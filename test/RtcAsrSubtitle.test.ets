import { describe, it, expect } from '@ohos/hypium'
import {
  hasRtcSubtitleSayableText,
  parseRtcAsrSubtitleFrame,
  rtcSubtitleSpeakerColor,
  rtcSubtitleSpeakerLabel
} from '../src/main/ets/subtitle/RtcAsrSubtitle'
import {
  RtcSubtitleLine,
  RtcSubtitleScheduler,
  RtcSubtitleSessionView,
  RtcSubtitleStore
} from '../src/main/ets/subtitle/RtcSubtitleStore'

class FakeTimer {
  id: number = 0
  callback: () => void = () => {}
  dueAt: number = 0
  active: boolean = true
}

class FakeSubtitleScheduler implements RtcSubtitleScheduler {
  timers: FakeTimer[] = []
  currentMs: number = 1000
  private nextId: number = 1

  setTimeout(callback: () => void, delayMs: number): number {
    const timer = new FakeTimer()
    timer.id = this.nextId
    timer.callback = callback
    timer.dueAt = this.currentMs + (delayMs > 0 ? delayMs : 0)
    this.nextId += 1
    this.timers.push(timer)
    return timer.id
  }

  clearTimeout(timerId: number): void {
    this.timers.forEach((timer: FakeTimer): void => {
      if (timer.id === timerId) {
        timer.active = false
      }
    })
  }

  now(): number {
    return this.currentMs
  }

  advance(ms: number): void {
    const target = this.currentMs + ms
    let guard = 0
    while (guard < 500) {
      guard += 1
      let due: FakeTimer | undefined = undefined
      for (let i = 0; i < this.timers.length; i += 1) {
        const timer = this.timers[i]
        if (timer.active && timer.dueAt <= target && (!due || timer.dueAt < due.dueAt)) {
          due = timer
        }
      }
      if (!due) {
        break
      }
      due.active = false
      if (due.dueAt > this.currentMs) {
        this.currentMs = due.dueAt
      }
      due.callback()
    }
    this.currentMs = target
  }
}

interface SubtitleFrameInput {
  uid?: string
  seq?: number
  state?: string
  text?: string
  utt?: number
  end?: boolean
  gen?: number
  beginMs?: number
  endMs?: number
  source_number?: string
  client_type?: string
  role?: string
}

/** v2 一句一帧：没给 utt 时按 seq 当不同句子，没给 end 时按还没闭合处理。 */
function frameJson(input: SubtitleFrameInput): string {
  return JSON.stringify({
    type: 'asr_subtitle',
    uid: input.uid,
    seq: input.seq,
    state: input.state === undefined ? 'partial' : input.state,
    utterance_id: input.utt === undefined ? input.seq : input.utt,
    sentence_end: input.end === true,
    sentence_text: input.text,
    begin_ms: input.beginMs,
    end_ms: input.endMs,
    generation: input.gen,
    source_number: input.source_number,
    client_type: input.client_type,
    role: input.role,
    language: 'zh',
    ts: '2026-10-30T10:56:15+08:00'
  })
}

/** 网关的下行形状：信封 data 里再包一层 BroadcastRequest，业务载荷仍是字符串。 */
function broadcastData(frameText: string): string {
  return JSON.stringify({
    commonRequest: { grpcFrom: '1001', grpcTo: '1022', locId: 'L1', hospitalId: 'H1' },
    data: frameText
  })
}

function snapshotLines(store: RtcSubtitleStore, uid: string): RtcSubtitleLine[] {
  const view = store.getSnapshot(uid)
  return view ? view.lines : []
}

function lineTexts(lines: RtcSubtitleLine[]): string {
  let text = ''
  lines.forEach((line: RtcSubtitleLine): void => {
    text += (text.length > 0 ? ' / ' : '') + line.text + (line.isFinal ? '[f]' : '[p]')
  })
  return text
}

function feed(store: RtcSubtitleStore, input: SubtitleFrameInput): void {
  store.ingestBroadcastData(broadcastData(frameJson(input)))
}

class SubtitleProbe {
  renders: number = 0
  sessions: RtcSubtitleSessionView[] = []

  record(sessions: RtcSubtitleSessionView[]): void {
    this.renders += 1
    this.sessions = sessions
  }
}

export default function rtcAsrSubtitleTest() {
  describe('RtcAsrSubtitle', () => {
    it('reads a v2 frame through the nested broadcast layers', 0, () => {
      const frame = parseRtcAsrSubtitleFrame(broadcastData(frameJson({
        uid: 'u1', seq: 7, utt: 4, end: true, text: '现在已经明确，所谓的996。',
        gen: 1, beginMs: 34200, endMs: 38150, source_number: '1022', client_type: 'bed', role: 'bed'
      })))
      expect(frame !== undefined).assertEqual(true)
      expect(frame ? frame.uid : '').assertEqual('u1')
      expect(frame ? frame.speaker : '').assertEqual('1022')
      expect(frame ? frame.sentenceText : '').assertEqual('现在已经明确，所谓的996。')
      expect(frame ? frame.utteranceId : 0).assertEqual(4)
      expect(frame ? frame.sentenceEnd : false).assertEqual(true)
      expect(frame ? frame.generation : 0).assertEqual(1)
      expect(frame ? frame.beginMs : 0).assertEqual(34200)
      expect(frame ? frame.endMs : 0).assertEqual(38150)
      expect(frame ? frame.role : '').assertEqual('bed')
      expect(frame ? frame.sessionFinal : true).assertEqual(false)
      expect(frame ? frame.seq : 0).assertEqual(7)
    })

    it('accepts a bare frame and drops everything else without throwing', 0, () => {
      expect(parseRtcAsrSubtitleFrame(frameJson({ uid: 'u1', text: '你好', source_number: '1022' })) !== undefined)
        .assertEqual(true)
      expect(parseRtcAsrSubtitleFrame('{"status":"挂断","uid":"u1"}') === undefined).assertEqual(true)
      expect(parseRtcAsrSubtitleFrame('{"type":"call_media_downgraded","uid":"u1"}') === undefined).assertEqual(true)
      expect(parseRtcAsrSubtitleFrame('not json at all') === undefined).assertEqual(true)
      expect(parseRtcAsrSubtitleFrame('') === undefined).assertEqual(true)
      expect(parseRtcAsrSubtitleFrame('{"type":"asr_subtitle","text":"你好"}') === undefined).assertEqual(true)
      expect(parseRtcAsrSubtitleFrame(
        '{"type":"asr_subtitle","uid":"u1","text":"你好"}') === undefined).assertEqual(true)
      const noSeq = parseRtcAsrSubtitleFrame(
        '{"type":"asr_subtitle","uid":"u1","source_number":"1022","sentence_text":"你好","seq":"7"}')
      expect(noSeq !== undefined).assertEqual(true)
      expect(noSeq ? noSeq.hasSeq : true).assertEqual(false)
      // 旧 v1 帧（只有 text）解析得过，但没有 sentence_text，落不成行：不会显示也不会崩。
      const legacy = parseRtcAsrSubtitleFrame(
        '{"type":"asr_subtitle","uid":"u1","source_number":"1022","text":"整场累计"}')
      expect(legacy !== undefined).assertEqual(true)
      expect(legacy ? legacy.sentenceText : 'x').assertEqual('')
    })

    it('treats punctuation-only and empty text as not sayable', 0, () => {
      expect(hasRtcSubtitleSayableText('')).assertEqual(false)
      expect(hasRtcSubtitleSayableText('  ，。、！？…—  ')).assertEqual(false)
      expect(hasRtcSubtitleSayableText('好')).assertEqual(true)
      expect(hasRtcSubtitleSayableText('A1')).assertEqual(true)
    })

    it('labels speakers by role and keeps colors stable per number', 0, () => {
      expect(rtcSubtitleSpeakerLabel('bed', '1022')).assertEqual('1022床')
      expect(rtcSubtitleSpeakerLabel('host', '1001')).assertEqual('主机 1001')
      expect(rtcSubtitleSpeakerLabel('door', '1005')).assertEqual('门口 1005')
      expect(rtcSubtitleSpeakerLabel('nurses', '1033')).assertEqual('护士站 1033')
      expect(rtcSubtitleSpeakerLabel('nurse', '1033')).assertEqual('护士站 1033')
      expect(rtcSubtitleSpeakerLabel('doctor', '2001')).assertEqual('医生 2001')
      expect(rtcSubtitleSpeakerLabel('watch', '9001')).assertEqual('手表 9001')
      expect(rtcSubtitleSpeakerLabel('other', '1033')).assertEqual('1033')
      expect(rtcSubtitleSpeakerLabel('', '1033')).assertEqual('1033')
      expect(rtcSubtitleSpeakerLabel('other', '')).assertEqual('对方')
      expect(rtcSubtitleSpeakerColor('1022')).assertEqual(rtcSubtitleSpeakerColor('1022'))
      expect(rtcSubtitleSpeakerColor('1022').length).assertEqual(9)
    })

    it('keeps one line per utterance and replaces it in place', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '现在已经明确', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, utt: 1, text: '现在已经明确，所谓的996。', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('现在已经明确，所谓的996。[p]')
      feed(store, { uid: 'u1', seq: 3, utt: 2, end: true, text: '这是下一句的内容。', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1')))
        .assertEqual('现在已经明确，所谓的996。[p] / 这是下一句的内容。[f]')
      store.dispose()
    })

    it('freezes only on sentence_end, never on punctuation', 0, () => {
      const store = new RtcSubtitleStore()
      // 识别引擎在半句中间打句号：v1 会被它断成碎句，v2 只看 sentence_end。
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '那么如果求职者在。', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('那么如果求职者在。[p]')
      feed(store, { uid: 'u1', seq: 2, utt: 1, text: '那么如果求职者在。入职的时候', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('那么如果求职者在。入职的时候[p]')
      feed(store, { uid: 'u1', seq: 3, utt: 1, end: true, text: '那么如果求职者在。入职的时候被要求签协议。',
        source_number: '1022' })
      expect(snapshotLines(store, 'u1').length).assertEqual(1)
      expect(lineTexts(snapshotLines(store, 'u1')))
        .assertEqual('那么如果求职者在。入职的时候被要求签协议。[f]')
      store.dispose()
    })

    it('freezes the open line when the session itself ends', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '没收尾的半句', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, utt: 2, text: '会话收尾这句', state: 'final', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('没收尾的半句[p] / 会话收尾这句[f]')
      store.dispose()
    })

    it('ignores a legacy frame that carries no sentence_text', 0, () => {
      const store = new RtcSubtitleStore()
      expect(store.ingestBroadcastData(broadcastData(
        '{"type":"asr_subtitle","uid":"u1","source_number":"1022","text":"整场累计","seq":1,"state":"final"}')))
        .assertEqual(true)
      expect(snapshotLines(store, 'u1').length).assertEqual(0)
      store.dispose()
    })

    it('logs one reconciliation line per frame without the raw text by default', 0, () => {
      const logs: string[] = []
      const store = new RtcSubtitleStore({ onLog: (message: string): void => { logs.push(message) } })
      feed(store, { uid: 'u1', seq: 7, utt: 4, end: true, gen: 1, beginMs: 34200, endMs: 38150,
        text: '现在已经明确，所谓的996。', source_number: '1022', role: 'bed' })
      const line = logs.join('\n')
      expect(line.indexOf('rtc_subtitle: uid=u1 src=1022 seq=7 utt=4 end=true gen=1') >= 0).assertEqual(true)
      expect(line.indexOf('begin_ms=34200 end_ms=38150') >= 0).assertEqual(true)
      expect(line.indexOf('local_recv_ms=') >= 0).assertEqual(true)
      expect(line.indexOf('text_len=') >= 0).assertEqual(true)
      expect(line.indexOf('text_hash=') >= 0).assertEqual(true)
      expect(line.indexOf('text=现在') >= 0).assertEqual(false)
      store.dispose()

      const rawLogs: string[] = []
      const verbose = new RtcSubtitleStore({
        logFrameText: true,
        onLog: (message: string): void => { rawLogs.push(message) }
      })
      feed(verbose, { uid: 'u1', seq: 7, utt: 4, end: true, text: '现在已经明确。', source_number: '1022' })
      expect(rawLogs.join('\n').indexOf('text=现在已经明确。') >= 0).assertEqual(true)
      verbose.dispose()
    })

    it('counts a seq jump as sentences lost for good', 0, () => {
      const logs: string[] = []
      const store = new RtcSubtitleStore({ onLog: (message: string): void => { logs.push(message) } })
      feed(store, { uid: 'u1', seq: 3, utt: 3, text: '第一句内容', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 7, utt: 7, text: '第五句内容', source_number: '1022' })
      expect(logs.join('\n').indexOf('rtc_subtitle gap uid=') >= 0).assertEqual(true)
      expect(logs.join('\n').indexOf('from=3 to=7 missed=3') >= 0).assertEqual(true)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('第一句内容[p] / 第五句内容[p]')
      store.dispose()
    })

    it('drops frames that carry no sayable sentence_text', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, utt: 2, text: '，。', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 3, utt: 3, text: '', source_number: '1022' })
      expect(snapshotLines(store, 'u1').length).assertEqual(1)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p]')
      store.dispose()
    })

    it('drops stale and duplicated seq without touching the lines', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 5, utt: 5, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 7, utt: 7, text: '你好世界', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 6, utt: 6, text: '迟到帧', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 7, utt: 8, text: '重复帧', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p] / 你好世界[p]')
      store.dispose()
    })

    it('keeps one container per uid so multi-call never mixes', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, text: '床旁这句', source_number: '1022' })
      feed(store, { uid: 'u2', seq: 1, text: '主机这句', source_number: '1001' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('床旁这句[p]')
      expect(lineTexts(snapshotLines(store, 'u2'))).assertEqual('主机这句[p]')
      expect(store.getSnapshots().length).assertEqual(2)
      store.dispose()
    })

    it('separates speakers inside one call', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '护士说', source_number: '1001', role: 'host' })
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '患者说', source_number: '1022', role: 'bed' })
      const lines = snapshotLines(store, 'u1')
      expect(lines.length).assertEqual(2)
      expect(lines[0].label).assertEqual('主机 1001')
      expect(lines[1].label).assertEqual('1022床')
      expect(lines[0].color).assertEqual(rtcSubtitleSpeakerColor('1001'))
      expect(lines[1].color).assertEqual(rtcSubtitleSpeakerColor('1022'))
      store.dispose()
    })

    it('drops the local speaker so the screen never shows your own words', 0, () => {
      const logs: string[] = []
      const store = new RtcSubtitleStore({ onLog: (message: string): void => { logs.push(message) } })
      store.setLocalSpeakers(['1001'], 'test')
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '主机自己说的这句', source_number: '1001', role: 'host' })
      feed(store, { uid: 'u1', seq: 2, utt: 1, text: '床旁说的那句', source_number: '1022', role: 'bed' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('床旁说的那句[p]')
      const joined = logs.join('\n')
      expect(joined.indexOf('self=true') >= 0).assertEqual(true)
      expect(joined.indexOf('self=false') >= 0).assertEqual(true)
      store.dispose()
    })

    it('keeps the transcript across a new generation and never renumbers history', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, utt: 11, gen: 1, text: '重连前那句', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, utt: 12, gen: 2, text: '重连后那句', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('重连前那句[p] / 重连后那句[p]')
      store.dispose()
    })

    it('coalesces frames of one sentence into a single render per interval', 0, () => {
      const scheduler = new FakeSubtitleScheduler()
      const store = new RtcSubtitleStore({ scheduler })
      const probe = new SubtitleProbe()
      store.subscribe((sessions: RtcSubtitleSessionView[]): void => {
        probe.record(sessions)
      })
      expect(probe.renders).assertEqual(1)
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, utt: 1, text: '你好世', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 3, utt: 1, text: '你好世界', source_number: '1022' })
      expect(probe.renders).assertEqual(1)
      scheduler.advance(0)
      expect(probe.renders).assertEqual(2)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好世界[p]')
      feed(store, { uid: 'u1', seq: 4, utt: 1, text: '你好世界啊', source_number: '1022' })
      scheduler.advance(199)
      expect(probe.renders).assertEqual(2)
      scheduler.advance(1)
      expect(probe.renders).assertEqual(3)
      store.dispose()
    })

    it('renders a session-final frame without waiting for the coalescing window', 0, () => {
      const scheduler = new FakeSubtitleScheduler()
      const store = new RtcSubtitleStore({ scheduler })
      const probe = new SubtitleProbe()
      store.subscribe((sessions: RtcSubtitleSessionView[]): void => {
        probe.record(sessions)
      })
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '你好', source_number: '1022' })
      const rendersBeforeFinal = probe.renders
      feed(store, { uid: 'u1', seq: 2, utt: 1, state: 'final', text: '你好。', source_number: '1022' })
      expect(probe.renders).assertEqual(rendersBeforeFinal + 1)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好。[f]')
      store.dispose()
    })

    it('finalizes open lines and refuses later frames once the call is closed', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '你好', source_number: '1022' })
      store.closeCall('u1', 'test hangup')
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[f]')
      const view = store.getSnapshot('u1')
      expect(view ? view.closed : false).assertEqual(true)
      feed(store, { uid: 'u1', seq: 2, utt: 2, text: '迟到帧', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[f]')
      store.closeCall('missing-uid', 'no such call')
      store.dispose()
    })

    it('lets a restarted seq counter through after a re-register', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 9, utt: 9, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 1, utt: 1, text: '新一句', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p]')
      store.resetSeqEpochs('register')
      feed(store, { uid: 'u1', seq: 1, utt: 10, text: '新一句', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p] / 新一句[p]')
      store.dispose()
    })

    it('keeps unknown broadcasts unconsumed and stops after dispose', 0, () => {
      const store = new RtcSubtitleStore()
      expect(store.ingestBroadcastData(broadcastData(
        frameJson({ uid: 'u1', seq: 1, text: '你好', source_number: '1022' })))).assertEqual(true)
      expect(store.ingestBroadcastData('{"type":"hold_switch","info":"{}"}')).assertEqual(false)
      expect(store.ingestBroadcastData(broadcastData('{"status":"离线挂断"}'))).assertEqual(false)
      expect(store.ingestBroadcastData('')).assertEqual(false)
      store.dispose()
      expect(store.ingestBroadcastData(broadcastData(
        frameJson({ uid: 'u1', seq: 2, text: 'Disposed', source_number: '1022' })))).assertEqual(false)
    })
  })
}
