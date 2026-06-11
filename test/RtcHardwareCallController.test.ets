import { describe, it, expect } from '@ohos/hypium'
import {
  RTC_HARDWARE_CALL_EVENT_HANDSET_DOWN,
  RTC_HARDWARE_CALL_EVENT_HANDSET_UP,
  RtcHardwareCallController,
  RtcHardwareCallEvent
} from '../src/main/ets/device/RtcHardwareCallController'
import { RTC_CALL_CONTROL_ACTION_ACCEPT, RTC_CALL_CONTROL_ACTION_HANGUP } from '../src/main/ets/core/RtcDefaultCallService'

class RawHardwareEvent {
  type: string = ''
}

function createRawEvent(type: string): RawHardwareEvent {
  const event = new RawHardwareEvent()
  event.type = type
  return event
}

export default function rtcHardwareCallControllerTest() {
  describe('RtcHardwareCallController', () => {
    it('dispatches handset up as answer command', 0, () => {
      let action = ''
      const controller = new RtcHardwareCallController({
        parser: (_raw: Object) => {
          const event = new RtcHardwareCallEvent()
          event.type = RTC_HARDWARE_CALL_EVENT_HANDSET_UP
          return event
        },
        callbacks: {
          onCommand(command) {
            action = command.action
          }
        }
      })

      controller.handleRawEvent(createRawEvent('up'))

      expect(action).assertEqual(RTC_CALL_CONTROL_ACTION_ACCEPT)
      expect(controller.getState().handsetPickedUp).assertEqual(true)
      expect(controller.getState().sequence).assertEqual(1)
    })

    it('dispatches handset down as hangup only when enabled', 0, () => {
      let action = ''
      const controller = new RtcHardwareCallController({
        hangupOnHandsetDown: true,
        parser: (_raw: Object) => {
          const event = new RtcHardwareCallEvent()
          event.type = RTC_HARDWARE_CALL_EVENT_HANDSET_DOWN
          return event
        },
        callbacks: {
          onCommand(command) {
            action = command.action
          }
        }
      })

      controller.handleRawEvent(createRawEvent('down'))

      expect(action).assertEqual(RTC_CALL_CONTROL_ACTION_HANGUP)
      expect(controller.getState().handsetPickedUp).assertEqual(false)
    })
  })
}
