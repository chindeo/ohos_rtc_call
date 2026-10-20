import { describe, it, expect } from '@ohos/hypium'
import { clampSpeechRate, parseSpeechRate, DEFAULT_SPEECH_RATE } from '../src/main/ets/tts/RtcSpeechRate'

export default function rtcSpeechRateTest() {
  describe('RtcSpeechRate', () => {
    it('takes the ward value as-is inside the allowed band', 0, () => {
      expect(parseSpeechRate('0.7')).assertEqual(0.7)
      expect(parseSpeechRate(' 1.0 ')).assertEqual(1.0)
      expect(clampSpeechRate(1.8)).assertEqual(1.8)
    })

    it('falls back to normal speed for empty, unparsable or out-of-band values', 0, () => {
      expect(parseSpeechRate('')).assertEqual(DEFAULT_SPEECH_RATE)
      expect(parseSpeechRate('   ')).assertEqual(DEFAULT_SPEECH_RATE)
      expect(parseSpeechRate('快一点')).assertEqual(DEFAULT_SPEECH_RATE)
      expect(parseSpeechRate('0')).assertEqual(DEFAULT_SPEECH_RATE)
      expect(parseSpeechRate('7')).assertEqual(DEFAULT_SPEECH_RATE)
      expect(clampSpeechRate(Number.NaN)).assertEqual(DEFAULT_SPEECH_RATE)
    })
  })
}
