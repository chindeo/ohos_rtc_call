import hilog from '@ohos.hilog'
import bundleManager from '@ohos.bundle.bundleManager'
import shimeta from '@ohos.shimeta'
import {
  createFailedResult,
  createSuccessResult,
  createUnsupportedResult,
  RtcAutoPowerOnOffConfig,
  RtcDeviceBootAppOptions,
  RtcDeviceCapabilityAdapter,
  RtcDeviceCapabilityResult,
  RtcDeviceKeepAliveOptions,
  RtcDeviceMacOptions,
  RtcMacAddressUtils,
  RtcSilentInstallOptions
} from './RtcDeviceCapabilityAdapter'
import { RtcDeviceVendor } from './RtcDeviceVendor'

const TAG = 'RtcShimetaDeviceAdapter'

function readShimetaMac(type: string): string {
  try {
    const mac = RtcMacAddressUtils.normalize(shimeta.net_getMacAddress(type))
    if (RtcMacAddressUtils.isValid(mac)) {
      hilog.info(0, TAG, `use Shimeta ${type} MAC=${mac}`)
      return mac
    }
    hilog.warn(0, TAG, `invalid Shimeta ${type} MAC=${mac}`)
  } catch (error) {
    hilog.warn(0, TAG, `read Shimeta ${type} MAC failed: ${JSON.stringify(error)}`)
  }
  return ''
}

function buildBootParam(options: RtcDeviceBootAppOptions): string {
  if (options.bootParam) {
    return options.bootParam
  }
  if (!options.abilityName || !options.bundleName || !options.moduleName) {
    return ''
  }
  return `${options.abilityName}/${options.bundleName}/${options.moduleName}`
}

async function resolveCurrentBootParam(options?: RtcDeviceBootAppOptions): Promise<string> {
  const preset = buildBootParam(options || {})
  if (preset) {
    return preset
  }

  const flags =
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_ABILITY |
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE
  const info = await bundleManager.getBundleInfoForSelf(flags)
  const moduleInfo = info.hapModulesInfo && info.hapModulesInfo.length > 0 ? info.hapModulesInfo[0] : undefined
  const abilityName = options?.abilityName || moduleInfo?.mainElementName || ''
  const bundleName = options?.bundleName || info.name || ''
  const moduleName = options?.moduleName || moduleInfo?.name || ''
  return buildBootParam({
    abilityName,
    bundleName,
    moduleName
  })
}

export class RtcShimetaDeviceAdapter implements RtcDeviceCapabilityAdapter {
  readonly vendor: RtcDeviceVendor = RtcDeviceVendor.SHIMETA

  isAvailable(): boolean {
    return !!readShimetaMac('eth0') || !!readShimetaMac('eth1')
  }

  async getDeviceMac(options?: RtcDeviceMacOptions): Promise<string> {
    const firstType = options?.preferEthernet === false ? 'eth1' : 'eth0'
    const secondType = firstType === 'eth0' ? 'eth1' : 'eth0'
    return readShimetaMac(firstType) || readShimetaMac(secondType)
  }

  async getBootApp(): Promise<string> {
    try {
      return shimeta.sys_getSystemBootApp() || ''
    } catch (error) {
      hilog.warn(0, TAG, `get Shimeta boot app failed: ${JSON.stringify(error)}`)
      return ''
    }
  }

  async setBootApp(options?: RtcDeviceBootAppOptions): Promise<RtcDeviceCapabilityResult<string>> {
    try {
      const bootParam = await resolveCurrentBootParam(options)
      if (!bootParam) {
        return createFailedResult<string>('Shimeta boot app param is empty')
      }
      const current = await this.getBootApp()
      if (current === bootParam) {
        return createSuccessResult<string>(bootParam, 'Shimeta boot app already configured')
      }
      const ret = shimeta.sys_setSystemBootApp(bootParam)
      if (ret === 0) {
        return createSuccessResult<string>(bootParam, 'Shimeta boot app configured')
      }
      return createFailedResult<string>(`Shimeta boot app configure failed code=${ret}`, String(ret))
    } catch (error) {
      return createFailedResult<string>('Shimeta boot app configure failed', JSON.stringify(error))
    }
  }

  async setAutoPowerOnOff(config: RtcAutoPowerOnOffConfig): Promise<RtcDeviceCapabilityResult<number>> {
    try {
      const ret = shimeta.sys_setAutoPowerOnOff(
        config.enable,
        config.week,
        config.onHour,
        config.onMinute,
        config.offHour,
        config.offMinute
      )
      if (ret === 0) {
        return createSuccessResult<number>(ret, 'Shimeta auto power on/off configured')
      }
      return createFailedResult<number>(`Shimeta auto power on/off failed code=${ret}`, String(ret))
    } catch (error) {
      return createFailedResult<number>('Shimeta auto power on/off failed', JSON.stringify(error))
    }
  }

  async getAutoPowerOnOff(): Promise<string> {
    try {
      return await shimeta.sys_getAutoPowerOnOff()
    } catch (error) {
      hilog.warn(0, TAG, `get Shimeta auto power on/off failed: ${JSON.stringify(error)}`)
      return ''
    }
  }

  async silentInstallApp(options: RtcSilentInstallOptions): Promise<RtcDeviceCapabilityResult<number>> {
    try {
      const ret = shimeta.sys_doSilentInstallApp(options.hapPath, options.isRun, options.bundleName)
      if (ret === 0) {
        return createSuccessResult<number>(ret, 'Shimeta silent install succeed')
      }
      return createFailedResult<number>(`Shimeta silent install failed code=${ret}`, String(ret))
    } catch (error) {
      return createFailedResult<number>('Shimeta silent install failed', JSON.stringify(error))
    }
  }

  async startKeepAlive(options: RtcDeviceKeepAliveOptions): Promise<RtcDeviceCapabilityResult<boolean>> {
    return createUnsupportedResult<boolean>(
      'Shimeta keep alive requires privileged ServiceExtensionAbility and system install_list_capability.json configuration'
    )
  }
}
