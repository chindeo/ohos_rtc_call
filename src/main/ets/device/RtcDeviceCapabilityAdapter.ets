export interface RtcDeviceCapabilityResult<T> {
  supported: boolean
  success: boolean
  value?: T
  message?: string
  error?: string
}

export interface RtcDeviceInitializeOptions {
  context?: Context
  reason?: string
}

export interface RtcDeviceMacOptions {
  context?: Context
  preferEthernet?: boolean
}

export interface RtcDeviceBootAppOptions {
  abilityName?: string
  bundleName?: string
  moduleName?: string
  bootParam?: string
}

export interface RtcDeviceKeepAliveOptions {
  bundleName: string
  abilityName: string
  intervalMs?: number
  screenOffTimeoutMs?: number
  reason?: string
}

export interface RtcAutoPowerOnOffConfig {
  enable: number
  week: string
  onHour: number
  onMinute: number
  offHour: number
  offMinute: number
}

export interface RtcSilentInstallOptions {
  hapPath: string
  isRun: number
  bundleName: string
}

export type RtcDeviceKeyEventListener = (event: Object) => void

export interface RtcDeviceHandsetOptions {
  mode: number
  reason?: string
}

export interface RtcDeviceLedOptions {
  channel: 'local' | 'rj485'
  r: boolean
  g: boolean
  b: boolean
  reason?: string
}

export interface RtcDeviceCapabilityAdapter {
  readonly vendor: string
  isAvailable(): boolean
  initialize?(options?: RtcDeviceInitializeOptions): Promise<RtcDeviceCapabilityResult<boolean>>
  getDeviceMac?(options?: RtcDeviceMacOptions): Promise<string>
  setBootApp?(options?: RtcDeviceBootAppOptions): Promise<RtcDeviceCapabilityResult<string>>
  getBootApp?(): Promise<string>
  setAutoPowerOnOff?(config: RtcAutoPowerOnOffConfig): Promise<RtcDeviceCapabilityResult<number>>
  getAutoPowerOnOff?(): Promise<string>
  silentInstallApp?(options: RtcSilentInstallOptions): Promise<RtcDeviceCapabilityResult<number>>
  startKeepAlive?(options: RtcDeviceKeepAliveOptions): Promise<RtcDeviceCapabilityResult<boolean>>
  stopKeepAlive?(): void
  subscribeKeyEvent?(listener: RtcDeviceKeyEventListener): RtcDeviceCapabilityResult<boolean>
  unsubscribeKeyEvent?(listener: RtcDeviceKeyEventListener): RtcDeviceCapabilityResult<boolean>
  setHandsetMode?(options: RtcDeviceHandsetOptions): RtcDeviceCapabilityResult<boolean>
  setLed?(options: RtcDeviceLedOptions): RtcDeviceCapabilityResult<boolean>
  reboot?(): RtcDeviceCapabilityResult<boolean>
  shutdown?(): RtcDeviceCapabilityResult<boolean>
  dispose?(): void
}

export class RtcMacAddressUtils {
  static normalize(mac: string): string {
    return (mac || '').replace(/:/g, '').replace(/-/g, '').trim().toUpperCase()
  }

  static isValid(mac: string): boolean {
    const normalized = RtcMacAddressUtils.normalize(mac)
    if (!normalized || normalized.length < 12) {
      return false
    }
    if (normalized === '000000000000' || normalized === '020000000000') {
      return false
    }
    return true
  }
}

export function createUnsupportedResult<T>(message: string): RtcDeviceCapabilityResult<T> {
  return {
    supported: false,
    success: false,
    message
  }
}

export function createSuccessResult<T>(value: T, message: string = ''): RtcDeviceCapabilityResult<T> {
  return {
    supported: true,
    success: true,
    value,
    message
  }
}

export function createFailedResult<T>(message: string, error: string = ''): RtcDeviceCapabilityResult<T> {
  return {
    supported: true,
    success: false,
    message,
    error
  }
}
