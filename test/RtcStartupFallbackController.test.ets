import { describe, it, expect } from '@ohos/hypium'
import {
  RtcStartupFallbackController,
  RtcStartupFallbackState
} from '../src/main/ets/core/RtcStartupFallbackController'
import { RTC_NETWORK_ERROR_MESSAGE } from '../src/main/ets/core/RtcNetworkRequestRecoveryController'

export default function rtcStartupFallbackControllerTest() {
  describe('RtcStartupFallbackController', () => {
    it('allows home entry when required startup data comes from cache', 0, () => {
      const state = RtcStartupFallbackController.evaluate({
        items: [
          { key: 'config', required: true, source: 'cache', usedCache: true, valueAvailable: true },
          { key: 'bedConfig', required: true, source: 'cache', usedCache: true, valueAvailable: true },
          { key: 'bedDetail', required: false, source: 'fallback', valueAvailable: true }
        ]
      })

      expect(state.canEnterHome).assertEqual(true)
      expect(state.degraded).assertEqual(true)
      expect(state.message).assertEqual(RTC_NETWORK_ERROR_MESSAGE)
      expect(state.cacheKeys.length).assertEqual(2)
    })

    it('blocks home entry when required data is missing by default', 0, () => {
      const state = RtcStartupFallbackController.evaluate({
        items: [
          { key: 'config', required: true, source: 'empty', valueAvailable: false },
          { key: 'bedConfig', required: true, source: 'cache', valueAvailable: true }
        ]
      })

      expect(state.canEnterHome).assertEqual(false)
      expect(state.missingKeys[0]).assertEqual('config')
    })

    it('can enter degraded home when business explicitly allows missing required data', 0, () => {
      const state: RtcStartupFallbackState = RtcStartupFallbackController.evaluate({
        allowEnterWithMissingRequired: true,
        items: [
          { key: 'config', required: true, source: 'empty', valueAvailable: false }
        ]
      })

      expect(state.canEnterHome).assertEqual(true)
      expect(state.degraded).assertEqual(true)
    })
  })
}
