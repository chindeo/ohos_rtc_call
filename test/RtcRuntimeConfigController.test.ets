import { describe, it, expect } from '@ohos/hypium'
import {
  RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING,
  RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST,
  RtcRuntimeSwitchHandlers,
  RtcRuntimeSwitchPlan
} from '../src/main/ets/core/RtcRuntimeConfigCoordinator'
import {
  RtcRuntimeConfigController,
  RtcRuntimeConfigMap
} from '../src/main/ets/core/RtcRuntimeConfigController'
import { RtcCallRoute } from '../src/main/ets/core/RtcCallRouteResolver'

class MemoryRuntimeHandlers implements RtcRuntimeSwitchHandlers {
  webRtcPrepareCount: number = 0
  sipPrepareCount: number = 0
  micApplyCount: number = 0

  async prepareWebRtc(_route: RtcCallRoute, _plan: RtcRuntimeSwitchPlan): Promise<void> {
    this.webRtcPrepareCount += 1
  }

  async prepareSip(_route: RtcCallRoute, _plan: RtcRuntimeSwitchPlan): Promise<void> {
    this.sipPrepareCount += 1
  }

  async applyMicSwitching(_plan: RtcRuntimeSwitchPlan): Promise<void> {
    this.micApplyCount += 1
  }
}

function createConfig(host: string, micSwitching: string): RtcRuntimeConfigMap {
  const config: RtcRuntimeConfigMap = {}
  config[RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST] = host
  config[RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING] = micSwitching
  return config
}

export default function rtcRuntimeConfigControllerTest() {
  describe('RtcRuntimeConfigController', () => {
    it('loads initial runtime config and applies mic switching', 0, async () => {
      const handlers = new MemoryRuntimeHandlers()
      const controller = new RtcRuntimeConfigController({
        defaultRegisterAddress: 'wss://fallback.example.com/websocket',
        loader: async () => createConfig('wss://rtc.example.com/websocket', 'true'),
        handlers,
        applyMicSwitchingOnInitial: true
      })

      const result = await controller.loadInitial()

      expect(result.resolved.registerAddress).assertEqual('wss://rtc.example.com/websocket')
      expect(result.resolved.micSwitchingEnabled).assertEqual(true)
      expect(handlers.webRtcPrepareCount).assertEqual(1)
      expect(handlers.micApplyCount).assertEqual(1)
    })

    it('refreshes only changed runtime keys', 0, async () => {
      const handlers = new MemoryRuntimeHandlers()
      let index = 0
      const configs: RtcRuntimeConfigMap[] = [
        createConfig('wss://rtc.example.com/websocket', 'false'),
        createConfig('wss://rtc2.example.com/websocket', 'true')
      ]
      const controller = new RtcRuntimeConfigController({
        defaultRegisterAddress: 'wss://fallback.example.com/websocket',
        loader: async () => {
          const config = configs[index]
          index += 1
          return config
        },
        handlers
      })

      await controller.loadInitial()
      const refresh = await controller.refresh()

      expect(refresh.changedKeys.indexOf(RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST) >= 0).assertEqual(true)
      expect(refresh.changedKeys.indexOf(RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING) >= 0).assertEqual(true)
      expect(refresh.resolved.registerAddress).assertEqual('wss://rtc2.example.com/websocket')
      expect(handlers.webRtcPrepareCount).assertEqual(2)
      expect(handlers.micApplyCount).assertEqual(1)
    })
  })
}
