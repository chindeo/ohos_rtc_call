import fs from '@ohos.file.fs'
import {
  createUnsupportedResult,
  RtcAutoPowerOnOffConfig,
  RtcDeviceBootAppOptions,
  RtcDeviceCapabilityAdapter,
  RtcDeviceCapabilityResult,
  RtcDeviceHandsetOptions,
  RtcDeviceInitializeOptions,
  RtcDeviceKeyEventListener,
  RtcDeviceLedOptions,
  RtcDeviceKeepAliveOptions,
  RtcDeviceMacOptions,
  RtcMacAddressUtils,
  RtcSilentInstallOptions
} from './RtcDeviceCapabilityAdapter'
import { RtcDeviceVendor, RtcDeviceVendorResolver } from './RtcDeviceVendor'

export class RtcDeviceCapabilityManager {
  private static adapters: Map<string, RtcDeviceCapabilityAdapter> = new Map()

  static registerAdapter(adapter: RtcDeviceCapabilityAdapter): void {
    RtcDeviceCapabilityManager.adapters.set(adapter.vendor, adapter)
  }

  static unregisterAdapter(vendor: string): void {
    RtcDeviceCapabilityManager.adapters.delete(vendor)
  }

  static clearAdapters(): void {
    RtcDeviceCapabilityManager.adapters.clear()
  }

  static getAdapter(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): RtcDeviceCapabilityAdapter | undefined {
    const adapter = RtcDeviceCapabilityManager.adapters.get(vendor)
    if (adapter) {
      return adapter
    }
    if (RtcDeviceVendorResolver.shouldUseDnakeSdk(vendor)) {
      return RtcDeviceCapabilityManager.adapters.get(RtcDeviceVendor.DNAKE)
    }
    return undefined
  }

  static isVendorAvailable(vendor: string): boolean {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    return adapter?.isAvailable() === true
  }

  static async initialize(options?: RtcDeviceInitializeOptions, vendor: string = RtcDeviceVendorResolver.getStoredVendor()):
    Promise<RtcDeviceCapabilityResult<boolean>> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.initialize) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} initialize is unsupported`)
    }
    return adapter.initialize(options)
  }

  static async getDeviceMac(options?: RtcDeviceMacOptions, vendor: string = RtcDeviceVendorResolver.getStoredVendor()):
    Promise<string> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    const mac = await RtcDeviceCapabilityManager.readDeviceMac(adapter, options)
    if (RtcMacAddressUtils.isValid(mac)) {
      return mac
    }
    const systemMac = RtcDeviceCapabilityManager.readSystemMac(options)
    if (RtcMacAddressUtils.isValid(systemMac)) {
      return systemMac
    }
    if (vendor !== RtcDeviceVendor.UNKNOWN) {
      return ''
    }

    const aurineMac = await RtcDeviceCapabilityManager.readDeviceMac(
      RtcDeviceCapabilityManager.adapters.get(RtcDeviceVendor.AURINE),
      options
    )
    if (RtcMacAddressUtils.isValid(aurineMac)) {
      RtcDeviceVendorResolver.persist(RtcDeviceVendor.AURINE)
      return aurineMac
    }

    const shimetaMac = await RtcDeviceCapabilityManager.readDeviceMac(
      RtcDeviceCapabilityManager.adapters.get(RtcDeviceVendor.SHIMETA),
      options
    )
    if (RtcMacAddressUtils.isValid(shimetaMac)) {
      RtcDeviceVendorResolver.persist(RtcDeviceVendor.SHIMETA)
      return shimetaMac
    }

    const dnakeMac = await RtcDeviceCapabilityManager.readDeviceMac(
      RtcDeviceCapabilityManager.adapters.get(RtcDeviceVendor.DNAKE),
      options
    )
    if (RtcMacAddressUtils.isValid(dnakeMac)) {
      RtcDeviceVendorResolver.persist(RtcDeviceVendor.DNAKE)
      return dnakeMac
    }
    return ''
  }

  private static readSystemMac(options?: RtcDeviceMacOptions): string {
    const primary = options?.preferEthernet === false ? 'wlan0' : 'eth0'
    const candidates = primary === 'eth0'
      ? ['eth0', 'eth1', 'wlan0', 'p2p0']
      : ['wlan0', 'p2p0', 'eth0', 'eth1']
    for (let i = 0; i < candidates.length; i += 1) {
      const mac = RtcDeviceCapabilityManager.readSystemMacByName(candidates[i])
      if (RtcMacAddressUtils.isValid(mac)) {
        return mac
      }
    }
    return ''
  }

  private static readSystemMacByName(name: string): string {
    try {
      return RtcMacAddressUtils.normalize(fs.readTextSync(`/sys/class/net/${name}/address`))
    } catch (_error) {
      return ''
    }
  }

  private static async readDeviceMac(adapter: RtcDeviceCapabilityAdapter | undefined, options?: RtcDeviceMacOptions):
    Promise<string> {
    if (!adapter?.getDeviceMac) {
      return ''
    }
    try {
      return await adapter.getDeviceMac(options)
    } catch (_error) {
      return ''
    }
  }

  static async setBootApp(options?: RtcDeviceBootAppOptions, vendor: string = RtcDeviceVendorResolver.getStoredVendor()):
    Promise<RtcDeviceCapabilityResult<string>> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.setBootApp) {
      return createUnsupportedResult<string>(`vendor ${vendor} boot app is unsupported`)
    }
    return adapter.setBootApp(options)
  }

  static async getBootApp(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): Promise<string> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.getBootApp) {
      return ''
    }
    return adapter.getBootApp()
  }

  static async setAutoPowerOnOff(
    config: RtcAutoPowerOnOffConfig,
    vendor: string = RtcDeviceVendorResolver.getStoredVendor()
  ): Promise<RtcDeviceCapabilityResult<number>> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.setAutoPowerOnOff) {
      return createUnsupportedResult<number>(`vendor ${vendor} auto power on/off is unsupported`)
    }
    return adapter.setAutoPowerOnOff(config)
  }

  static async getAutoPowerOnOff(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): Promise<string> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.getAutoPowerOnOff) {
      return ''
    }
    return adapter.getAutoPowerOnOff()
  }

  static async silentInstallApp(
    options: RtcSilentInstallOptions,
    vendor: string = RtcDeviceVendorResolver.getStoredVendor()
  ): Promise<RtcDeviceCapabilityResult<number>> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.silentInstallApp) {
      return createUnsupportedResult<number>(`vendor ${vendor} silent install is unsupported`)
    }
    return adapter.silentInstallApp(options)
  }

  static async startKeepAlive(options: RtcDeviceKeepAliveOptions, vendor: string = RtcDeviceVendorResolver.getStoredVendor()):
    Promise<RtcDeviceCapabilityResult<boolean>> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.startKeepAlive) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} keep alive is unsupported`)
    }
    return adapter.startKeepAlive(options)
  }

  static stopKeepAlive(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): void {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    adapter?.stopKeepAlive?.()
  }

  static subscribeKeyEvent(
    listener: RtcDeviceKeyEventListener,
    vendor: string = RtcDeviceVendorResolver.getStoredVendor()
  ): RtcDeviceCapabilityResult<boolean> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.subscribeKeyEvent) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} key event is unsupported`)
    }
    return adapter.subscribeKeyEvent(listener)
  }

  static unsubscribeKeyEvent(
    listener: RtcDeviceKeyEventListener,
    vendor: string = RtcDeviceVendorResolver.getStoredVendor()
  ): RtcDeviceCapabilityResult<boolean> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.unsubscribeKeyEvent) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} key event is unsupported`)
    }
    return adapter.unsubscribeKeyEvent(listener)
  }

  static setHandsetMode(
    options: RtcDeviceHandsetOptions,
    vendor: string = RtcDeviceVendorResolver.getStoredVendor()
  ): RtcDeviceCapabilityResult<boolean> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.setHandsetMode) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} handset is unsupported`)
    }
    return adapter.setHandsetMode(options)
  }

  static setLed(
    options: RtcDeviceLedOptions,
    vendor: string = RtcDeviceVendorResolver.getStoredVendor()
  ): RtcDeviceCapabilityResult<boolean> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.setLed) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} led is unsupported`)
    }
    return adapter.setLed(options)
  }

  static reboot(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): RtcDeviceCapabilityResult<boolean> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.reboot) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} reboot is unsupported`)
    }
    return adapter.reboot()
  }

  static shutdown(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): RtcDeviceCapabilityResult<boolean> {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    if (!adapter?.shutdown) {
      return createUnsupportedResult<boolean>(`vendor ${vendor} shutdown is unsupported`)
    }
    return adapter.shutdown()
  }

  static dispose(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): void {
    const adapter = RtcDeviceCapabilityManager.getAdapter(vendor)
    adapter?.dispose?.()
  }
}
