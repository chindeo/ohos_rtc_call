import { describe, it, expect } from '@ohos/hypium'
import { RtcHostCallController } from '../src/main/ets/core/RtcHostCallController'
import {
  RTC_CALL_STATUS_LEVEL_KEY,
  RTC_CALL_STATUS_MESSAGE_KEY,
  RtcCallStatusLevel,
  RtcCallStatusNotifier
} from '../src/main/ets/model/RtcCallStatusMessage'

function createMicSwitchController(onMicSwitch: () => boolean | void | Promise<boolean | void>): RtcHostCallController {
  return new RtcHostCallController({
    serverUrl: 'ws://127.0.0.1',
    local: {
      number: '1001',
      displayName: '床旁',
      clientType: 'bed'
    },
    appVersion: 'unit-test',
    speakerActionIsMicSwitch: true,
    onMicSwitch
  })
}

export default function rtcHostCallControllerTest() {
  describe('RtcHostCallController', () => {
    it('updates mic switch button state when the host callback succeeds', 0, async () => {
      let switchCount = 0
      const controller = createMicSwitchController((): boolean => {
        switchCount += 1
        return true
      })

      await controller.toggleSpeaker()

      expect(switchCount).assertEqual(1)
      expect(controller.getUiModel().speakerEnabled).assertEqual(true)
      controller.dispose()
    })

    it('keeps mic switch button state and warns when the host callback fails', 0, async () => {
      RtcCallStatusNotifier.clear()
      const controller = createMicSwitchController((): boolean => false)

      await controller.toggleSpeaker()

      expect(controller.getUiModel().speakerEnabled).assertEqual(false)
      expect(AppStorage.get<string>(RTC_CALL_STATUS_MESSAGE_KEY)).assertEqual('当前设备不支持切麦或切换失败')
      expect(AppStorage.get<string>(RTC_CALL_STATUS_LEVEL_KEY)).assertEqual(RtcCallStatusLevel.WARNING)
      controller.dispose()
    })
  })
}
