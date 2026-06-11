import { RtcCallRoute, RtcCallRouteOptions, RtcCallRouteResolver } from './RtcCallRouteResolver'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'

export const RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST = 'call.rtcServerHost'
export const RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING = 'call.micSwitching'

export interface RtcRuntimeAudioVideoOptions extends RtcCallRouteOptions {
  reason?: string
}

export interface RtcRuntimeRefreshOptions extends RtcRuntimeAudioVideoOptions {
  changedKeys?: string[]
  runtimeConfigMap?: Record<string, string>
  micSwitchingValue?: string
  applyMicSwitchingOnInitial?: boolean
}

export interface RtcRuntimeSwitchPlan {
  route: RtcCallRoute
  protocol: RtcTransportProtocol
  shouldPrepare: boolean
  rtcServerHostChanged: boolean
  micSwitchingChanged: boolean
  micSwitchingPresent: boolean
  micSwitchingValue: string
  micSwitchingEnabled: boolean
  shouldApplyMicSwitching: boolean
  reason: string
}

export interface RtcRuntimeSwitchHandlers {
  prepareWebRtc(route: RtcCallRoute, plan: RtcRuntimeSwitchPlan): Promise<void>
  prepareSip(route: RtcCallRoute, plan: RtcRuntimeSwitchPlan): Promise<void>
  applyMicSwitching?(plan: RtcRuntimeSwitchPlan): Promise<void>
}

export class RtcRuntimeConfigCoordinator {
  static resolveAudioVideoRoute(options: RtcRuntimeAudioVideoOptions): RtcCallRoute {
    return RtcCallRouteResolver.resolve(options)
  }

  static isWebRtcAddress(registerAddress: string): boolean {
    return RtcRuntimeConfigCoordinator.resolveAudioVideoRoute({ registerAddress }).protocol === RtcTransportProtocol.WEBRTC
  }

  static hasRtcServerHostChanged(changedKeys: string[] = []): boolean {
    return changedKeys.indexOf(RTC_RUNTIME_CONFIG_KEY_RTC_SERVER_HOST) >= 0
  }

  static hasMicSwitchingChanged(changedKeys: string[] = []): boolean {
    return changedKeys.indexOf(RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING) >= 0
  }

  static parseBooleanConfigValue(value: string): boolean {
    const normalized = (value || '').trim().toLowerCase()
    if (!normalized) {
      return false
    }
    if (normalized === '1' || normalized === 'true' || normalized === 'on' || normalized === 'yes' ||
      normalized === 'enable' || normalized === 'enabled') {
      return true
    }
    if (normalized === '0' || normalized === 'false' || normalized === 'off' || normalized === 'no' ||
      normalized === 'disable' || normalized === 'disabled') {
      return false
    }
    const numberValue = Number(normalized)
    if (!Number.isNaN(numberValue)) {
      return numberValue !== 0
    }
    return false
  }

  private static hasMicSwitchingValue(options: RtcRuntimeRefreshOptions): boolean {
    if (options.micSwitchingValue !== undefined) {
      return true
    }
    const map = options.runtimeConfigMap
    return !!map && map[RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING] !== undefined
  }

  private static getMicSwitchingValue(options: RtcRuntimeRefreshOptions): string {
    if (options.micSwitchingValue !== undefined) {
      return options.micSwitchingValue
    }
    const map = options.runtimeConfigMap
    if (map && map[RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING] !== undefined) {
      return map[RTC_RUNTIME_CONFIG_KEY_MIC_SWITCHING]
    }
    return ''
  }

  static createSwitchPlan(options: RtcRuntimeRefreshOptions): RtcRuntimeSwitchPlan {
    const route = RtcRuntimeConfigCoordinator.resolveAudioVideoRoute(options)
    const rtcServerHostChanged = RtcRuntimeConfigCoordinator.hasRtcServerHostChanged(options.changedKeys || [])
    const micSwitchingChanged = RtcRuntimeConfigCoordinator.hasMicSwitchingChanged(options.changedKeys || [])
    const micSwitchingPresent = RtcRuntimeConfigCoordinator.hasMicSwitchingValue(options)
    const micSwitchingValue = RtcRuntimeConfigCoordinator.getMicSwitchingValue(options)
    return {
      route,
      protocol: route.protocol,
      shouldPrepare: !options.changedKeys || options.changedKeys.length === 0 || rtcServerHostChanged,
      rtcServerHostChanged,
      micSwitchingChanged,
      micSwitchingPresent,
      micSwitchingValue,
      micSwitchingEnabled: RtcRuntimeConfigCoordinator.parseBooleanConfigValue(micSwitchingValue),
      shouldApplyMicSwitching: micSwitchingPresent &&
        (micSwitchingChanged || (!options.changedKeys || options.changedKeys.length === 0) ||
          options.applyMicSwitchingOnInitial === true),
      reason: options.reason || (rtcServerHostChanged ? 'runtime rtc host changed' : 'runtime config refresh')
    }
  }

  static async applySwitchPlan(plan: RtcRuntimeSwitchPlan, handlers: RtcRuntimeSwitchHandlers): Promise<void> {
    if (!plan.shouldPrepare) {
      return
    }
    if (plan.protocol === RtcTransportProtocol.WEBRTC) {
      await handlers.prepareWebRtc(plan.route, plan)
      return
    }
    await handlers.prepareSip(plan.route, plan)
  }

  static async applyMicSwitching(plan: RtcRuntimeSwitchPlan, handlers: RtcRuntimeSwitchHandlers): Promise<void> {
    if (!plan.shouldApplyMicSwitching || !handlers.applyMicSwitching) {
      return
    }
    await handlers.applyMicSwitching(plan)
  }

  static async handleRefresh(options: RtcRuntimeRefreshOptions, handlers: RtcRuntimeSwitchHandlers): Promise<RtcRuntimeSwitchPlan> {
    const plan = RtcRuntimeConfigCoordinator.createSwitchPlan(options)
    await RtcRuntimeConfigCoordinator.applySwitchPlan(plan, handlers)
    await RtcRuntimeConfigCoordinator.applyMicSwitching(plan, handlers)
    return plan
  }
}
