import { describe, expect, it } from '@ohos/hypium'
import { normalizeTtsText } from '../src/main/ets/tts/RtcTtsText'

export default function rtcTtsTextTest() {
  describe('RtcTtsText', () => {
    it('reads short numbers as cardinals so the bed number is audible', 0, () => {
      expect(normalizeTtsText('21床,正在呼叫。')).assertEqual('二十一床,正在呼叫。')
      expect(normalizeTtsText('105床')).assertEqual('一百零五床')
      expect(normalizeTtsText('110床')).assertEqual('一百一十床')
      expect(normalizeTtsText('10点')).assertEqual('十点')
    })

    it('reads long runs and leading-zero codes digit by digit', 0, () => {
      expect(normalizeTtsText('科室0117')).assertEqual('科室零一一七')
      expect(normalizeTtsText('住院号7122515')).assertEqual('住院号七一二二五一五')
      expect(normalizeTtsText('2026年')).assertEqual('二零二六年')
    })

    it('reads clock times including leading-zero minutes and seconds', 0, () => {
      expect(normalizeTtsText('10:36')).assertEqual('十点三十六分')
      expect(normalizeTtsText('08:05')).assertEqual('八点零五分')
      expect(normalizeTtsText('10:00')).assertEqual('十点整')
      expect(normalizeTtsText('10:36:20')).assertEqual('十点三十六分二十秒')
    })

    it('leaves plain Chinese and invalid time shapes alone', 0, () => {
      expect(normalizeTtsText('为您自动接听')).assertEqual('为您自动接听')
      expect(normalizeTtsText('')).assertEqual('')
      // 25 点不是合法时刻，退回按位/按整数读，不硬编成"点"
      expect(normalizeTtsText('25:36')).assertEqual('二十五三十六')
      expect(normalizeTtsText('36.5度')).assertEqual('三十六点五度')
    })
  })
}
