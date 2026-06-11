export const RTC_ADMIN_ENTRY_COUNTDOWN_VISIBLE_KEY = 'rtcAdminEntryCountdownVisible'
export const RTC_ADMIN_ENTRY_COUNTDOWN_TEXT_KEY = 'rtcAdminEntryCountdownText'
export const RTC_ADMIN_ENTRY_COUNTDOWN_UPDATED_AT_KEY = 'rtcAdminEntryCountdownUpdatedAt'

AppStorage.setOrCreate<boolean>(RTC_ADMIN_ENTRY_COUNTDOWN_VISIBLE_KEY, false)
AppStorage.setOrCreate<string>(RTC_ADMIN_ENTRY_COUNTDOWN_TEXT_KEY, '')
AppStorage.setOrCreate<number>(RTC_ADMIN_ENTRY_COUNTDOWN_UPDATED_AT_KEY, 0)

export class RtcAdminEntryCountdownNotifier {
  private static timer: number = -1
  private static startedAt: number = 0
  private static durationMs: number = 0
  private static label: string = '进入管理员设置界面'

  static start(durationMs: number, label: string = '进入管理员设置界面'): void {
    RtcAdminEntryCountdownNotifier.cancel()
    RtcAdminEntryCountdownNotifier.durationMs = Math.max(durationMs, 1000)
    RtcAdminEntryCountdownNotifier.startedAt = Date.now()
    RtcAdminEntryCountdownNotifier.label = label
    AppStorage.setOrCreate<boolean>(RTC_ADMIN_ENTRY_COUNTDOWN_VISIBLE_KEY, true)
    RtcAdminEntryCountdownNotifier.updateText()
    RtcAdminEntryCountdownNotifier.timer = setInterval(() => {
      RtcAdminEntryCountdownNotifier.updateText()
    }, 250)
  }

  static complete(): void {
    RtcAdminEntryCountdownNotifier.cancel()
  }

  static cancel(): void {
    if (RtcAdminEntryCountdownNotifier.timer > 0) {
      clearInterval(RtcAdminEntryCountdownNotifier.timer)
      RtcAdminEntryCountdownNotifier.timer = -1
    }
    AppStorage.setOrCreate<boolean>(RTC_ADMIN_ENTRY_COUNTDOWN_VISIBLE_KEY, false)
    AppStorage.setOrCreate<string>(RTC_ADMIN_ENTRY_COUNTDOWN_TEXT_KEY, '')
    AppStorage.setOrCreate<number>(RTC_ADMIN_ENTRY_COUNTDOWN_UPDATED_AT_KEY, Date.now())
  }

  private static updateText(): void {
    const elapsed = Date.now() - RtcAdminEntryCountdownNotifier.startedAt
    const remainingMs = Math.max(RtcAdminEntryCountdownNotifier.durationMs - elapsed, 0)
    const remainingSeconds = Math.max(Math.ceil(remainingMs / 1000), 1)
    AppStorage.setOrCreate<string>(
      RTC_ADMIN_ENTRY_COUNTDOWN_TEXT_KEY,
      `${remainingSeconds}秒后${RtcAdminEntryCountdownNotifier.label}`
    )
    AppStorage.setOrCreate<number>(RTC_ADMIN_ENTRY_COUNTDOWN_UPDATED_AT_KEY, Date.now())
  }
}
