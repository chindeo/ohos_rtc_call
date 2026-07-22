import { describe, it, expect } from '@ohos/hypium'
import {
  RtcWebRtcReconnectPolicy
} from '../src/main/ets/signaling/RtcWebRtcReconnectPolicy'

export default function rtcWebRtcReconnectPolicyTest() {
  describe('RtcWebRtcReconnectPolicy', () => {
    it('uses balanced defaults and caps exponential backoff', 0, () => {
      const config = RtcWebRtcReconnectPolicy.resolve()
      const first = RtcWebRtcReconnectPolicy.calculateDelay(config, 1, 'device-1000', 0)
      const late = RtcWebRtcReconnectPolicy.calculateDelay(config, 20, 'device-1000', 0.999999)

      expect(config.initialDelayMs).assertEqual(5000)
      expect(config.maxDelayMs).assertEqual(300000)
      expect(config.cohortSpreadMs).assertEqual(30000)
      expect(first >= 2500 && first <= 35000).assertEqual(true)
      expect(late <= 300000).assertEqual(true)
    })

    it('spreads ten thousand devices across the first reconnect window', 0, () => {
      const config = RtcWebRtcReconnectPolicy.resolve()
      const buckets: number[] = []
      let maxDelay = 0
      for (let i = 0; i < 10000; i += 1) {
        const delay = RtcWebRtcReconnectPolicy.calculateDelay(config, 1, `device-${i}`, 0.5)
        const bucket = Math.floor(delay / 1000)
        buckets[bucket] = (buckets[bucket] || 0) + 1
        maxDelay = Math.max(maxDelay, delay)
      }
      let nonEmptyBuckets = 0
      let maxBucketSize = 0
      for (let i = 0; i < buckets.length; i += 1) {
        if ((buckets[i] || 0) > 0) {
          nonEmptyBuckets += 1
          maxBucketSize = Math.max(maxBucketSize, buckets[i])
        }
      }

      expect(nonEmptyBuckets >= 25).assertEqual(true)
      expect(maxBucketSize < 600).assertEqual(true)
      expect(maxDelay <= 35000).assertEqual(true)
    })
  })
}
