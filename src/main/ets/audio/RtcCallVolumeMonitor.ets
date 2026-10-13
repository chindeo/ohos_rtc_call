import audio from '@ohos.multimedia.audio'

export const RTC_DEFAULT_DNAKE_TALK_VOLUME = 1
export const RTC_DEFAULT_WEBRTC_CALL_VOLUME_PERCENT = 90
export const RTC_MIN_VISIBLE_VOLUME_PERCENT = 3
const RTC_DEFAULT_VOICE_CALL_MIN_LEVEL = 0
const RTC_DEFAULT_VOICE_CALL_MAX_LEVEL = 15

export interface RtcCallVolumeSnapshot {
  minLevel: number
  maxLevel: number
  currentLevel: number
  percent: number
}

/**
 * 一次通话音量写入的实测结果。SDK 23 的 AudioVolumeGroupManager 只有 getter，
 * 唯一可写的 AudioManager.setVolume 自 API 9 就标记废弃，所以"没有抛错"并不等于
 * 设备真的改了档——必须写前写后各读一次。
 */
export interface RtcCallVolumeWriteResult {
  requestedLevel: number
  beforeLevel: number
  afterLevel: number
  maxLevel: number
  errorText: string
}

export class RtcCallVolumeMonitor {
  private static hasCachedSnapshot: boolean = false
  private static cachedSnapshot: RtcCallVolumeSnapshot = {
    minLevel: RTC_DEFAULT_VOICE_CALL_MIN_LEVEL,
    maxLevel: RTC_DEFAULT_VOICE_CALL_MAX_LEVEL,
    currentLevel: RtcCallVolumeMonitor.getVolumeLevelByPercent(
      RTC_DEFAULT_WEBRTC_CALL_VOLUME_PERCENT,
      RTC_DEFAULT_VOICE_CALL_MIN_LEVEL,
      RTC_DEFAULT_VOICE_CALL_MAX_LEVEL
    ),
    percent: RTC_DEFAULT_WEBRTC_CALL_VOLUME_PERCENT
  }

  static readVoiceCallVolumeSnapshot(): RtcCallVolumeSnapshot {
    const volumeGroupManager = audio.getAudioManager()
      .getVolumeManager()
      .getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
    const volumeType = audio.AudioVolumeType.VOICE_CALL
    const minLevel = volumeGroupManager.getMinVolumeSync(volumeType)
    const maxLevel = volumeGroupManager.getMaxVolumeSync(volumeType)
    const currentLevel = volumeGroupManager.getVolumeSync(volumeType)
    const snapshot: RtcCallVolumeSnapshot = {
      minLevel,
      maxLevel,
      currentLevel,
      percent: RtcCallVolumeMonitor.getVolumePercent(currentLevel, minLevel, maxLevel)
    }
    RtcCallVolumeMonitor.cachedSnapshot = snapshot
    RtcCallVolumeMonitor.hasCachedSnapshot = true
    return snapshot
  }

  static readCachedVoiceCallVolumeSnapshot(defaultPercent: number = RTC_DEFAULT_WEBRTC_CALL_VOLUME_PERCENT): RtcCallVolumeSnapshot {
    if (RtcCallVolumeMonitor.hasCachedSnapshot) {
      return RtcCallVolumeMonitor.cachedSnapshot
    }
    const currentLevel = RtcCallVolumeMonitor.getVolumeLevelByPercent(
      defaultPercent,
      RTC_DEFAULT_VOICE_CALL_MIN_LEVEL,
      RTC_DEFAULT_VOICE_CALL_MAX_LEVEL
    )
    RtcCallVolumeMonitor.cachedSnapshot = {
      minLevel: RTC_DEFAULT_VOICE_CALL_MIN_LEVEL,
      maxLevel: RTC_DEFAULT_VOICE_CALL_MAX_LEVEL,
      currentLevel,
      percent: defaultPercent
    }
    return RtcCallVolumeMonitor.cachedSnapshot
  }

  static getVolumePercent(volume: number, minVolume: number, maxVolume: number): number {
    if (maxVolume <= minVolume) {
      return 0
    }
    return Math.max(0, Math.min(100,
      Math.round(((volume - minVolume) / (maxVolume - minVolume)) * 100)))
  }

  static getVisibleVolumePercent(percent: number): number {
    if (percent <= 0) {
      return RTC_MIN_VISIBLE_VOLUME_PERCENT
    }
    return Math.max(0, Math.min(100, percent))
  }

  static getVolumeLevelByPercent(percent: number, minVolume: number, maxVolume: number): number {
    const boundedPercent = Math.max(0, Math.min(100, percent))
    return Math.round(minVolume + (boundedPercent / 100) * (maxVolume - minVolume))
  }

  static async setVoiceCallVolume(volume: number, reason: string = 'volume write'): Promise<RtcCallVolumeWriteResult> {
    let beforeLevel = -1
    let afterLevel = -1
    let maxLevel = -1
    try {
      const before = RtcCallVolumeMonitor.readVoiceCallVolumeSnapshot()
      beforeLevel = before.currentLevel
      maxLevel = before.maxLevel
    } catch (error) {
      console.warn(`RtcCallVolumeMonitor read before write failed: ${JSON.stringify(error)}`)
    }
    let errorText = ''
    try {
      await audio.getAudioManager().setVolume(audio.AudioVolumeType.VOICE_CALL, volume)
    } catch (error) {
      errorText = JSON.stringify(error)
    }
    try {
      afterLevel = RtcCallVolumeMonitor.readVoiceCallVolumeSnapshot().currentLevel
    } catch (error) {
      console.warn(`RtcCallVolumeMonitor read after write failed: ${JSON.stringify(error)}`)
    }
    console.info(`RtcCallVolumeMonitor voice_call_volume_write reason=${reason} requested=${volume} ` +
      `before=${beforeLevel} after=${afterLevel} max=${maxLevel} ` +
      `applied=${afterLevel === volume} error=${errorText || 'none'}`)
    return { requestedLevel: volume, beforeLevel, afterLevel, maxLevel, errorText }
  }
}
