import dataPreferences from '@ohos.data.preferences'

const DEFAULT_STARTUP_CACHE_PREFERENCE_NAME = 'rtcStartupDataCache'
const DEFAULT_STARTUP_CACHE_VERSION = 1

export type RtcStartupDataCacheSource = 'network' | 'cache' | 'fallback'

export interface RtcStartupDataCacheStore {
  get(key: string): Promise<string>
  put(key: string, value: string): Promise<void>
  remove(key: string): Promise<void>
}

export interface RtcStartupDataCacheLogger {
  info?(message: string): void
  warn?(message: string): void
}

export interface RtcStartupDataCacheOptions<T> {
  key: string
  preferenceName?: string
  store?: RtcStartupDataCacheStore
  loader: () => Promise<T>
  fallbackValue?: T
  isUsable?: (value: T) => boolean
  shouldCache?: (value: T) => boolean
  serialize?: (value: T) => string
  deserialize?: (value: string) => T
  logger?: RtcStartupDataCacheLogger
}

export interface RtcStartupDataCacheSaveOptions<T> {
  preferenceName?: string
  store?: RtcStartupDataCacheStore
  serialize?: (value: T) => string
}

export interface RtcStartupDataCacheGetOptions<T> {
  preferenceName?: string
  store?: RtcStartupDataCacheStore
  deserialize?: (value: string) => T
}

export interface RtcStartupDataCacheClearOptions {
  preferenceName?: string
  store?: RtcStartupDataCacheStore
}

export class RtcStartupDataCacheResult<T> {
  value?: T
  source: RtcStartupDataCacheSource = 'network'
  usedCache: boolean = false
  hasCache: boolean = false
  updatedAt: number = 0
  errorMessage: string = ''
}

class RtcStartupDataCacheEnvelope {
  version: number = DEFAULT_STARTUP_CACHE_VERSION
  updatedAt: number = 0
  value: string = ''
}

class RtcPreferencesStartupDataCacheStore implements RtcStartupDataCacheStore {
  private preferenceName: string

  constructor(preferenceName?: string) {
    this.preferenceName = preferenceName || DEFAULT_STARTUP_CACHE_PREFERENCE_NAME
  }

  async get(key: string): Promise<string> {
    const preferences = await dataPreferences.getPreferences(getContext(), this.preferenceName)
    return String(await preferences.get(key, ''))
  }

  async put(key: string, value: string): Promise<void> {
    const preferences = await dataPreferences.getPreferences(getContext(), this.preferenceName)
    await preferences.put(key, value)
    await preferences.flush()
  }

  async remove(key: string): Promise<void> {
    const preferences = await dataPreferences.getPreferences(getContext(), this.preferenceName)
    await preferences.delete(key)
    await preferences.flush()
  }
}

export class RtcStartupDataCache {
  static async load<T>(options: RtcStartupDataCacheOptions<T>): Promise<RtcStartupDataCacheResult<T>> {
    const store = RtcStartupDataCache.getStore(options)
    try {
      const value = await options.loader()
      if (RtcStartupDataCache.isUsable(options, value)) {
        if (RtcStartupDataCache.shouldCache(options, value)) {
          await RtcStartupDataCache.saveValue(options, store, value)
        }
        return RtcStartupDataCache.createValueResult(value, 'network')
      }

      const cached = await RtcStartupDataCache.readCachedValue(options, store)
      if (cached.value !== undefined && RtcStartupDataCache.isUsable(options, cached.value)) {
        cached.source = 'cache'
        cached.usedCache = true
        cached.errorMessage = 'network value is unusable'
        options.logger?.warn?.(`RtcStartupDataCache fallback to cache key=${options.key}: network value is unusable`)
        return cached
      }

      return RtcStartupDataCache.createValueResult(value, 'network')
    } catch (error) {
      const cached = await RtcStartupDataCache.readCachedValue(options, store)
      if (cached.value !== undefined && RtcStartupDataCache.isUsable(options, cached.value)) {
        cached.source = 'cache'
        cached.usedCache = true
        cached.errorMessage = RtcStartupDataCache.getErrorMessage(error)
        options.logger?.warn?.(`RtcStartupDataCache fallback to cache key=${options.key}: ${cached.errorMessage}`)
        return cached
      }

      if (options.fallbackValue !== undefined && RtcStartupDataCache.isUsable(options, options.fallbackValue)) {
        const result = RtcStartupDataCache.createValueResult(options.fallbackValue, 'fallback')
        result.errorMessage = RtcStartupDataCache.getErrorMessage(error)
        options.logger?.warn?.(`RtcStartupDataCache fallback to default key=${options.key}: ${result.errorMessage}`)
        return result
      }

      throw new Error(RtcStartupDataCache.getErrorMessage(error))
    }
  }

  static async save<T>(key: string, value: T, options?: RtcStartupDataCacheSaveOptions<T>): Promise<void> {
    const cacheOptions: RtcStartupDataCacheOptions<T> = {
      key,
      preferenceName: options?.preferenceName,
      store: options?.store,
      loader: async () => value,
      serialize: options?.serialize
    }
    await RtcStartupDataCache.saveValue(cacheOptions, RtcStartupDataCache.getStore(cacheOptions), value)
  }

  static async get<T>(key: string, options?: RtcStartupDataCacheGetOptions<T>): Promise<RtcStartupDataCacheResult<T>> {
    const cacheOptions: RtcStartupDataCacheOptions<T> = {
      key,
      preferenceName: options?.preferenceName,
      store: options?.store,
      loader: async () => {
        throw new Error('loader is not available')
      },
      deserialize: options?.deserialize
    }
    return RtcStartupDataCache.readCachedValue(cacheOptions, RtcStartupDataCache.getStore(cacheOptions))
  }

  static async clear(key: string, options?: RtcStartupDataCacheClearOptions): Promise<void> {
    const store = options?.store || new RtcPreferencesStartupDataCacheStore(options?.preferenceName)
    await store.remove(key)
  }

  private static getStore<T>(options: RtcStartupDataCacheOptions<T>): RtcStartupDataCacheStore {
    return options.store || new RtcPreferencesStartupDataCacheStore(options.preferenceName)
  }

  private static isUsable<T>(options: RtcStartupDataCacheOptions<T>, value: T): boolean {
    if (options.isUsable) {
      return options.isUsable(value)
    }
    return value !== undefined && value !== null
  }

  private static shouldCache<T>(options: RtcStartupDataCacheOptions<T>, value: T): boolean {
    if (options.shouldCache) {
      return options.shouldCache(value)
    }
    return RtcStartupDataCache.isUsable(options, value)
  }

  private static serialize<T>(options: RtcStartupDataCacheOptions<T>, value: T): string {
    if (options.serialize) {
      return options.serialize(value)
    }
    return JSON.stringify(value)
  }

  private static deserialize<T>(options: RtcStartupDataCacheOptions<T>, value: string): T {
    if (options.deserialize) {
      return options.deserialize(value)
    }
    return JSON.parse(value) as T
  }

  private static async saveValue<T>(
    options: RtcStartupDataCacheOptions<T>,
    store: RtcStartupDataCacheStore,
    value: T
  ): Promise<void> {
    const envelope = new RtcStartupDataCacheEnvelope()
    envelope.updatedAt = Date.now()
    envelope.value = RtcStartupDataCache.serialize(options, value)
    await store.put(options.key, JSON.stringify(envelope))
    options.logger?.info?.(`RtcStartupDataCache saved key=${options.key}`)
  }

  private static async readCachedValue<T>(
    options: RtcStartupDataCacheOptions<T>,
    store: RtcStartupDataCacheStore
  ): Promise<RtcStartupDataCacheResult<T>> {
    const result = new RtcStartupDataCacheResult<T>()
    const text = await store.get(options.key)
    if (!text) {
      return result
    }

    const envelope = JSON.parse(text) as RtcStartupDataCacheEnvelope
    if (!envelope || !envelope.value) {
      return result
    }

    result.value = RtcStartupDataCache.deserialize(options, envelope.value)
    result.source = 'cache'
    result.usedCache = true
    result.hasCache = true
    result.updatedAt = envelope.updatedAt || 0
    return result
  }

  private static createValueResult<T>(value: T, source: RtcStartupDataCacheSource): RtcStartupDataCacheResult<T> {
    const result = new RtcStartupDataCacheResult<T>()
    result.value = value
    result.source = source
    result.usedCache = source === 'cache'
    result.hasCache = source === 'cache'
    return result
  }

  private static getErrorMessage(error: Object): string {
    if (!error) {
      return ''
    }
    return JSON.stringify(error)
  }
}
