import { RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { SipDnakeSwitchOptions } from './SipDnakeAdapter'

export interface SipDnakeModeOptions {
  protocol: RtcTransportProtocol
  reason?: string
}

export interface SipDnakeRingSwitchAdapter {
  setRingEnabled(options: SipDnakeSwitchOptions): void
  setDmsgHandlerEnabled(options: SipDnakeSwitchOptions): void
}

export class SipDnakeController {
  private adapter?: SipDnakeRingSwitchAdapter
  private sipRingEnabled: boolean | undefined = undefined
  private dmsgHandlerEnabled: boolean | undefined = undefined

  configureAdapter(adapter: SipDnakeRingSwitchAdapter): void {
    this.adapter = adapter
  }

  applyMode(options: SipDnakeModeOptions): void {
    const enabled = options.protocol === RtcTransportProtocol.SIP
    this.setRingAndDmsgEnabled(enabled, options.reason || options.protocol)
  }

  setRingAndDmsgEnabled(enabled: boolean, reason: string = ''): void {
    if (!this.adapter) {
      return
    }
    if (this.dmsgHandlerEnabled !== enabled) {
      this.dmsgHandlerEnabled = enabled
      this.adapter.setDmsgHandlerEnabled({ enabled, reason })
    }
    if (this.sipRingEnabled !== enabled) {
      this.sipRingEnabled = enabled
      this.adapter.setRingEnabled({ enabled, reason })
    }
  }

  isRingEnabled(): boolean {
    return this.sipRingEnabled !== false
  }

  isDmsgHandlerEnabled(): boolean {
    return this.dmsgHandlerEnabled !== false
  }
}
