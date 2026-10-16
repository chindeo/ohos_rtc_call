import { describe, it, expect } from '@ohos/hypium'
import { normalizeTtsText } from '../src/main/ets/tts/RtcTtsText'

export default function rtcTtsTextTest() {
  describe('RtcTtsText', () => {
    it('reads a clock time as 点/分', 0, () => {
      expect(normalizeTtsText('10:36，请3床患者到护士站')).assertEqual('十点三十六分，请3床患者到护士站')
      expect(normalizeTtsText('08:05 复查')).assertEqual('八点零五分 复查')
      expect(normalizeTtsText('20:00')).assertEqual('二十点零零分')
    })

    it('reads long digit runs one digit at a time', 0, () => {
      expect(normalizeTtsText('住院号01177125')).assertEqual('住院号零一一七七一二五')
      expect(normalizeTtsText('电话0755-1234567')).assertEqual('电话零七五五-一二三四五六七')
    })

    it('keeps short numbers for the sherpa rules', 0, () => {
      expect(normalizeTtsText('21床正在呼叫')).assertEqual('21床正在呼叫')
      expect(normalizeTtsText('体温36.5度')).assertEqual('体温36.5度')
    })

    it('leaves an invalid clock alone', 0, () => {
      expect(normalizeTtsText('比例25:99')).assertEqual('比例25:99')
    })

    it('handles empty text', 0, () => {
      expect(normalizeTtsText('')).assertEqual('')
    })
  })
}
