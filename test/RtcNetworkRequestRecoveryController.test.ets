import { describe, it, expect } from '@ohos/hypium'
import {
  RTC_NETWORK_ERROR_MESSAGE,
  RtcNetworkRequestRecoveryController,
  RtcNetworkRequestState
} from '../src/main/ets/core/RtcNetworkRequestRecoveryController'

export default function rtcNetworkRequestRecoveryControllerTest() {
  describe('RtcNetworkRequestRecoveryController', () => {
    it('shows network error when cache fallback is used', 0, () => {
      const controller = new RtcNetworkRequestRecoveryController()

      const state = controller.applyCacheResult({
        source: 'cache',
        usedCache: true,
        errorMessage: 'api stopped'
      })

      expect(state.online).assertEqual(false)
      expect(state.usingCache).assertEqual(true)
      expect(state.message).assertEqual(RTC_NETWORK_ERROR_MESSAGE)
      expect(state.errorMessage).assertEqual('api stopped')
    })

    it('clears network error after a successful request', 0, () => {
      const controller = new RtcNetworkRequestRecoveryController()
      controller.markFailure(new Error('offline'))

      const state = controller.markSuccess('已恢复')

      expect(state.online).assertEqual(true)
      expect(state.usingCache).assertEqual(false)
      expect(state.failureCount).assertEqual(0)
      expect(state.message).assertEqual('已恢复')
    })

    it('emits immutable state snapshots', 0, () => {
      const controller = new RtcNetworkRequestRecoveryController()
      let latest = new RtcNetworkRequestState()
      controller.onChange((state: RtcNetworkRequestState) => {
        latest = state
      })

      latest.message = 'modified'
      controller.markFailure(new Error('offline'))

      expect(latest.message).assertEqual(RTC_NETWORK_ERROR_MESSAGE)
    })
  })
}
