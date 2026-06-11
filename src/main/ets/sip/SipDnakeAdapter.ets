import { RtcCallViewStateListener } from '../model/RtcCallViewState'
import { RtcSipCallTarget, RtcSipConfig } from './RtcSipConfig'

export interface SipDnakeInitOptions {
  enableCallModule?: boolean
  reason?: string
}

export interface SipDnakeSwitchOptions {
  enabled: boolean
  reason?: string
}

export interface SipDnakeAdapter {
  init(options?: SipDnakeInitOptions): Promise<boolean>
  configure(config: RtcSipConfig): void
  setEnabled(options: SipDnakeSwitchOptions): void
  setRingEnabled(options: SipDnakeSwitchOptions): void
  setDmsgHandlerEnabled(options: SipDnakeSwitchOptions): void
  isReady(): boolean
  isCalling(): boolean
  startCall(target: RtcSipCallTarget): void
  acceptCall(): void
  terminateCall(): void
  onViewStateChange(listener: RtcCallViewStateListener): () => void
  dispose(): void
}

