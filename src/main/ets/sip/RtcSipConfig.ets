export const RTC_DEFAULT_DNAKE_DEVICE_TYPE = 10002
export const RTC_DEFAULT_DNAKE_RING_TIMEOUT_SECONDS = 30
export const RTC_DISABLED_DNAKE_RING_TIMEOUT_SECONDS = 0

export interface RtcSipConfig {
  sipUser: string
  sipPassword: string
  sipServer: string
  ntpServer?: string
  bindingCode?: string
  deviceIp?: string
}

export interface RtcSipCallTarget {
  number: string
  deviceIp?: string
  displayName?: string
}

export interface RtcSipCallAdapter {
  init(): Promise<void>
  configure(config: RtcSipConfig): void
  isReady(): boolean
  isCalling(): boolean
  startCall(target: RtcSipCallTarget): void
  acceptCall(): void
  terminateCall(): void
}
