import {
  RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING,
  RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST,
  RtcRuntimeRefreshOptions,
  RtcRuntimeSwitchHandlers,
  RtcRuntimeSwitchPlan,
  RtcRuntimeConfigCoordinator
} from './RtcRuntimeConfigCoordinator'

export type RtcRuntimeConfigMap = Record<string, string>
export type RtcRuntimeConfigLoader = () => Promise<RtcRuntimeConfigMap>

export interface RtcRuntimeConfigControllerOptions {
  defaultRegisterAddress: string
  loader: RtcRuntimeConfigLoader
  handlers: RtcRuntimeSwitchHandlers
  sipUser?: string
  sipPassword?: string
  ntpServer?: string
  bindingCode?: string
  deviceIp?: string
  rtcServerHostKey?: string
  applyMicSwitchingOnInitial?: boolean
}

export class RtcRuntimeResolvedConfig {
  registerAddress: string = ''
  rtcServerHost: string = ''
  micSwitchingValue: string = ''
  micSwitchingEnabled: boolean = false
}

export class RtcRuntimeConfigControllerResult {
  config: RtcRuntimeConfigMap = {}
  changedKeys: string[] = []
  resolved: RtcRuntimeResolvedConfig = new RtcRuntimeResolvedConfig()
  plan?: RtcRuntimeSwitchPlan
}

export class RtcRuntimeConfigController {
  private options: RtcRuntimeConfigControllerOptions
  private currentConfig?: RtcRuntimeConfigMap

  constructor(options: RtcRuntimeConfigControllerOptions) {
    this.options = options
  }

  async loadInitial(reason: string = 'runtime config initial'): Promise<RtcRuntimeConfigControllerResult> {
    const nextConfig = await this.options.loader()
    const result = await this.applyConfig(nextConfig, [], reason, this.options.applyMicSwitchingOnInitial === true)
    this.currentConfig = nextConfig
    return result
  }

  async refresh(reason: string = 'runtime config refresh'): Promise<RtcRuntimeConfigControllerResult> {
    const nextConfig = await this.options.loader()
    const changedKeys = RtcRuntimeConfigController.diffChangedKeys(this.currentConfig, nextConfig)
    const result = await this.applyConfig(nextConfig, changedKeys, reason, false)
    this.currentConfig = nextConfig
    return result
  }

  getCurrentConfig(): RtcRuntimeConfigMap | undefined {
    return this.currentConfig
  }

  static selectRtcServerHost(config: RtcRuntimeConfigMap | undefined, fallback: string, key: string = RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST): string {
    const value = RtcRuntimeConfigController.getConfigValue(config, key)
    return value.length > 0 ? value : fallback
  }

  static resolveConfig(config: RtcRuntimeConfigMap | undefined, defaultRegisterAddress: string,
    rtcServerHostKey: string = RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST): RtcRuntimeResolvedConfig {
    const resolved = new RtcRuntimeResolvedConfig()
    resolved.rtcServerHost = RtcRuntimeConfigController.selectRtcServerHost(config, defaultRegisterAddress, rtcServerHostKey)
    resolved.registerAddress = resolved.rtcServerHost
    resolved.micSwitchingValue = RtcRuntimeConfigController.getConfigValue(config, RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING)
    resolved.micSwitchingEnabled = RtcRuntimeConfigCoordinator.parseBooleanConfigValue(resolved.micSwitchingValue)
    return resolved
  }

  static diffChangedKeys(previous: RtcRuntimeConfigMap | undefined, next: RtcRuntimeConfigMap): string[] {
    if (!previous) {
      return []
    }
    const changedKeys: string[] = []
    const visited: string[] = []
    const nextKeys = Object.keys(next)
    for (let i = 0; i < nextKeys.length; i += 1) {
      const key = nextKeys[i]
      visited.push(key)
      if (previous[key] !== next[key]) {
        changedKeys.push(key)
      }
    }
    const previousKeys = Object.keys(previous)
    for (let i = 0; i < previousKeys.length; i += 1) {
      const key = previousKeys[i]
      if (visited.indexOf(key) < 0) {
        changedKeys.push(key)
      }
    }
    return changedKeys
  }

  private async applyConfig(config: RtcRuntimeConfigMap, changedKeys: string[], reason: string,
    applyMicSwitchingOnInitial: boolean): Promise<RtcRuntimeConfigControllerResult> {
    const resolved = RtcRuntimeConfigController.resolveConfig(
      config,
      this.options.defaultRegisterAddress,
      this.options.rtcServerHostKey
    )
    const refreshOptions: RtcRuntimeRefreshOptions = {
      registerAddress: resolved.registerAddress,
      sipUser: this.options.sipUser,
      sipPassword: this.options.sipPassword,
      ntpServer: this.options.ntpServer,
      bindingCode: this.options.bindingCode,
      deviceIp: this.options.deviceIp,
      changedKeys,
      runtimeConfigMap: config,
      micSwitchingValue: resolved.micSwitchingValue,
      applyMicSwitchingOnInitial,
      reason
    }
    const plan = await RtcRuntimeConfigCoordinator.handleRefresh(refreshOptions, this.options.handlers)
    const result = new RtcRuntimeConfigControllerResult()
    result.config = config
    result.changedKeys = changedKeys
    result.resolved = resolved
    result.plan = plan
    return result
  }

  private static getConfigValue(config: RtcRuntimeConfigMap | undefined, key: string): string {
    if (!config || config[key] === undefined) {
      return ''
    }
    return (config[key] || '').trim()
  }
}
