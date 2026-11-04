import { describe, it, expect } from '@ohos/hypium'
import {
  normalizeRtcSubtitleHexColor,
  parseRtcSubtitleStyleFrame,
  rtcSubtitleBackgroundArgb,
  RtcSubtitleStyleSpec
} from '../src/main/ets/subtitle/RtcSubtitleStyle'
import { RtcSubtitleScheduler, RtcSubtitleStore } from '../src/main/ets/subtitle/RtcSubtitleStore'
import { RtcSubtitleStyleCache } from '../src/main/ets/subtitle/RtcSubtitleStyleCache'
import { RtcStartupDataCacheStore } from '../src/main/ets/core/RtcStartupDataCache'

/** 替身存储：把偏好读写换成内存表，持久化链路就能在本机跑完。 */
class StyleCacheMemoryStore implements RtcStartupDataCacheStore {
  values: Record<string, string> = {}
  lastWrite: Promise<void> = Promise.resolve()

  async get(key: string): Promise<string> {
    const value = this.values[key]
    return value ? value : ''
  }

  async put(key: string, value: string): Promise<void> {
    this.values[key] = value
  }

  async remove(key: string): Promise<void> {
    delete this.values[key]
  }
}

const CACHED_STYLE_FRAME_TEXT = '{"type":"asr_subtitle_style","style_version":7,' +
  '"font_size":28,"text_color":"#FFFFFF","background_color":"#101010",' +
  '"background_opacity":80,"stroke_color":"#000000","stroke_width":1}'

class StyleFakeScheduler implements RtcSubtitleScheduler {
  currentMs: number = 1000
  private nextId: number = 1
  private callbacks: Map<number, () => void> = new Map()

  setTimeout(callback: () => void, delayMs: number): number {
    const id = this.nextId
    this.nextId += 1
    this.callbacks.set(id, callback)
    return id
  }

  clearTimeout(timerId: number): void {
    this.callbacks.delete(timerId)
  }

  now(): number {
    this.currentMs += 1
    return this.currentMs
  }

  flush(): void {
    const pending: (() => void)[] = []
    this.callbacks.forEach((callback: () => void): void => {
      pending.push(callback)
    })
    this.callbacks.clear()
    pending.forEach((callback: () => void): void => {
      callback()
    })
  }
}

function bodyFrame(seq: number, utterance: number, text: string, sentenceEnd: boolean): string {
  return JSON.stringify({
    type: 'asr_subtitle',
    uid: 'uid-style-test',
    source_number: '1022',
    role: 'bed',
    seq: seq,
    utterance_id: utterance,
    sentence_end: sentenceEnd,
    sentence_text: text
  })
}

function styleFrame(version: number, extraJson: string): string {
  return '{"type":"asr_subtitle_style","style_version":' + version + extraJson + '}'
}

export default function rtcSubtitleStyleTest() {
  describe('RtcSubtitleStyle', () => {
    it('parses a direct style frame with all fields', 0, () => {
      const frame = parseRtcSubtitleStyleFrame(styleFrame(3,
        ',"font_size":26,"text_color":"#FFFFFF","background_color":"#000000",' +
        '"background_opacity":70,"stroke_color":"#000000","stroke_width":2'))
      expect(frame !== undefined).assertTrue()
      if (!frame) {
        return
      }
      expect(frame.styleVersion).assertEqual(3)
      expect(frame.style.fontSize).assertEqual(26)
      expect(frame.style.backgroundOpacity).assertEqual(70)
      expect(frame.style.strokeWidth).assertEqual(2)
      expect(frame.fallbackFields.length).assertEqual(0)
    })

    it('parses the three layer nested envelope', 0, () => {
      const inner = styleFrame(5, ',"font_size":30')
      const wrapped = JSON.stringify({ commonRequest: {}, data: inner })
      const frame = parseRtcSubtitleStyleFrame(JSON.stringify({ data: wrapped }))
      expect(frame !== undefined).assertTrue()
      if (!frame) {
        return
      }
      expect(frame.styleVersion).assertEqual(5)
      expect(frame.style.fontSize).assertEqual(30)
    })

    it('fills missing fields with built-in defaults', 0, () => {
      const frame = parseRtcSubtitleStyleFrame(JSON.stringify({ type: 'asr_subtitle_style', style_version: 1 }))
      expect(frame !== undefined).assertTrue()
      if (!frame) {
        return
      }
      expect(frame.style.fontSize).assertEqual(20)
      expect(frame.style.textColor).assertEqual('#FFFFFF')
      expect(frame.style.backgroundOpacity).assertEqual(60)
      expect(frame.style.strokeWidth).assertEqual(1)
    })

    it('falls back per field on invalid values and keeps the rest', 0, () => {
      const frame = parseRtcSubtitleStyleFrame(styleFrame(7,
        ',"font_size":999,"text_color":"red","background_color":"#1A1A1A",' +
        '"background_opacity":80,"stroke_width":2'))
      expect(frame !== undefined).assertTrue()
      if (!frame) {
        return
      }
      expect(frame.style.fontSize).assertEqual(20)
      expect(frame.style.textColor).assertEqual('#FFFFFF')
      expect(frame.style.backgroundColor).assertEqual('#1A1A1A')
      expect(frame.style.backgroundOpacity).assertEqual(80)
      expect(frame.style.strokeWidth).assertEqual(2)
      expect(frame.fallbackFields.indexOf('font_size') >= 0).assertTrue()
      expect(frame.fallbackFields.indexOf('text_color') >= 0).assertTrue()
      expect(frame.fallbackFields.indexOf('background_color') < 0).assertTrue()
    })

    it('keeps opacity 0 and stroke width 0 as deliberate choices', 0, () => {
      const frame = parseRtcSubtitleStyleFrame(styleFrame(8, ',"background_opacity":0,"stroke_width":0'))
      expect(frame !== undefined).assertTrue()
      if (!frame) {
        return
      }
      expect(frame.style.backgroundOpacity).assertEqual(0)
      expect(frame.style.strokeWidth).assertEqual(0)
      expect(frame.fallbackFields.length).assertEqual(0)
      expect(rtcSubtitleBackgroundArgb(frame.style)).assertEqual('#00000000')
    })

    it('expands #RGB and normalizes case', 0, () => {
      expect(normalizeRtcSubtitleHexColor('#abc')).assertEqual('#AABBCC')
      expect(normalizeRtcSubtitleHexColor('#ffe066')).assertEqual('#FFE066')
      expect(normalizeRtcSubtitleHexColor('red') === undefined).assertTrue()
      expect(normalizeRtcSubtitleHexColor('#12345') === undefined).assertTrue()
    })

    it('composes background alpha from opacity percentage', 0, () => {
      const style = new RtcSubtitleStyleSpec()
      style.backgroundColor = '#1A1A1A'
      style.backgroundOpacity = 80
      expect(rtcSubtitleBackgroundArgb(style)).assertEqual('#CC1A1A1A')
    })

    it('ignores unknown broadcast types', 0, () => {
      expect(parseRtcSubtitleStyleFrame(JSON.stringify({ type: 'asr_subtitle', uid: 'u' })) === undefined).assertTrue()
      expect(parseRtcSubtitleStyleFrame('not json at all') === undefined).assertTrue()
    })

    it('applies a new style to open lines only and skips same version', 0, () => {
      const scheduler = new StyleFakeScheduler()
      const store = new RtcSubtitleStore({ scheduler: scheduler, coalesceIntervalMs: 200 })
      expect(store.ingestBroadcastData(bodyFrame(1, 1, 'first sentence', false))).assertTrue()
      scheduler.flush()
      expect(store.ingestBroadcastData(styleFrame(3, ',"font_size":32,"text_color":"#FFE066"'))).assertTrue()
      expect(store.getAppliedStyleVersion()).assertEqual(3)
      let lines = store.getSnapshot('uid-style-test')?.lines || []
      expect(lines.length).assertEqual(1)
      expect(lines[0].style.fontSize).assertEqual(32)
      expect(lines[0].style.textColor).assertEqual('#FFE066')
      const openUpdatedAt = lines[0].updatedAt

      // 同版本重复收到：幂等跳过，不刷新不重绘。
      expect(store.ingestBroadcastData(styleFrame(3, ',"font_size":40'))).assertTrue()
      lines = store.getSnapshot('uid-style-test')?.lines || []
      expect(lines[0].style.fontSize).assertEqual(32)
      expect(lines[0].updatedAt).assertEqual(openUpdatedAt)

      // 定稿行保留建行时快照；新样式只作用于之后的行。
      expect(store.ingestBroadcastData(bodyFrame(2, 1, 'first sentence done', true))).assertTrue()
      scheduler.flush()
      expect(store.ingestBroadcastData(styleFrame(4, ',"font_size":40'))).assertTrue()
      expect(store.ingestBroadcastData(bodyFrame(3, 2, 'second sentence', false))).assertTrue()
      scheduler.flush()
      lines = store.getSnapshot('uid-style-test')?.lines || []
      expect(lines.length).assertEqual(2)
      expect(lines[0].style.fontSize).assertEqual(32)
      expect(lines[1].style.fontSize).assertEqual(40)
      store.dispose()
    })

    it('renders with defaults before any style frame arrives', 0, () => {
      const scheduler = new StyleFakeScheduler()
      const store = new RtcSubtitleStore({ scheduler: scheduler, coalesceIntervalMs: 200 })
      expect(store.ingestBroadcastData(bodyFrame(1, 1, 'no style yet', false))).assertTrue()
      scheduler.flush()
      const lines = store.getSnapshot('uid-style-test')?.lines || []
      expect(lines.length).assertEqual(1)
      expect(lines[0].style.fontSize).assertEqual(20)
      expect(lines[0].style.backgroundOpacity).assertEqual(60)
      expect(store.getAppliedStyleVersion()).assertEqual(-1)
      store.dispose()
    })

    it('reports the missing style frame once, not per sentence', 0, () => {
      const scheduler = new StyleFakeScheduler()
      const logs: string[] = []
      const store = new RtcSubtitleStore({
        scheduler: scheduler,
        coalesceIntervalMs: 200,
        onLog: (message: string): void => {
          logs.push(message)
        }
      })
      expect(store.ingestBroadcastData(bodyFrame(1, 1, 'no style one', false))).assertTrue()
      expect(store.ingestBroadcastData(bodyFrame(2, 1, 'no style one done', true))).assertTrue()
      scheduler.flush()
      let absent = logs.filter((l: string): boolean => l.indexOf('rtc_subtitle_style absent') >= 0)
      expect(absent.length).assertEqual(1)
      expect(absent[0].indexOf('no_frame_before_body') >= 0).assertTrue()
      expect(absent[0].indexOf('rendered=builtin') >= 0).assertTrue()

      // 样式帧补上之后，后续正文不再报缺失。
      expect(store.ingestBroadcastData(styleFrame(5, ',"font_size":28'))).assertTrue()
      expect(store.ingestBroadcastData(bodyFrame(3, 2, 'styled sentence', false))).assertTrue()
      scheduler.flush()
      absent = logs.filter((l: string): boolean => l.indexOf('rtc_subtitle_style absent') >= 0)
      expect(absent.length).assertEqual(1)
      store.dispose()
    })

    it('reuses the last applied style across restarts when the gateway stays silent', 0, async () => {
      const cacheStore = new StyleCacheMemoryStore()
      const writer = new RtcSubtitleStore({
        scheduler: new StyleFakeScheduler(),
        coalesceIntervalMs: 200,
        onStyleApplied: (frameText: string): void => {
          cacheStore.lastWrite = RtcSubtitleStyleCache.save(frameText, { store: cacheStore })
        }
      })
      expect(writer.ingestBroadcastData(styleFrame(9, ',"font_size":34,"background_opacity":85'))).assertTrue()
      await cacheStore.lastWrite

      // 模拟"进程重启后网关一帧样式都没补发"：新 store 只靠缓存就该画出后台那套值。
      const reader = new RtcSubtitleStore({
        scheduler: new StyleFakeScheduler(),
        coalesceIntervalMs: 200
      })
      expect(await RtcSubtitleStyleCache.restore(reader, { store: cacheStore })).assertTrue()
      expect(reader.getAppliedStyleVersion()).assertEqual(9)
      expect(reader.getCurrentStyle().fontSize).assertEqual(34)
      expect(reader.getCurrentStyle().backgroundOpacity).assertEqual(85)
      expect(reader.isStyleFromCache()).assertTrue()
      expect(reader.ingestBroadcastData(bodyFrame(1, 1, 'after restart', false))).assertTrue()

      // 网关随后真发了更新版本：以网关为准，缓存不能压住它。
      expect(reader.ingestBroadcastData(styleFrame(10, ',"font_size":24'))).assertTrue()
      expect(reader.getAppliedStyleVersion()).assertEqual(10)
      expect(reader.isStyleFromCache()).assertFalse()
      writer.dispose()
      reader.dispose()
    })

    it('does not overwrite a style frame that already arrived', 0, async () => {
      const cacheStore = new StyleCacheMemoryStore()
      await RtcSubtitleStyleCache.save(CACHED_STYLE_FRAME_TEXT, { store: cacheStore })
      const store = new RtcSubtitleStore({
        scheduler: new StyleFakeScheduler(),
        coalesceIntervalMs: 200
      })
      expect(store.ingestBroadcastData(styleFrame(12, ',"font_size":40'))).assertTrue()
      expect(await RtcSubtitleStyleCache.restore(store, { store: cacheStore })).assertFalse()
      expect(store.getAppliedStyleVersion()).assertEqual(12)
      expect(store.getCurrentStyle().fontSize).assertEqual(40)
      store.dispose()
    })
  })
}
