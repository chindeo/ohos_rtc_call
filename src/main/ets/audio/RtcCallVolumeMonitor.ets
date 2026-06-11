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

  static async setVoiceCallVolume(volume: number): Promise<void> {
    await audio.getAudioManager().setVolume(audio.AudioVolumeType.VOICE_CALL, volume)
  }
}
