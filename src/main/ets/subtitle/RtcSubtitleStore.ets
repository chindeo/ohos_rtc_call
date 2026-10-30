import {
  hasRtcSubtitleSayableText,
  parseRtcAsrSubtitleFrame,
  rtcSubtitleIdHash,
  rtcSubtitleSpeakerColor,
  rtcSubtitleSpeakerLabel,
  RtcAsrSubtitleFrame
} from './RtcAsrSubtitle'

export interface RtcSubtitleScheduler {
  setTimeout(callback: () => void, delayMs: number): number
  clearTimeout(timer: number): void
  now(): number
}

class RtcDefaultSubtitleScheduler implements RtcSubtitleScheduler {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs)
  }

  clearTimeout(timer: number): void {
    clearTimeout(timer)
  }

  now(): number {
    return Date.now()
  }
}

export interface RtcSubtitleStoreOptions {
  coalesceIntervalMs?: number
  maxLinesPerSession?: number
  maxRetainedClosedCalls?: number
  scheduler?: RtcSubtitleScheduler
  onLog?: (message: string) => void
}

export class RtcSubtitleLine {
  id: string = ''
  speaker: string = ''
  label: string = ''
  color: string = ''
  text: string = ''
  isFinal: boolean = false
  updatedAt: number = 0
}

export class RtcSubtitleSessionView {
  uid: string = ''
  uidHash: string = ''
  lines: RtcSubtitleLine[] = []
  closed: boolean = false
}

export type RtcSubtitleSnapshotListener = (sessions: RtcSubtitleSessionView[]) => void

class RtcSubtitleStream {
  speaker: string = ''
  label: string = ''
  color: string = ''
  currentLine?: RtcSubtitleLine
  hasSeq: boolean = false
  lastSeq: number = 0
  lastFlushAt: number = 0
  dirty: boolean = false
}

class RtcSubtitleSession {
  uid: string = ''
  uidHash: string = ''
  lines: RtcSubtitleLine[] = []
  streams: Map<string, RtcSubtitleStream> = new Map()
  closed: boolean = false
  flushTimer: number = -1
  lastUpdatedAt: number = 0
}

/**
 * 字幕是通话的旁路能力：这里任何一帧处理失败都只丢帧，异常不能溢出到信令分支，
 * 所以公开入口统一兜住 try/catch。
 */
export class RtcSubtitleStore {
  private static readonly DEFAULT_COALESCE_INTERVAL_MS: number = 200
  private static readonly DEFAULT_MAX_LINES: number = 200
  private static readonly DEFAULT_RETAINED_CLOSED_CALLS: number = 8
  private static readonly HEARTBEAT_EVERY_NOTIFIES: number = 40

  private sessions: Map<string, RtcSubtitleSession> = new Map()
  private listeners: RtcSubtitleSnapshotListener[] = []
  private scheduler: RtcSubtitleScheduler
  private coalesceIntervalMs: number
  private maxLinesPerSession: number
  private maxRetainedClosedCalls: number
  private onLog?: (message: string) => void
  private lineSeq: number = 0
  private disposed: boolean = false
  private receivedCount: number = 0
  private droppedCount: number = 0
  private notifyCount: number = 0

  constructor(options?: RtcSubtitleStoreOptions) {
    this.scheduler = (options && options.scheduler) || new RtcDefaultSubtitleScheduler()
    this.coalesceIntervalMs = RtcSubtitleStore.positiveOr(
      options ? options.coalesceIntervalMs : undefined, RtcSubtitleStore.DEFAULT_COALESCE_INTERVAL_MS)
    this.maxLinesPerSession = RtcSubtitleStore.positiveOr(
      options ? options.maxLinesPerSession : undefined, RtcSubtitleStore.DEFAULT_MAX_LINES)
    this.maxRetainedClosedCalls = RtcSubtitleStore.positiveOr(
      options ? options.maxRetainedClosedCalls : undefined, RtcSubtitleStore.DEFAULT_RETAINED_CLOSED_CALLS)
    this.onLog = options ? options.onLog : undefined
  }

  private static positiveOr(value: number | undefined, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : fallback
  }

  /** 返回 true 表示这一帧确实被字幕消费掉了，调用方可以据此打日志。 */
  ingestBroadcastData(data: string): boolean {
    if (this.disposed) {
      return false
    }
    try {
      const frame = parseRtcAsrSubtitleFrame(data)
      if (!frame) {
        return false
      }
      this.receivedCount += 1
      this.applyFrame(frame)
      return true
    } catch (error) {
      this.droppedCount += 1
      this.onLog?.(`rtc_subtitle ingest failed error=${String(error)}`)
      return false
    }
  }

  subscribe(listener: RtcSubtitleSnapshotListener): () => void {
    this.listeners.push(listener)
    listener(this.getSnapshots())
    return (): void => {
      this.listeners = this.listeners.filter((item: RtcSubtitleSnapshotListener) => item !== listener)
    }
  }

  getSnapshots(): RtcSubtitleSessionView[] {
    const views: RtcSubtitleSessionView[] = []
    this.sessions.forEach((session: RtcSubtitleSession): void => {
      views.push(RtcSubtitleStore.toView(session))
    })
    return views
  }

  getSnapshot(uid: string): RtcSubtitleSessionView | undefined {
    const session = this.sessions.get((uid || '').trim())
    return session ? RtcSubtitleStore.toView(session) : undefined
  }

  /**
   * 通话结束：停止后续更新，把仍在 partial 的行转终态，历史保留可回看。
   * 调用方按会话自己的 uid 逐路关闭，不在这里判还剩几路。
   */
  closeCall(uid: string, reason: string): void {
    if (this.disposed) {
      return
    }
    const key = (uid || '').trim()
    const session = this.sessions.get(key)
    if (!session) {
      return
    }
    session.closed = true
    session.lines.forEach((line: RtcSubtitleLine): void => {
      line.isFinal = true
    })
    session.streams.forEach((stream: RtcSubtitleStream): void => {
      stream.currentLine = undefined
      stream.dirty = false
    })
    this.clearFlushTimer(session)
    this.onLog?.(`rtc_subtitle call closed uid=${rtcSubtitleIdHash(key)} reason=${reason} lines=${session.lines.length}`)
    this.pruneClosedSessions()
    this.notify()
  }

  /**
   * 重新注册后字幕可能从头计数：只清 seq 基线，不清已显示的行，
   * 否则网关重新计数会把新帧整批误判成乱序丢掉。
   */
  resetSeqEpochs(reason: string): void {
    if (this.disposed) {
      return
    }
    let streams = 0
    this.sessions.forEach((session: RtcSubtitleSession): void => {
      session.streams.forEach((stream: RtcSubtitleStream): void => {
        stream.hasSeq = false
        stream.lastSeq = 0
        streams += 1
      })
    })
    if (streams > 0) {
      this.onLog?.(`rtc_subtitle seq reset reason=${reason} streams=${streams}`)
    }
  }

  dispose(): void {
    if (this.disposed) {
      return
    }
    this.sessions.forEach((session: RtcSubtitleSession): void => {
      this.clearFlushTimer(session)
    })
    this.sessions.clear()
    this.listeners = []
    this.disposed = true
  }

  private applyFrame(frame: RtcAsrSubtitleFrame): void {
    const session = this.ensureSession(frame.uid)
    if (!session || session.closed) {
      this.droppedCount += 1
      this.onLog?.(`rtc_subtitle drop reason=closed_call uid=${rtcSubtitleIdHash(frame.uid)}`)
      return
    }
    const stream = this.ensureStream(session, frame)
    if (frame.hasSeq && stream.hasSeq && frame.seq <= stream.lastSeq) {
      this.droppedCount += 1
      this.onLog?.(`rtc_subtitle drop reason=stale_seq uid=${rtcSubtitleIdHash(frame.uid)}` +
        ` speaker=${rtcSubtitleIdHash(frame.speaker)} seq=${frame.seq} last=${stream.lastSeq}`)
      return
    }
    if (frame.hasSeq) {
      stream.hasSeq = true
      stream.lastSeq = frame.seq
    }

    const text = frame.text
    const current = stream.currentLine
    const target = this.resolveTargetLine(stream, current, text)
    if (target === undefined) {
      if (!hasRtcSubtitleSayableText(text)) {
        // 只有标点或空文本：不产生新行，但 final 要把当前行收尾。
        if (frame.isFinal && current) {
          current.isFinal = true
          current.updatedAt = this.scheduler.now()
          this.markDirty(session, stream, true)
        } else {
          this.droppedCount += 1
        }
        return
      }
      const line = this.appendLine(session, stream, frame)
      line.text = text
      line.isFinal = frame.isFinal
      this.markDirty(session, stream, frame.isFinal)
      return
    }
    if (text.length > 0) {
      target.text = text
    }
    target.updatedAt = this.scheduler.now()
    if (frame.isFinal) {
      target.isFinal = true
    }
    this.markDirty(session, stream, frame.isFinal)
  }

  /**
   * 帧文本是累计语义：与当前行互为前缀（含 ASR 回改缩短）就整行替换，
   * 当前行已收尾或前缀断开才新起一行。
   */
  private resolveTargetLine(stream: RtcSubtitleStream,
    current: RtcSubtitleLine | undefined, text: string): RtcSubtitleLine | undefined {
    if (!current) {
      return undefined
    }
    if (current.isFinal) {
      return undefined
    }
    if (text.length === 0 || current.text.startsWith(text) || text.startsWith(current.text)) {
      return current
    }
    return undefined
  }

  private appendLine(session: RtcSubtitleSession, stream: RtcSubtitleStream,
    frame: RtcAsrSubtitleFrame): RtcSubtitleLine {
    this.lineSeq += 1
    const line = new RtcSubtitleLine()
    line.id = stream.speaker + '#' + this.lineSeq
    line.speaker = stream.speaker
    line.label = stream.label
    line.color = stream.color
    line.updatedAt = this.scheduler.now()
    session.lines.push(line)
    stream.currentLine = line
    if (session.lines.length > this.maxLinesPerSession) {
      session.lines.splice(0, session.lines.length - this.maxLinesPerSession)
    }
    return line
  }

  private ensureSession(uid: string): RtcSubtitleSession | undefined {
    const key = (uid || '').trim()
    if (key.length === 0) {
      return undefined
    }
    const existing = this.sessions.get(key)
    if (existing) {
      existing.lastUpdatedAt = this.scheduler.now()
      return existing
    }
    const session = new RtcSubtitleSession()
    session.uid = key
    session.uidHash = rtcSubtitleIdHash(key)
    session.lastUpdatedAt = this.scheduler.now()
    this.sessions.set(key, session)
    this.onLog?.(`rtc_subtitle session opened uid=${session.uidHash} calls=${this.sessions.size}`)
    return session
  }

  private ensureStream(session: RtcSubtitleSession, frame: RtcAsrSubtitleFrame): RtcSubtitleStream {
    const existing = session.streams.get(frame.speaker)
    if (existing) {
      if (existing.label.length === 0 || existing.label === frame.speaker) {
        existing.label = rtcSubtitleSpeakerLabel(frame.clientType, frame.speaker)
      }
      return existing
    }
    const stream = new RtcSubtitleStream()
    stream.speaker = frame.speaker
    stream.label = rtcSubtitleSpeakerLabel(frame.clientType, frame.speaker)
    stream.color = rtcSubtitleSpeakerColor(frame.speaker)
    stream.lastFlushAt = 0
    session.streams.set(frame.speaker, stream)
    return stream
  }

  private markDirty(session: RtcSubtitleSession, stream: RtcSubtitleStream, immediate: boolean): void {
    stream.dirty = true
    session.lastUpdatedAt = this.scheduler.now()
    if (this.listeners.length === 0) {
      // 组件解除帧回调后不再排定时器，重新订阅时按最新累计文本整份刷新。
      return
    }
    if (immediate) {
      this.clearFlushTimer(session)
      this.flushSession(session)
      return
    }
    if (session.flushTimer >= 0) {
      return
    }
    const now = this.scheduler.now()
    let delay = this.coalesceIntervalMs
    session.streams.forEach((pending: RtcSubtitleStream): void => {
      if (pending.dirty) {
        const remaining = pending.lastFlushAt + this.coalesceIntervalMs - now
        if (remaining < delay) {
          delay = remaining
        }
      }
    })
    if (delay < 0) {
      delay = 0
    }
    session.flushTimer = this.scheduler.setTimeout(() => {
      session.flushTimer = -1
      this.flushSession(session)
    }, delay)
  }

  private flushSession(session: RtcSubtitleSession): void {
    let flushed = 0
    session.streams.forEach((stream: RtcSubtitleStream): void => {
      if (stream.dirty) {
        stream.dirty = false
        stream.lastFlushAt = this.scheduler.now()
        flushed += 1
      }
    })
    if (flushed > 0) {
      this.notify()
    }
  }

  private clearFlushTimer(session: RtcSubtitleSession): void {
    if (session.flushTimer >= 0) {
      this.scheduler.clearTimeout(session.flushTimer)
      session.flushTimer = -1
    }
  }

  private pruneClosedSessions(): void {
    const closed: RtcSubtitleSession[] = []
    this.sessions.forEach((session: RtcSubtitleSession): void => {
      if (session.closed) {
        closed.push(session)
      }
    })
    if (closed.length <= this.maxRetainedClosedCalls) {
      return
    }
    closed.sort((a: RtcSubtitleSession, b: RtcSubtitleSession): number => a.lastUpdatedAt - b.lastUpdatedAt)
    const dropCount = closed.length - this.maxRetainedClosedCalls
    for (let i = 0; i < dropCount; i += 1) {
      this.sessions.delete(closed[i].uid)
    }
  }

  private notify(): void {
    if (this.listeners.length === 0) {
      return
    }
    this.notifyCount += 1
    if (this.notifyCount % RtcSubtitleStore.HEARTBEAT_EVERY_NOTIFIES === 0) {
      // 帧数远大于刷新次数才是 200ms 合并真的生效的证据，光看界面判不出来。
      this.onLog?.(`rtc_subtitle heartbeat frames=${this.receivedCount} renders=${this.notifyCount}` +
        ` dropped=${this.droppedCount} calls=${this.sessions.size}`)
    }
    const snapshots = this.getSnapshots()
    this.listeners.slice().forEach((listener: RtcSubtitleSnapshotListener): void => {
      try {
        listener(snapshots)
      } catch (error) {
        this.onLog?.(`rtc_subtitle listener failed error=${String(error)}`)
      }
    })
  }

  private static toView(session: RtcSubtitleSession): RtcSubtitleSessionView {
    const view = new RtcSubtitleSessionView()
    view.uid = session.uid
    view.uidHash = session.uidHash
    view.lines = session.lines.slice()
    view.closed = session.closed
    return view
  }
}
