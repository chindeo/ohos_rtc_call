import { RtcCallSettingPorts, RtcCallSettingOverride, RtcCallSettingOverrideStore } from './RtcCallSettingPorts'
import {
  CALL_SETTING_SOURCE_OVERRIDE,
  CALL_SETTING_SOURCE_RAWFILE,
  CALL_SETTING_SOURCE_REMOTE,
  RtcCallAudioSetting,
  RtcCallSettingBean,
  RtcCallSettingDiff,
  RtcCallSettingIdentity,
  RtcCallSettingOptions,
  RtcCallSettingResolution,
  RtcCallSettingSnapshot,
  RtcCallVideoProfile
} from './RtcCallSettingTypes'
import { RtcCallSettingPolicy } from './RtcCallSettingPolicy'

const DEFAULT_REFRESH_INTERVAL_MS: number = 5 * 60 * 1000

export type RtcCallSettingListener = (diff: RtcCallSettingDiff) => void

export class RtcCallSettingController {
  private ports: RtcCallSettingPorts
  private options: RtcCallSettingOptions
  private current: RtcCallSettingSnapshot | undefined = undefined
  private listeners: RtcCallSettingListener[] = []
  private loading: Promise<RtcCallSettingSnapshot> | undefined = undefined
  private refreshTimer: number = -1
  readonly overrides: RtcCallSettingOverride

  constructor(ports: RtcCallSettingPorts, options?: RtcCallSettingOptions) {
    this.ports = ports
    this.options = options || {}
    this.overrides = ports.override ||
      new RtcCallSettingOverrideStore(ports, this.options.overridePreferenceName)
  }

  identity(): RtcCallSettingIdentity {
    return this.ports.identity()
  }

  matchedBean(): RtcCallSettingBean | undefined {
    const beans = this.current ? this.current.beans : undefined
    return RtcCallSettingPolicy.selectBestMatch(beans, this.identity())
  }

  listResolutions(): RtcCallVideoProfile[] {
    const bean = this.matchedBean()
    const profiles: RtcCallVideoProfile[] = []
    RtcCallSettingPolicy.listResolutions(bean).forEach((resolution: RtcCallSettingResolution) => {
      const profile = RtcCallSettingPolicy.profileFromResolution(resolution, CALL_SETTING_SOURCE_OVERRIDE)
      if (profile) {
        profiles.push(profile)
      }
    })
    return profiles
  }

  snapshot(): RtcCallSettingSnapshot | undefined {
    return this.current
  }

  cachedProfile(): RtcCallVideoProfile | undefined {
    return this.current ? this.current.profile : undefined
  }

  cachedAudioSetting(): RtcCallAudioSetting | undefined {
    return this.current ? this.current.audio : undefined
  }

  onChange(listener: RtcCallSettingListener): () => void {
    this.listeners.push(listener)
    return () => {
      this.listeners = this.listeners.filter((item: RtcCallSettingListener) => item !== listener)
    }
  }

  async load(reason: string): Promise<RtcCallSettingSnapshot> {
    if (this.loading) {
      return await this.loading
    }
    const task = this.doLoad(reason)
    this.loading = task
    try {
      return await task
    } finally {
      this.loading = undefined
    }
  }

  private async doLoad(reason: string): Promise<RtcCallSettingSnapshot> {
    await this.overrides.restore()
    let beans: RtcCallSettingBean[] | undefined = undefined
    let source = CALL_SETTING_SOURCE_REMOTE
    try {
      beans = await this.ports.fetcher.fetchRemote()
    } catch (error) {
      this.ports.logger.warn(`call_setting remote failed reason=${reason}, error=${JSON.stringify(error)}`)
    }
    if (!beans || beans.length === 0) {
      source = CALL_SETTING_SOURCE_RAWFILE
      try {
        beans = await this.ports.fetcher.readBundled()
      } catch (error) {
        beans = undefined
        this.ports.logger.error(`call_setting bundled failed reason=${reason}, error=${JSON.stringify(error)}`)
      }
    }
    const identity: RtcCallSettingIdentity = this.ports.identity()
    const audio: RtcCallAudioSetting =
      RtcCallSettingPolicy.resolveAudioSetting(beans, identity, source)
    let profile: RtcCallVideoProfile | undefined =
      RtcCallSettingPolicy.resolveVideoProfile(beans, identity, source)
    let matchedBy = 'match'
    // 安卓 SettingDataUtil parseDefault：一条都匹配不到时取列表第一条，不再校验身份。
    if (!profile && this.options.firstBeanFallback !== false && beans && beans.length > 0) {
      profile = RtcCallSettingPolicy.profileFromBean(beans[0], source)
      matchedBy = 'firstBean'
    }
    if (!profile) {
      matchedBy = 'codeFallback'
      profile = RtcCallSettingPolicy.fallbackProfile()
    }
    const overrideProfile = RtcCallSettingPolicy.profileFromResolution(
      RtcCallSettingPolicy.findResolutionByLabel(
        RtcCallSettingPolicy.selectBestMatch(beans, identity), this.overrides.profileLabel()),
      CALL_SETTING_SOURCE_OVERRIDE)
    if (overrideProfile) {
      profile = overrideProfile
      matchedBy = 'localOverride'
    }
    this.applyAudioOverride(audio)
    const snapshot: RtcCallSettingSnapshot = {
      profile: profile,
      audio: audio,
      beans: beans || [],
      matchedBy: matchedBy,
      source: profile.source,
      reason: reason,
      fetchedAt: Date.now()
    }
    const previous = this.current
    this.current = snapshot
    this.ports.logger.info(`call_setting resolved reason=${reason}, source=${profile.source}, ` +
      `matchedBy=${matchedBy}, mac=${identity.mac}, packageName=${identity.packageName}, ` +
      `deviceType=${identity.deviceType}, profile=${profile.label} ${profile.width}x${profile.height}@${profile.frameRate}, ` +
      `maxKbps=${profile.maxBitrateKbps}, startKbps=${RtcCallSettingPolicy.resolveStartKbps(profile.maxBitrateKbps)}`)
    this.ports.logger.info(`call_setting volume resolved reason=${reason}, source=${audio.source}, ` +
      `deviceVolume=${audio.deviceVolume}, streamVolume=${audio.streamVolume}`)
    if (!previous || this.hasChanged(previous, snapshot)) {
      this.emit({
        profileChanged: !previous || previous.profile.label !== snapshot.profile.label ||
          previous.profile.width !== snapshot.profile.width ||
          previous.profile.height !== snapshot.profile.height ||
          previous.profile.frameRate !== snapshot.profile.frameRate ||
          previous.profile.maxBitrateKbps !== snapshot.profile.maxBitrateKbps,
        audioChanged: !previous || previous.audio.deviceVolume !== snapshot.audio.deviceVolume ||
          previous.audio.streamVolume !== snapshot.audio.streamVolume,
        previous: previous,
        current: snapshot
      })
    }
    return snapshot
  }

  private applyAudioOverride(audio: RtcCallAudioSetting): void {
    const percent = this.overrides.answerVolumePercent()
    if (percent >= 0) {
      audio.deviceVolume = percent
      audio.source = CALL_SETTING_SOURCE_OVERRIDE
    }
  }

  private hasChanged(previous: RtcCallSettingSnapshot, current: RtcCallSettingSnapshot): boolean {
    return previous.profile.label !== current.profile.label ||
      previous.profile.width !== current.profile.width ||
      previous.profile.height !== current.profile.height ||
      previous.profile.frameRate !== current.profile.frameRate ||
      previous.profile.maxBitrateKbps !== current.profile.maxBitrateKbps ||
      previous.audio.deviceVolume !== current.audio.deviceVolume ||
      previous.audio.streamVolume !== current.audio.streamVolume
  }

  private emit(diff: RtcCallSettingDiff): void {
    this.listeners.forEach((listener: RtcCallSettingListener) => listener(diff))
  }

  async saveOverride(profileLabel: string, answerVolumePercent: number, reason: string)
    : Promise<RtcCallSettingSnapshot> {
    await this.overrides.setProfileLabel(profileLabel)
    await this.overrides.setAnswerVolumePercent(answerVolumePercent)
    return await this.load(reason)
  }

  async clearOverride(reason: string): Promise<RtcCallSettingSnapshot> {
    await this.overrides.clear()
    return await this.load(reason)
  }

  startAutoRefresh(intervalMs: number = DEFAULT_REFRESH_INTERVAL_MS): void {
    this.stopAutoRefresh()
    if (intervalMs <= 0) {
      return
    }
    this.refreshTimer = setInterval(() => {
      this.load('auto refresh').catch((error: Error) => {
        this.ports.logger.warn(`call_setting auto refresh failed: ${error.message}`)
      })
    }, intervalMs)
    this.ports.logger.info(`call_setting auto refresh started intervalMs=${intervalMs}`)
  }

  stopAutoRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = -1
      this.ports.logger.info('call_setting auto refresh stopped')
    }
  }
}
