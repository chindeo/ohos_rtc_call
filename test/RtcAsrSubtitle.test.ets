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
  source_number?: string
  client_type?: string
}

function frameJson(input: SubtitleFrameInput): string {
  return JSON.stringify({
    type: 'asr_subtitle',
    uid: input.uid,
    seq: input.seq,
    state: input.state === undefined ? 'partial' : input.state,
    text: input.text,
    source_number: input.source_number,
    client_type: input.client_type,
    language: 'zh',
    ts: '2026-10-30T10:12:33+08:00'
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
    it('reads a subtitle frame through the nested broadcast layers', 0, () => {
      const frame = parseRtcAsrSubtitleFrame(broadcastData(
        frameJson({ uid: 'u1', seq: 3, text: '你好', source_number: '1022', client_type: 'bed' })
      ))
      expect(frame !== undefined).assertEqual(true)
      expect(frame ? frame.uid : '').assertEqual('u1')
      expect(frame ? frame.speaker : '').assertEqual('1022')
      expect(frame ? frame.text : '').assertEqual('你好')
      expect(frame ? frame.isFinal : true).assertEqual(false)
      expect(frame ? frame.seq : 0).assertEqual(3)
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
        '{"type":"asr_subtitle","uid":"u1","source_number":"1022","text":"你好","seq":"7"}')
      expect(noSeq !== undefined).assertEqual(true)
      expect(noSeq ? noSeq.hasSeq : true).assertEqual(false)
    })

    it('treats punctuation-only and empty text as not sayable', 0, () => {
      expect(hasRtcSubtitleSayableText('')).assertEqual(false)
      expect(hasRtcSubtitleSayableText('  ，。、！？…—  ')).assertEqual(false)
      expect(hasRtcSubtitleSayableText('好')).assertEqual(true)
      expect(hasRtcSubtitleSayableText('A1')).assertEqual(true)
    })

    it('formats speaker labels and keeps colors stable per number', 0, () => {
      expect(rtcSubtitleSpeakerLabel('bed', '1022')).assertEqual('1022床')
      expect(rtcSubtitleSpeakerLabel('host', '1001')).assertEqual('主机 1001')
      expect(rtcSubtitleSpeakerLabel('door', '1005')).assertEqual('门口 1005')
      expect(rtcSubtitleSpeakerLabel('', '1022')).assertEqual('1022')
      expect(rtcSubtitleSpeakerColor('1022')).assertEqual(rtcSubtitleSpeakerColor('1022'))
      expect(rtcSubtitleSpeakerColor('1022').length).assertEqual(9)
    })

    it('replaces the open line while the cumulative text keeps its prefix', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, text: '你好，世界', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好，世界[p]')
      store.dispose()
    })

    it('starts a new line when the text diverges or the previous line is final', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, text: '再见', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p] / 再见[p]')
      feed(store, { uid: 'u1', seq: 3, state: 'final', text: '再见。', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 4, text: '下一句', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p] / 再见。[f] / 下一句[p]')
      store.dispose()
    })

    it('ignores punctuation-only frames and closes the line on a final empty frame', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, text: '，。', source_number: '1022' })
      expect(snapshotLines(store, 'u1').length).assertEqual(1)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p]')
      feed(store, { uid: 'u1', seq: 3, state: 'final', text: '', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[f]')
      store.dispose()
    })

    it('drops stale and duplicated seq', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 5, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 7, text: '你好世界', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 6, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 7, text: '重写', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好世界[p]')
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
      feed(store, { uid: 'u1', seq: 1, text: '护士说', source_number: '1001', client_type: 'host' })
      feed(store, { uid: 'u1', seq: 1, text: '患者说', source_number: '1022', client_type: 'bed' })
      const lines = snapshotLines(store, 'u1')
      expect(lines.length).assertEqual(2)
      expect(lines[0].label).assertEqual('主机 1001')
      expect(lines[1].label).assertEqual('1022床')
      expect(lines[0].color).assertEqual(rtcSubtitleSpeakerColor('1001'))
      expect(lines[1].color).assertEqual(rtcSubtitleSpeakerColor('1022'))
      store.dispose()
    })

    it('coalesces partial frames into one render per interval', 0, () => {
      const scheduler = new FakeSubtitleScheduler()
      const store = new RtcSubtitleStore({ scheduler })
      const probe = new SubtitleProbe()
      store.subscribe((sessions: RtcSubtitleSessionView[]): void => {
        probe.record(sessions)
      })
      expect(probe.renders).assertEqual(1)
      feed(store, { uid: 'u1', seq: 1, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 2, text: '你好世', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 3, text: '你好世界', source_number: '1022' })
      expect(probe.renders).assertEqual(1)
      scheduler.advance(0)
      expect(probe.renders).assertEqual(2)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好世界[p]')
      feed(store, { uid: 'u1', seq: 4, text: '你好世界啊', source_number: '1022' })
      scheduler.advance(199)
      expect(probe.renders).assertEqual(2)
      scheduler.advance(1)
      expect(probe.renders).assertEqual(3)
      store.dispose()
    })

    it('renders a final frame without waiting for the coalescing window', 0, () => {
      const scheduler = new FakeSubtitleScheduler()
      const store = new RtcSubtitleStore({ scheduler })
      const probe = new SubtitleProbe()
      store.subscribe((sessions: RtcSubtitleSessionView[]): void => {
        probe.record(sessions)
      })
      feed(store, { uid: 'u1', seq: 1, text: '你好', source_number: '1022' })
      const rendersBeforeFinal = probe.renders
      feed(store, { uid: 'u1', seq: 2, state: 'final', text: '你好。', source_number: '1022' })
      expect(probe.renders).assertEqual(rendersBeforeFinal + 1)
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好。[f]')
      store.dispose()
    })

    it('finalizes open lines and refuses later frames once the call is closed', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 1, text: '你好', source_number: '1022' })
      store.closeCall('u1', 'test hangup')
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[f]')
      const view = store.getSnapshot('u1')
      expect(view ? view.closed : false).assertEqual(true)
      feed(store, { uid: 'u1', seq: 2, text: '迟到帧', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[f]')
      store.closeCall('missing-uid', 'no such call')
      store.dispose()
    })

    it('lets a restarted seq counter through after a re-register', 0, () => {
      const store = new RtcSubtitleStore()
      feed(store, { uid: 'u1', seq: 9, text: '你好', source_number: '1022' })
      feed(store, { uid: 'u1', seq: 1, text: '新一句', source_number: '1022' })
      expect(lineTexts(snapshotLines(store, 'u1'))).assertEqual('你好[p]')
      store.resetSeqEpochs('register')
      feed(store, { uid: 'u1', seq: 1, text: '新一句', source_number: '1022' })
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
