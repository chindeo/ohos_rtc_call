import {
  CALL_SETTING_SOURCE_DEFAULT,
  CALL_SETTING_SOURCE_FALLBACK,
  RtcCallAudioSetting,
  RtcCallSettingBean,
  RtcCallSettingIdentity,
  RtcCallSettingOptions,
  RtcCallSettingResolution,
  RtcCallVideoProfile
} from './RtcCallSettingTypes'

const RESOLUTION_LIMIT: number = 4096
const FPS_LIMIT: number = 60
const KBPS_LIMIT: number = 100000
const START_KBPS_FLOOR: number = 300
const START_KBPS_CEILING: number = 1800
const DEVICE_VOLUME_MIN: number = -1
const DEVICE_VOLUME_MAX: number = 100
const STREAM_VOLUME_MIN: number = 0
const STREAM_VOLUME_MAX: number = 250

export class RtcCallSettingPolicy {
  static readonly FALLBACK_WIDTH: number = 640
  static readonly FALLBACK_HEIGHT: number = 480
  static readonly FALLBACK_FPS: number = 15
  static readonly FALLBACK_MAX_KBPS: number = 1500
  static readonly DEFAULT_DEVICE_VOLUME: number = DEVICE_VOLUME_MIN
  static readonly DEFAULT_STREAM_VOLUME: number = 100

  private static clean(value: string | undefined): string {
    if (typeof value !== 'string') {
      return ''
    }
    return value.trim()
  }

  static normalizeMac(value: string | undefined): string {
    return RtcCallSettingPolicy.clean(value).replace(/[:\-\s]/g, '').toUpperCase()
  }

  static identityMac(value: string | undefined, options?: RtcCallSettingOptions): string {
    return options?.normalizeMac === true ? RtcCallSettingPolicy.normalizeMac(value) :
      RtcCallSettingPolicy.clean(value)
  }

  static matchPriority(bean: RtcCallSettingBean, identity: RtcCallSettingIdentity): number {
    const beanMac = RtcCallSettingPolicy.clean(bean.mac)
    const beanDeviceType = RtcCallSettingPolicy.clean(bean.deviceType)
    const beanPackageName = RtcCallSettingPolicy.clean(bean.packageName)
    const deviceType = RtcCallSettingPolicy.clean(identity.deviceType)
    const packageName = RtcCallSettingPolicy.clean(identity.packageName)
    if (beanMac.length > 0) {
      if (beanMac !== RtcCallSettingPolicy.clean(identity.mac)) {
        return 0
      }
      if (beanDeviceType.length > 0 && beanDeviceType !== deviceType) {
        return 0
      }
      if (beanPackageName.length > 0 && beanPackageName !== packageName) {
        return 0
      }
      return 5
    }
    if (beanDeviceType.length > 0 && beanDeviceType !== deviceType) {
      return 0
    }
    if (beanPackageName.length > 0 && beanPackageName !== packageName) {
      return 0
    }
    if (beanDeviceType.length > 0 && beanPackageName.length > 0) {
      return 4
    }
    if (beanDeviceType.length > 0) {
      return 3
    }
    if (beanPackageName.length > 0) {
      return 2
    }
    return 1
  }

  static selectBestMatch(
    beans: RtcCallSettingBean[] | undefined,
    identity: RtcCallSettingIdentity
  ): RtcCallSettingBean | undefined {
    if (!beans || beans.length === 0) {
      return undefined
    }
    let best: RtcCallSettingBean | undefined = undefined
    let bestPriority = 0
    for (let index = 0; index < beans.length; index++) {
      const priority = RtcCallSettingPolicy.matchPriority(beans[index], identity)
      if (priority === 0) {
        continue
      }
      if (priority > bestPriority) {
        bestPriority = priority
        best = beans[index]
        if (priority === 5) {
          return best
        }
      }
    }
    return best
  }

  private static sanitizeResolution(value: number | undefined, fallback: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > RESOLUTION_LIMIT) {
      return fallback
    }
    return value
  }

  private static sanitizeFps(value: number | undefined, fallback: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > FPS_LIMIT) {
      return fallback
    }
    return value
  }

  private static sanitizeKbps(value: number | undefined, fallback: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > KBPS_LIMIT) {
      return fallback
    }
    return value
  }

  static resolveStartKbps(maxKbps: number): number {
    const safeMax = RtcCallSettingPolicy.sanitizeKbps(maxKbps, RtcCallSettingPolicy.FALLBACK_MAX_KBPS)
    const raw = Math.round(safeMax * 0.4)
    const clamped = Math.max(START_KBPS_FLOOR, Math.min(START_KBPS_CEILING, raw))
    return Math.min(safeMax, clamped)
  }

  static profileFromResolution(
    resolution: RtcCallSettingResolution | undefined,
    source: string
  ): RtcCallVideoProfile | undefined {
    if (!resolution) {
      return undefined
    }
    const profile: RtcCallVideoProfile = {
      width: RtcCallSettingPolicy.sanitizeResolution(resolution.width, RtcCallSettingPolicy.FALLBACK_WIDTH),
      height: RtcCallSettingPolicy.sanitizeResolution(resolution.height, RtcCallSettingPolicy.FALLBACK_HEIGHT),
      frameRate: RtcCallSettingPolicy.sanitizeFps(resolution.fps, RtcCallSettingPolicy.FALLBACK_FPS),
      maxBitrateKbps: RtcCallSettingPolicy.sanitizeKbps(resolution.kbps, RtcCallSettingPolicy.FALLBACK_MAX_KBPS),
      label: typeof resolution.label === 'string' ? resolution.label : '',
      source: source
    }
    return profile
  }

  static findResolutionByLabel(
    bean: RtcCallSettingBean | undefined,
    label: string
  ): RtcCallSettingResolution | undefined {
    const resolutions = bean ? bean.videoResolution : undefined
    if (!resolutions || !label) {
      return undefined
    }
    for (let index = 0; index < resolutions.length; index++) {
      if (resolutions[index].label === label) {
        return resolutions[index]
      }
    }
    return undefined
  }

  static listResolutions(bean: RtcCallSettingBean | undefined): RtcCallSettingResolution[] {
    const resolutions = bean ? bean.videoResolution : undefined
    return resolutions ? resolutions : []
  }

  static profileFromBean(bean: RtcCallSettingBean | undefined, source: string): RtcCallVideoProfile | undefined {
    const resolutions = RtcCallSettingPolicy.listResolutions(bean)
    for (let index = 0; index < resolutions.length; index++) {
      if (resolutions[index].enabled === true) {
        return RtcCallSettingPolicy.profileFromResolution(resolutions[index], source)
      }
    }
    return undefined
  }

  static resolveVideoProfile(
    beans: RtcCallSettingBean[] | undefined,
    identity: RtcCallSettingIdentity,
    source: string
  ): RtcCallVideoProfile | undefined {
    return RtcCallSettingPolicy.profileFromBean(
      RtcCallSettingPolicy.selectBestMatch(beans, identity), source)
  }

  // 只做"匹配到的那一行"，firstBean 兜底由调用方决定，保持与拆分前一致。
  static isServerProfile(profile: RtcCallVideoProfile | undefined): boolean {
    return !!profile && profile.source !== CALL_SETTING_SOURCE_FALLBACK &&
      profile.source !== CALL_SETTING_SOURCE_DEFAULT
  }

  private static clampNumber(
    value: number | undefined,
    fallback: number,
    min: number,
    max: number
  ): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return fallback
    }
    return Math.max(min, Math.min(max, Math.round(value)))
  }

  static resolveAudioSetting(
    beans: RtcCallSettingBean[] | undefined,
    identity: RtcCallSettingIdentity,
    source: string
  ): RtcCallAudioSetting {
    const bean = RtcCallSettingPolicy.selectBestMatch(beans, identity)
    const setting: RtcCallAudioSetting = {
      deviceVolume: RtcCallSettingPolicy.clampNumber(
        bean ? bean.deviceVolume : undefined,
        RtcCallSettingPolicy.DEFAULT_DEVICE_VOLUME,
        DEVICE_VOLUME_MIN,
        DEVICE_VOLUME_MAX
      ),
      streamVolume: RtcCallSettingPolicy.clampNumber(
        bean ? bean.streamVolume : undefined,
        RtcCallSettingPolicy.DEFAULT_STREAM_VOLUME,
        STREAM_VOLUME_MIN,
        STREAM_VOLUME_MAX
      ),
      source: bean ? source : CALL_SETTING_SOURCE_DEFAULT
    }
    return setting
  }

  static fallbackProfile(): RtcCallVideoProfile {
    const profile: RtcCallVideoProfile = {
      width: RtcCallSettingPolicy.FALLBACK_WIDTH,
      height: RtcCallSettingPolicy.FALLBACK_HEIGHT,
      frameRate: RtcCallSettingPolicy.FALLBACK_FPS,
      maxBitrateKbps: RtcCallSettingPolicy.FALLBACK_MAX_KBPS,
      label: 'fallback',
      source: 'fallback'
    }
    return profile
  }
}
