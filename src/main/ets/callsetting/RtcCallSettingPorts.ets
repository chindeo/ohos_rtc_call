import dataPreferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import {
  RtcCallSettingBean,
  RtcCallSettingIdentity
} from './RtcCallSettingTypes'

const OVERRIDE_PREFERENCE_NAME = 'rtcCall'
const KEY_PROFILE_LABEL = 'rtc_call_override_profile_label'
const KEY_ANSWER_VOLUME_PERCENT = 'rtc_call_override_answer_volume_percent'
const ANSWER_VOLUME_UNSET: number = -1

export interface RtcCallSettingFetcher {
  fetchRemote(): Promise<RtcCallSettingBean[] | undefined>
  readBundled(): Promise<RtcCallSettingBean[] | undefined>
}

export interface RtcCallSettingLogger {
  info(message: string): void
  warn(message: string): void
  error(message: string): void
}

export interface RtcCallSettingOverride {
  restore(): Promise<void>
  profileLabel(): string
  answerVolumePercent(): number
  setProfileLabel(label: string): Promise<void>
  setAnswerVolumePercent(percent: number): Promise<void>
  clear(): Promise<void>
}

export interface RtcCallSettingPorts {
  fetcher: RtcCallSettingFetcher
  logger: RtcCallSettingLogger
  identity: () => RtcCallSettingIdentity
  // 只有默认的 dataPreferences 覆盖存储需要；注入 override 替身时可以省略。
  context?: () => common.Context
  // 不传则用 dataPreferences 默认实现；测试可注入替身。
  override?: RtcCallSettingOverride
}

export class RtcCallSettingOverrideStore implements RtcCallSettingOverride {
  private profileLabelValue: string = ''
  private answerVolumePercentValue: number = ANSWER_VOLUME_UNSET
  private loaded: boolean = false

  constructor(private ports: RtcCallSettingPorts, private preferenceName: string = OVERRIDE_PREFERENCE_NAME) {
  }

  async restore(): Promise<void> {
    const context = this.ports.context ? this.ports.context() : undefined
    if (!context) {
      this.ports.logger.warn('override restore skipped reason=noContext')
      return
    }
    try {
      const preferences = await dataPreferences.getPreferences(context, this.preferenceName)
      this.profileLabelValue = String(await preferences.get(KEY_PROFILE_LABEL, ''))
      this.answerVolumePercentValue =
        Number(await preferences.get(KEY_ANSWER_VOLUME_PERCENT, ANSWER_VOLUME_UNSET))
      this.loaded = true
      this.ports.logger.info(`override restored label=${this.profileLabelValue || 'none'}, ` +
        `answerVolumePercent=${this.answerVolumePercentValue}`)
    } catch (error) {
      this.ports.logger.error(`override restore failed: ${JSON.stringify(error)}`)
    }
  }

  profileLabel(): string {
    return this.profileLabelValue
  }

  answerVolumePercent(): number {
    return this.answerVolumePercentValue
  }

  async setProfileLabel(label: string): Promise<void> {
    await this.write(KEY_PROFILE_LABEL, label)
    this.profileLabelValue = label
  }

  async setAnswerVolumePercent(percent: number): Promise<void> {
    await this.write(KEY_ANSWER_VOLUME_PERCENT, percent)
    this.answerVolumePercentValue = percent
  }

  async clear(): Promise<void> {
    await this.setProfileLabel('')
    await this.setAnswerVolumePercent(ANSWER_VOLUME_UNSET)
  }

  private async write(key: string, value: string | number): Promise<void> {
    const context = this.ports.context ? this.ports.context() : undefined
    if (!context) {
      this.ports.logger.warn(`override write skipped key=${key}, reason=noContext`)
      return
    }
    try {
      const preferences = await dataPreferences.getPreferences(context, this.preferenceName)
      await preferences.put(key, value)
      await preferences.flush()
      this.ports.logger.info(`override saved key=${key}, value=${value}`)
    } catch (error) {
      this.ports.logger.error(`override save failed key=${key}: ${JSON.stringify(error)}`)
    }
  }
}
