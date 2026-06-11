import {
  RtcDeviceCapabilityAdapter,
  RtcDeviceCapabilityResult
} from './RtcDeviceCapabilityAdapter'
import { RtcDeviceCapabilityManager } from './RtcDeviceCapabilityManager'
import { RtcDeviceVendor, RtcDeviceVendorResolver } from './RtcDeviceVendor'

export interface RtcDeviceBootstrapOptions {
  adapters: RtcDeviceCapabilityAdapter[]
  context?: Context
  bundleName: string
  abilityName: string
  keepAliveIntervalMs?: number
  screenOffTimeoutMs?: number
  reason?: string
}

export interface RtcDeviceBootstrapResult {
  vendor: string
  useDnakeSdk: boolean
  initialized: boolean
  keepAliveStarted: boolean
  bootAppConfigured: boolean
  initializeResult?: RtcDeviceCapabilityResult<boolean>
  keepAliveResult?: RtcDeviceCapabilityResult<boolean>
  bootAppResult?: RtcDeviceCapabilityResult<string>
}

export class RtcDeviceBootstrapper {
  static async bootstrap(options: RtcDeviceBootstrapOptions): Promise<RtcDeviceBootstrapResult> {
    RtcDeviceBootstrapper.registerAdapters(options.adapters)
    const vendor = await RtcDeviceBootstrapper.resolveVendor(options)
    const useDnakeSdk = RtcDeviceVendorResolver.shouldUseDnakeSdk(vendor)
    const initializeResult = await RtcDeviceCapabilityManager.initialize({
      context: options.context,
      reason: options.reason || 'device bootstrap'
    }, vendor)

    if (!useDnakeSdk) {
      const bootAppResult = await RtcDeviceCapabilityManager.setBootApp(undefined, vendor)
      let keepAliveResult: RtcDeviceCapabilityResult<boolean> | undefined = undefined
      if (initializeResult.success && initializeResult.value) {
        keepAliveResult = await RtcDeviceCapabilityManager.startKeepAlive({
          bundleName: options.bundleName,
          abilityName: options.abilityName,
          intervalMs: options.keepAliveIntervalMs || 5 * 1000,
          screenOffTimeoutMs: options.screenOffTimeoutMs,
          reason: options.reason || 'device bootstrap'
        }, vendor)
      }
      return {
        vendor,
        useDnakeSdk,
        initialized: initializeResult.success && initializeResult.value === true,
        keepAliveStarted: keepAliveResult?.success === true && keepAliveResult.value === true,
        bootAppConfigured: bootAppResult.success,
        initializeResult,
        keepAliveResult,
        bootAppResult
      }
    }

    let keepAliveResult: RtcDeviceCapabilityResult<boolean> | undefined = undefined
    if (initializeResult.success && initializeResult.value) {
      keepAliveResult = await RtcDeviceCapabilityManager.startKeepAlive({
        bundleName: options.bundleName,
        abilityName: options.abilityName,
        intervalMs: options.keepAliveIntervalMs || 2 * 1000,
        screenOffTimeoutMs: options.screenOffTimeoutMs,
        reason: options.reason || 'device bootstrap'
      }, vendor)
    }

    return {
      vendor,
      useDnakeSdk,
      initialized: initializeResult.success && initializeResult.value === true,
      keepAliveStarted: keepAliveResult?.success === true && keepAliveResult.value === true,
      initializeResult,
      keepAliveResult,
      bootAppConfigured: false
    }
  }

  private static registerAdapters(adapters: RtcDeviceCapabilityAdapter[]): void {
    for (let i = 0; i < adapters.length; i += 1) {
      RtcDeviceCapabilityManager.registerAdapter(adapters[i])
    }
  }

  private static async resolveVendor(options: RtcDeviceBootstrapOptions): Promise<string> {
    let vendor = RtcDeviceVendorResolver.persist()
    if (vendor === RtcDeviceVendor.DNAKE) {
      return vendor
    }
    if (vendor === RtcDeviceVendor.AURINE) {
      return vendor
    }

    const shimetaInitResult = await RtcDeviceCapabilityManager.initialize({
      context: options.context,
      reason: options.reason || 'device bootstrap'
    }, RtcDeviceVendor.SHIMETA)
    if (shimetaInitResult.success && shimetaInitResult.value) {
      return RtcDeviceVendorResolver.persist(RtcDeviceVendor.SHIMETA)
    }
    if (vendor === RtcDeviceVendor.SHIMETA) {
      return vendor
    }
    const aurineInitResult = await RtcDeviceCapabilityManager.initialize({
      context: options.context,
      reason: options.reason || 'device bootstrap'
    }, RtcDeviceVendor.AURINE)
    if (aurineInitResult.success && aurineInitResult.value) {
      return RtcDeviceVendorResolver.persist(RtcDeviceVendor.AURINE)
    }
    const dnakeInitResult = await RtcDeviceCapabilityManager.initialize({
      context: options.context,
      reason: options.reason || 'device bootstrap'
    }, RtcDeviceVendor.DNAKE)
    if (dnakeInitResult.success && dnakeInitResult.value) {
      return RtcDeviceVendorResolver.persist(RtcDeviceVendor.DNAKE)
    }
    if (RtcDeviceCapabilityManager.isVendorAvailable(RtcDeviceVendor.SHIMETA)) {
      vendor = RtcDeviceVendorResolver.persist(RtcDeviceVendor.SHIMETA)
    }
    return vendor
  }
}
