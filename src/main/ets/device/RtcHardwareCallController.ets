import {
  RTC_CALL_CONTROL_ACTION_ACCEPT,
  RTC_CALL_CONTROL_ACTION_HANGUP
} from '../core/RtcDefaultCallService'
import {
  RTC_CALL_CONTROL_SOURCE_HANDSET,
  RtcCallControlCommand,
  RtcCallControlCommandCodec
} from '../core/RtcCallControlCommand'
import { RtcDeviceCapabilityResult, RtcDeviceKeyEventListener } from './RtcDeviceCapabilityAdapter'
import { RtcDeviceCapabilityManager } from './RtcDeviceCapabilityManager'

export const RTC_HARDWARE_CALL_EVENT_CALL_KEY = 'callKey'
export const RTC_HARDWARE_CALL_EVENT_HANDSET_UP = 'handsetUp'
export const RTC_HARDWARE_CALL_EVENT_HANDSET_DOWN = 'handsetDown'
export const RTC_HARDWARE_CALL_EVENT_UNKNOWN = 'unknown'

export class RtcHardwareCallEvent {
  type: string = RTC_HARDWARE_CALL_EVENT_UNKNOWN
  source: string = RTC_CALL_CONTROL_SOURCE_HANDSET
  rawText: string = ''
}

export type RtcHardwareCallEventParser = (event: Object) => RtcHardwareCallEvent

export interface RtcHardwareCallControllerCallbacks {
  onCommand?(command: RtcCallControlCommand, event: RtcHardwareCallEvent): void
  onAnswer?(command: RtcCallControlCommand, event: RtcHardwareCallEvent): void
  onHangup?(command: RtcCallControlCommand, event: RtcHardwareCallEvent): void
  onCallKey?(event: RtcHardwareCallEvent): void
  onHandsetChanged?(pickedUp: boolean, event: RtcHardwareCallEvent): void
  onLog?(message: string): void
}

export interface RtcHardwareCallControllerOptions {
  vendor?: string
  parser?: RtcHardwareCallEventParser
  callbacks?: RtcHardwareCallControllerCallbacks
  answerOnHandsetUp?: boolean
  hangupOnHandsetDown?: boolean
  callKeyAsAnswer?: boolean
}

export class RtcHardwareCallControllerState {
  subscribed: boolean = false
  handsetPickedUp: boolean = false
  sequence: number = 0
}

export class RtcHardwareCallController {
  private options: RtcHardwareCallControllerOptions
  private listener: RtcDeviceKeyEventListener
  private state: RtcHardwareCallControllerState = new RtcHardwareCallControllerState()

  constructor(options?: RtcHardwareCallControllerOptions) {
    this.options = options || {}
    this.listener = (event: Object) => {
      this.handleRawEvent(event)
    }
  }

  subscribe(): RtcDeviceCapabilityResult<boolean> {
    const result = RtcDeviceCapabilityManager.subscribeKeyEvent(this.listener, this.options.vendor)
    this.state.subscribed = result.success === true
    return result
  }

  unsubscribe(): RtcDeviceCapabilityResult<boolean> {
    const result = RtcDeviceCapabilityManager.unsubscribeKeyEvent(this.listener, this.options.vendor)
    if (result.success || !result.supported) {
      this.state.subscribed = false
    }
    return result
  }

  dispose(): void {
    if (this.state.subscribed) {
      this.unsubscribe()
    }
  }

  handleRawEvent(raw: Object): RtcHardwareCallEvent {
    const parser = this.options.parser || RtcHardwareCallController.defaultParser
    const event = parser(raw)
    this.dispatch(event)
    return event
  }

  getState(): RtcHardwareCallControllerState {
    const copy = new RtcHardwareCallControllerState()
    copy.subscribed = this.state.subscribed
    copy.handsetPickedUp = this.state.handsetPickedUp
    copy.sequence = this.state.sequence
    return copy
  }

  static defaultParser(event: Object): RtcHardwareCallEvent {
    const parsed = new RtcHardwareCallEvent()
    parsed.rawText = JSON.stringify(event)
    const text = parsed.rawText.toLowerCase()
    if (text.indexOf('handset') >= 0 && (text.indexOf('up') >= 0 || text.indexOf('pickup') >= 0 ||
      text.indexOf('pick_up') >= 0 || text.indexOf('offhook') >= 0)) {
      parsed.type = RTC_HARDWARE_CALL_EVENT_HANDSET_UP
      return parsed
    }
    if (text.indexOf('handset') >= 0 && (text.indexOf('down') >= 0 || text.indexOf('hangup') >= 0 ||
      text.indexOf('onhook') >= 0)) {
      parsed.type = RTC_HARDWARE_CALL_EVENT_HANDSET_DOWN
      return parsed
    }
    if (text.indexOf('call') >= 0 || text.indexOf('answer') >= 0) {
      parsed.type = RTC_HARDWARE_CALL_EVENT_CALL_KEY
      return parsed
    }
    return parsed
  }

  private dispatch(event: RtcHardwareCallEvent): void {
    if (event.type === RTC_HARDWARE_CALL_EVENT_CALL_KEY) {
      this.options.callbacks?.onCallKey?.(event)
      if (this.options.callKeyAsAnswer !== false) {
        this.emitCommand(RTC_CALL_CONTROL_ACTION_ACCEPT, event)
      }
      return
    }
    if (event.type === RTC_HARDWARE_CALL_EVENT_HANDSET_UP) {
      this.state.handsetPickedUp = true
      this.options.callbacks?.onHandsetChanged?.(true, event)
      if (this.options.answerOnHandsetUp !== false) {
        this.emitCommand(RTC_CALL_CONTROL_ACTION_ACCEPT, event)
      }
      return
    }
    if (event.type === RTC_HARDWARE_CALL_EVENT_HANDSET_DOWN) {
      this.state.handsetPickedUp = false
      this.options.callbacks?.onHandsetChanged?.(false, event)
      if (this.options.hangupOnHandsetDown === true) {
        this.emitCommand(RTC_CALL_CONTROL_ACTION_HANGUP, event)
      }
      return
    }
    this.options.callbacks?.onLog?.('ignore unknown hardware call event: ' + event.rawText)
  }

  private emitCommand(action: string, event: RtcHardwareCallEvent): void {
    this.state.sequence += 1
    const encoded = RtcCallControlCommandCodec.build(action, this.state.sequence, event.source)
    const command = RtcCallControlCommandCodec.parse(encoded)
    this.options.callbacks?.onCommand?.(command, event)
    if (action === RTC_CALL_CONTROL_ACTION_ACCEPT) {
      this.options.callbacks?.onAnswer?.(command, event)
      return
    }
    if (action === RTC_CALL_CONTROL_ACTION_HANGUP) {
      this.options.callbacks?.onHangup?.(command, event)
    }
  }
}
