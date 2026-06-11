export enum RtcCallStatusLevel {
  INFO = 'info',
  SUCCESS = 'success',
  WARNING = 'warning',
  ERROR = 'error'
}

export const RTC_CALL_STATUS_MESSAGE_KEY = 'rtcCallStatusMessage'
export const RTC_CALL_STATUS_LEVEL_KEY = 'rtcCallStatusLevel'
export const RTC_CALL_STATUS_UPDATED_AT_KEY = 'rtcCallStatusUpdatedAt'

AppStorage.setOrCreate<string>(RTC_CALL_STATUS_MESSAGE_KEY, '')
AppStorage.setOrCreate<string>(RTC_CALL_STATUS_LEVEL_KEY, RtcCallStatusLevel.INFO)
AppStorage.setOrCreate<number>(RTC_CALL_STATUS_UPDATED_AT_KEY, 0)

export class RtcCallStatusNotifier {
  static show(message: string, level: RtcCallStatusLevel = RtcCallStatusLevel.INFO): void {
    const text = (message || '').trim()
    if (!text) {
      return
    }
    AppStorage.setOrCreate<string>(RTC_CALL_STATUS_MESSAGE_KEY, text)
    AppStorage.setOrCreate<string>(RTC_CALL_STATUS_LEVEL_KEY, level)
    AppStorage.setOrCreate<number>(RTC_CALL_STATUS_UPDATED_AT_KEY, Date.now())
  }

  static info(message: string): void {
    RtcCallStatusNotifier.show(message, RtcCallStatusLevel.INFO)
  }

  static success(message: string): void {
    RtcCallStatusNotifier.show(message, RtcCallStatusLevel.SUCCESS)
  }

  static warning(message: string): void {
    RtcCallStatusNotifier.show(message, RtcCallStatusLevel.WARNING)
  }

  static error(message: string): void {
    RtcCallStatusNotifier.show(message, RtcCallStatusLevel.ERROR)
  }

  static clear(): void {
    AppStorage.setOrCreate<string>(RTC_CALL_STATUS_MESSAGE_KEY, '')
    AppStorage.setOrCreate<number>(RTC_CALL_STATUS_UPDATED_AT_KEY, Date.now())
  }
}
