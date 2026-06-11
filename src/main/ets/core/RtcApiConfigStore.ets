import dataPreferences from '@ohos.data.preferences'

const DEFAULT_CONFIG_URL_KEY = 'config_json_url_key'
const DEFAULT_PREFERENCE_NAME = 'rtcCall'

export interface RtcApiConfigStoreOptions {
  key?: string
  preferenceName?: string
  defaultUrl?: string
}

export class RtcApiConfigStore {
  static getKey(options?: RtcApiConfigStoreOptions): string {
    return options?.key || DEFAULT_CONFIG_URL_KEY
  }

  static getPreferenceName(options?: RtcApiConfigStoreOptions): string {
    return options?.preferenceName || DEFAULT_PREFERENCE_NAME
  }

  static normalizeUrl(url?: string): string {
    return (url || '').trim()
  }

  static async getConfigUrl(options?: RtcApiConfigStoreOptions): Promise<string> {
    const key = RtcApiConfigStore.getKey(options)
    const appValue = RtcApiConfigStore.normalizeUrl(AppStorage.get<string>(key) || '')
    if (appValue.length > 0) {
      return appValue
    }

    const preferences = await dataPreferences.getPreferences(getContext(), RtcApiConfigStore.getPreferenceName(options))
    const storedValue = RtcApiConfigStore.normalizeUrl(String(await preferences.get(key, '')))
    if (storedValue.length > 0) {
      AppStorage.setOrCreate<string>(key, storedValue)
      return storedValue
    }
    return RtcApiConfigStore.normalizeUrl(options?.defaultUrl || '')
  }

  static async setConfigUrl(url: string, options?: RtcApiConfigStoreOptions): Promise<string> {
    const key = RtcApiConfigStore.getKey(options)
    const nextUrl = RtcApiConfigStore.normalizeUrl(url)
    AppStorage.setOrCreate<string>(key, nextUrl)

    const preferences = await dataPreferences.getPreferences(getContext(), RtcApiConfigStore.getPreferenceName(options))
    await preferences.put(key, nextUrl)
    await preferences.flush()
    return nextUrl
  }

  static async resolveConfigUrl(defaultUrl: string, options?: RtcApiConfigStoreOptions): Promise<string> {
    const storedUrl = await RtcApiConfigStore.getConfigUrl(options)
    return storedUrl.length > 0 ? storedUrl : RtcApiConfigStore.normalizeUrl(defaultUrl)
  }
}
