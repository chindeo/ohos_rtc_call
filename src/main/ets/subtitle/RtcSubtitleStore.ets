import {
  hasRtcSubtitleSayableText,
  parseRtcAsrSubtitleFrame,
  rtcSubtitleIdHash,
  rtcSubtitleSettledLength,
  rtcSubtitleSpeakerColor,
  rtcSubtitleSpeakerLabel,
  rtcSubtitleSplitSentences,
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
  /** 最近一帧的整场累计文本，用来判断这一帧是不是接着上一句往下说 */
  accum: string = ''
  /** accum 里已经落成行的前缀长度，剩下的才是正在说的残句 */
  settledLen: number = 0
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
    // 空文本和只有标点的帧不带词，不碰已累计文本也不动行；final 只负责把残句收尾。
    if (text.length === 0 || !hasRtcSubtitleSayableText(text)) {
      if (frame.isFinal) {
        this.finishStream(session, stream)
      } else {
        this.droppedCount += 1
      }
      return
    }

    // 累计文本必须是上一次的延长；被改写或换了一段话就重新起一段，老残句当场收尾。
    if (!this.continuesAccum(stream, text)) {
      this.freezeCurrentLine(stream)
      stream.accum = ''
      stream.settledLen = 0
    }
    stream.accum = text
    if (text.length < stream.settledLen) {
      stream.settledLen = text.length
    }
    let cut = rtcSubtitleSettledLength(text)
    if (cut < stream.settledLen) {
      cut = stream.settledLen
    }
    if (frame.isFinal) {
      cut = text.length
    }
    let committed = false
    if (cut > stream.settledLen) {
      this.commitSentences(session, stream, text.substring(stream.settledLen, cut))
      stream.settledLen = cut
      committed = true
    }

    const tail = text.substring(cut)
    if (!frame.isFinal && tail.length > 0 && hasRtcSubtitleSayableText(tail)) {
      const line = stream.currentLine ? stream.currentLine : this.appendLine(session, stream)
      stream.currentLine = line
      line.text = tail
      line.updatedAt = this.scheduler.now()
      this.markDirty(session, stream, false)
      return
    }
    if (frame.isFinal) {
      this.finishStream(session, stream)
      return
    }
    // 刚好落在句末标点上的 partial：整句已经成行但没有残句，也要让这一行刷到界面上。
    if (committed) {
      this.markDirty(session, stream, false)
      return
    }
    // 只有标点或空白：界面不变，也不新起一行。
    this.droppedCount += 1
  }

  /** 同一句话的连续累计：新文本把旧文本整段包在里面才算接得上。 */
  private continuesAccum(stream: RtcSubtitleStream, text: string): boolean {
    const accum = stream.accum
    if (accum.length === 0) {
      return true
    }
    if (text.length >= accum.length) {
      return text.startsWith(accum)
    }
    return accum.startsWith(text)
  }

  /**
   * 落定的整句各自成一行，这样底部字幕像正常视频字幕一样一句一句往前走，
   * 不会攒成一大坨。第一句复用在显示的那行，避免残句和整句重复出现。
   */
  private commitSentences(session: RtcSubtitleSession, stream: RtcSubtitleStream, part: string): void {
    const sentences = rtcSubtitleSplitSentences(part)
    for (let i = 0; i < sentences.length; i += 1) {
      const sentence = sentences[i]
      if (!hasRtcSubtitleSayableText(sentence)) {
        continue
      }
      const open = stream.currentLine
      if (i === 0 && open && !open.isFinal) {
        open.text = sentence
        open.isFinal = true
        open.updatedAt = this.scheduler.now()
        stream.currentLine = undefined
        continue
      }
      const line = this.appendLine(session, stream)
      line.text = sentence
      line.isFinal = true
    }
  }

  /**
   * 这一路说完了：残句转终态，下一段话从新行开始。
   * accum 和 settledLen 要留着 —— 网关的 text 是整场累计，下一帧还会把已显示的句子带上，
   * 清掉就会把同一批句子再落一遍行。
   */
  private finishStream(session: RtcSubtitleSession, stream: RtcSubtitleStream): void {
    this.freezeCurrentLine(stream)
    this.markDirty(session, stream, true)
  }

  private freezeCurrentLine(stream: RtcSubtitleStream): void {
    const current = stream.currentLine
    if (!current) {
      return
    }
    current.isFinal = true
    current.updatedAt = this.scheduler.now()
    stream.currentLine = undefined
  }

  private appendLine(session: RtcSubtitleSession, stream: RtcSubtitleStream): RtcSubtitleLine {
    this.lineSeq += 1
    const line = new RtcSubtitleLine()
    line.id = stream.speaker + '#' + this.lineSeq
    line.speaker = stream.speaker
    line.label = stream.label
    line.color = stream.color
    line.updatedAt = this.scheduler.now()
    session.lines.push(line)
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
