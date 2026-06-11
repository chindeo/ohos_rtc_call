import {
  RTC_CALL_CONTROL_SOURCE_HANDSET,
  RTC_CALL_CONTROL_SOURCE_SCREEN
} from '../core/RtcCallControlCommand'

export const RTC_WEBRTC_HANDSET_ANSWER_VOLUME_PERCENT = 40
export const RTC_WEBRTC_SCREEN_ANSWER_VOLUME_PERCENT = 90

export class RtcCallAnswerAudioRoute {
  source: string = RTC_CALL_CONTROL_SOURCE_SCREEN
  speakerEnabled: boolean = true
  volumePercent: number = RTC_WEBRTC_SCREEN_ANSWER_VOLUME_PERCENT
}

export class RtcCallAnswerAudioPolicy {
  static normalizeSource(source: string): string {
    return source === RTC_CALL_CONTROL_SOURCE_HANDSET ?
      RTC_CALL_CONTROL_SOURCE_HANDSET : RTC_CALL_CONTROL_SOURCE_SCREEN
  }

  static resolve(source: string): RtcCallAnswerAudioRoute {
    const normalizedSource = RtcCallAnswerAudioPolicy.normalizeSource(source)
    const route = new RtcCallAnswerAudioRoute()
    route.source = normalizedSource
    route.speakerEnabled = normalizedSource === RTC_CALL_CONTROL_SOURCE_SCREEN
    route.volumePercent = route.speakerEnabled ?
      RTC_WEBRTC_SCREEN_ANSWER_VOLUME_PERCENT : RTC_WEBRTC_HANDSET_ANSWER_VOLUME_PERCENT
    return route
  }
}
