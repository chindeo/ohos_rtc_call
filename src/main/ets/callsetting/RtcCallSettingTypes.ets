export interface RtcCallSettingResolution {
  enabled?: boolean
  label?: string
  fps?: number
  kbps?: number
  width?: number
  height?: number
}

export interface RtcCallSettingBean {
  mac?: string
  deviceType?: string
  packageName?: string
  deviceVolume?: number
  streamVolume?: number
  isDeviceUpdate?: boolean
  videoResolution?: RtcCallSettingResolution[]
}

export interface RtcCallSettingIdentity {
  mac: string
  packageName: string
  deviceType: string
}

export interface RtcCallVideoProfile {
  width: number
  height: number
  frameRate: number
  maxBitrateKbps: number
  label: string
  source: string
}

export interface RtcCallAudioSetting {
  deviceVolume: number
  streamVolume: number
  source: string
}

export const CALL_SETTING_SOURCE_REMOTE: string = 'remote'
export const CALL_SETTING_SOURCE_RAWFILE: string = 'rawfile'
export const CALL_SETTING_SOURCE_FALLBACK: string = 'fallback'
export const CALL_SETTING_SOURCE_DEFAULT: string = 'default'
export const CALL_SETTING_SOURCE_OVERRIDE: string = 'override'

export interface RtcCallVideoProfileResolution {
  profile?: RtcCallVideoProfile
  matchedBy: string
}

export interface RtcCallSettingSnapshot {
  profile: RtcCallVideoProfile
  audio: RtcCallAudioSetting
  beans: RtcCallSettingBean[]
  matchedBy: string
  source: string
  reason: string
  fetchedAt: number
}

export interface RtcCallSettingDiff {
  profileChanged: boolean
  audioChanged: boolean
  previous: RtcCallSettingSnapshot | undefined
  current: RtcCallSettingSnapshot
}

export interface RtcCallSettingOptions {
  // 安卓 SettingDataUtil.clean() 只做 trim，不做 mac 归一化；默认保持不归一化。
  normalizeMac?: boolean
  // 安卓 parseDefault = selectBestMatch ?: beans.first()，一条都不匹配时取第一行。
  firstBeanFallback?: boolean
  overridePreferenceName?: string
}
