import { window } from '@kit.ArkUI'

export const RTC_SYSTEM_BAR_PREFERENCE_NAME = 'nurseHost'
export const RTC_NAVIGATION_BAR_VISIBLE_KEY = 'host_navigation_bar_visible'
export const RTC_STATUS_BAR_HEIGHT_KEY = 'statusBarHeight'
export const RTC_NAVIGATION_BAR_HEIGHT_KEY = 'navigationBarHeight'

export interface RtcSystemBarOptions {
  preferenceName?: string
  navigationVisibleKey?: string
  defaultNavigationVisible?: boolean
}

export interface RtcSystemBarApplyOptions extends RtcSystemBarOptions {
  updateAvoidAreaStorage?: boolean
}

export class RtcSystemBarController {
  private static navigationBarVisible: boolean = false

  static getPreferenceName(options?: RtcSystemBarOptions): string {
    return options?.preferenceName || RTC_SYSTEM_BAR_PREFERENCE_NAME
  }

  static getNavigationVisibleKey(options?: RtcSystemBarOptions): string {
    return options?.navigationVisibleKey || RTC_NAVIGATION_BAR_VISIBLE_KEY
  }

  static async setNavigationBarVisible(visible: boolean, _options?: RtcSystemBarOptions): Promise<void> {
    RtcSystemBarController.navigationBarVisible = visible
  }

  static async isNavigationBarVisible(_options?: RtcSystemBarOptions): Promise<boolean> {
    return RtcSystemBarController.navigationBarVisible
  }

  static async applyNavigationBarPreference(
    targetWindow: window.Window,
    options?: RtcSystemBarApplyOptions
  ): Promise<boolean> {
    const visible = await RtcSystemBarController.isNavigationBarVisible(options)
    await RtcSystemBarController.applyNavigationBarVisibility(targetWindow, visible, options)
    return visible
  }

  static async applyNavigationBarVisibility(
    targetWindow: window.Window,
    visible: boolean,
    options?: RtcSystemBarApplyOptions
  ): Promise<void> {
    await targetWindow.setWindowLayoutFullScreen(!visible)
    await targetWindow.setWindowSystemBarEnable(visible ? ['navigation'] : [])
    try {
      await targetWindow.setSpecificSystemBarEnabled('navigation', visible)
    } catch (_error) {
      // Some API levels/devices do not support this specific toggle; setWindowSystemBarEnable above is still applied.
    }
    if (options?.updateAvoidAreaStorage !== false) {
      RtcSystemBarController.updateAvoidAreaStorage(targetWindow, visible)
    }
  }

  static updateAvoidAreaStorage(targetWindow: window.Window, navigationVisible?: boolean): void {
    const systemArea = targetWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
    const navigationArea = targetWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
    const statusBarHeight = px2vp(systemArea.topRect.height)
    const navigationBarHeight = navigationVisible === false ? 0 : px2vp(navigationArea.bottomRect.height)
    AppStorage.setOrCreate(RTC_STATUS_BAR_HEIGHT_KEY, statusBarHeight)
    AppStorage.setOrCreate(RTC_NAVIGATION_BAR_HEIGHT_KEY, navigationBarHeight)
    PersistentStorage.persistProp(RTC_STATUS_BAR_HEIGHT_KEY, statusBarHeight)
    PersistentStorage.persistProp(RTC_NAVIGATION_BAR_HEIGHT_KEY, navigationBarHeight)
  }
}
