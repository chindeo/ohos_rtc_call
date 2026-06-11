import {
  RTC_CALL_CONTROL_SOURCE_HANDSET,
  RTC_CALL_CONTROL_SOURCE_SCREEN
} from '../core/RtcCallControlCommand'
import { RtcDeviceCapabilityManager } from '../device/RtcDeviceCapabilityManager'
import { RtcAudioRoute } from './RtcAudioRoute'
import {
  RtcCallAnswerAudioPolicy,
  RtcCallAnswerAudioRoute,
  RTC_WEBRTC_SCREEN_ANSWER_VOLUME_PERCENT
} from './RtcCallAnswerAudioPolicy'
import { RtcCallVolumeMonitor, RtcCallVolumeSnapshot } from './RtcCallVolumeMonitor'

export const RTC_DEVICE_ROLE_BEDSIDE = 'bedside'
export const RTC_DEVICE_ROLE_NURSE_HOST = 'nurseHost'
export const RTC_DEVICE_ROLE_DOOR_HOST = 'doorHost'

export interface RtcCallAudioPolicyDriver {
  readVoiceCallVolumeSnapshot(): RtcCallVolumeSnapshot
  setVoiceCallVolume(volume: number): Promise<void>
  setSpeaker(enabled: boolean): Promise<void>
  setHandsetMode?(enabled: boolean, reason: string): void
  setMuted?(muted: boolean): void
}

export interface RtcCallAudioPolicyOptions {
  deviceRole?: string
  vendor?: string
  driver?: RtcCallAudioPolicyDriver
  screenAnswerVolumePercent?: number
  handsetAnswerVolumePercent?: number
  restoreVolumeOnEnd?: boolean
}

export class RtcCallAudioPolicyState {
  deviceRole: string = RTC_DEVICE_ROLE_BEDSIDE
  source: string = RTC_CALL_CONTROL_SOURCE_SCREEN
  speakerEnabled: boolean = true
  muted: boolean = false
  handsetMode: boolean = false
  currentVolumePercent: number = RTC_WEBRTC_SCREEN_ANSWER_VOLUME_PERCENT
  hasOriginalVolume: boolean = false
  originalVolumeLevel: number = 0
  originalVolumePercent: number = 0
}

class RtcDefaultCallAudioPolicyDriver implements RtcCallAudioPolicyDriver {
  private route: RtcAudioRoute = new RtcAudioRoute()
  private vendor?: string

  constructor(vendor?: string) {
    this.vendor = vendor
  }

  readVoiceCallVolumeSnapshot(): RtcCallVolumeSnapshot {
    return RtcCallVolumeMonitor.readVoiceCallVolumeSnapshot()
  }

  async setVoiceCallVolume(volume: number): Promise<void> {
    await RtcCallVolumeMonitor.setVoiceCallVolume(volume)
  }

  async setSpeaker(enabled: boolean): Promise<void> {
    await this.route.setSpeaker(enabled)
  }

  setHandsetMode(enabled: boolean, reason: string): void {
    RtcDeviceCapabilityManager.setHandsetMode({
      mode: enabled ? 1 : 0,
      reason
    }, this.vendor)
  }
}

export class RtcCallAudioPolicyController {
  private options: RtcCallAudioPolicyOptions
  private driver: RtcCallAudioPolicyDriver
  private state: RtcCallAudioPolicyState = new RtcCallAudioPolicyState()

  constructor(options?: RtcCallAudioPolicyOptions) {
    this.options = options || {}
    this.driver = this.options.driver || new RtcDefaultCallAudioPolicyDriver(this.options.vendor)
    this.state.deviceRole = this.options.deviceRole || RTC_DEVICE_ROLE_BEDSIDE
  }

  configure(options: RtcCallAudioPolicyOptions): void {
    this.options = options
    this.driver = options.driver || new RtcDefaultCallAudioPolicyDriver(options.vendor)
    this.state.deviceRole = options.deviceRole || RTC_DEVICE_ROLE_BEDSIDE
  }

  captureOriginalVolume(): RtcCallVolumeSnapshot {
    const snapshot = this.driver.readVoiceCallVolumeSnapshot()
    this.state.hasOriginalVolume = true
    this.state.originalVolumeLevel = snapshot.currentLevel
    this.state.originalVolumePercent = snapshot.percent
    return snapshot
  }

  async applyAnswerPolicy(source: string = RTC_CALL_CONTROL_SOURCE_SCREEN, reason: string = 'answer'): Promise<RtcCallAnswerAudioRoute> {
    const snapshot = this.captureOriginalVolume()
    const route = RtcCallAnswerAudioPolicy.resolve(source)
    const volumePercent = this.resolveAnswerVolumePercent(route)
    const volumeLevel = RtcCallVolumeMonitor.getVolumeLevelByPercent(volumePercent, snapshot.minLevel, snapshot.maxLevel)
    await this.driver.setSpeaker(route.speakerEnabled)
    await this.driver.setVoiceCallVolume(volumeLevel)
    this.applyHandsetMode(route.source === RTC_CALL_CONTROL_SOURCE_HANDSET, reason)
    this.state.source = route.source
    this.state.speakerEnabled = route.speakerEnabled
    this.state.handsetMode = route.source === RTC_CALL_CONTROL_SOURCE_HANDSET
    this.state.currentVolumePercent = volumePercent
    route.volumePercent = volumePercent
    return route
  }

  async applyHandsetPickedUp(reason: string = 'handset pickup'): Promise<RtcCallAnswerAudioRoute> {
    return this.applyAnswerPolicy(RTC_CALL_CONTROL_SOURCE_HANDSET, reason)
  }

  async applyScreenAnswer(reason: string = 'screen answer'): Promise<RtcCallAnswerAudioRoute> {
    return this.applyAnswerPolicy(RTC_CALL_CONTROL_SOURCE_SCREEN, reason)
  }

  async applyHandsetPutDown(reason: string = 'handset put down'): Promise<void> {
    this.applyHandsetMode(false, reason)
    this.state.handsetMode = false
    if (this.state.source === RTC_CALL_CONTROL_SOURCE_HANDSET) {
      await this.driver.setSpeaker(true)
      this.state.speakerEnabled = true
      this.state.source = RTC_CALL_CONTROL_SOURCE_SCREEN
    }
  }

  setMuted(muted: boolean): void {
    this.state.muted = muted
    this.driver.setMuted?.(muted)
  }

  async restoreAfterCall(reason: string = 'call ended'): Promise<void> {
    if (this.options.restoreVolumeOnEnd !== false && this.state.hasOriginalVolume) {
      await this.driver.setVoiceCallVolume(this.state.originalVolumeLevel)
    }
    await this.driver.setSpeaker(false)
    this.applyHandsetMode(false, reason)
    this.state.speakerEnabled = false
    this.state.handsetMode = false
    this.state.source = RTC_CALL_CONTROL_SOURCE_SCREEN
  }

  getState(): RtcCallAudioPolicyState {
    const copy = new RtcCallAudioPolicyState()
    copy.deviceRole = this.state.deviceRole
    copy.source = this.state.source
    copy.speakerEnabled = this.state.speakerEnabled
    copy.muted = this.state.muted
    copy.handsetMode = this.state.handsetMode
    copy.currentVolumePercent = this.state.currentVolumePercent
    copy.hasOriginalVolume = this.state.hasOriginalVolume
    copy.originalVolumeLevel = this.state.originalVolumeLevel
    copy.originalVolumePercent = this.state.originalVolumePercent
    return copy
  }

  private resolveAnswerVolumePercent(route: RtcCallAnswerAudioRoute): number {
    if (route.source === RTC_CALL_CONTROL_SOURCE_HANDSET && this.options.handsetAnswerVolumePercent !== undefined) {
      return this.options.handsetAnswerVolumePercent
    }
    if (route.source === RTC_CALL_CONTROL_SOURCE_SCREEN && this.options.screenAnswerVolumePercent !== undefined) {
      return this.options.screenAnswerVolumePercent
    }
    return route.volumePercent
  }

  private applyHandsetMode(enabled: boolean, reason: string): void {
    this.driver.setHandsetMode?.(enabled, reason)
  }
}
