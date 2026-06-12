import { describe, it, expect } from '@ohos/hypium'
import {
  RtcStartupDataCache,
  RtcStartupDataCacheStore
} from '../src/main/ets/core/RtcStartupDataCache'

class MemoryCacheStore implements RtcStartupDataCacheStore {
  values: Record<string, string> = {}

  async get(key: string): Promise<string> {
    return this.values[key] || ''
  }

  async put(key: string, value: string): Promise<void> {
    this.values[key] = value
  }

  async remove(key: string): Promise<void> {
    delete this.values[key]
  }
}

class StartupConfig {
  bedId: number = 0
  name: string = ''
}

function createConfig(bedId: number, name: string): StartupConfig {
  const config = new StartupConfig()
  config.bedId = bedId
  config.name = name
  return config
}

function isConfigUsable(config: StartupConfig): boolean {
  return !!config && config.bedId > 0
}

export default function rtcStartupDataCacheTest() {
  describe('RtcStartupDataCache', () => {
    it('saves network data and loads it when loader fails', 0, async () => {
      const store = new MemoryCacheStore()

      const first = await RtcStartupDataCache.load<StartupConfig>({
        key: 'bedConfig',
        store,
        loader: async () => createConfig(1491, 'bed'),
        isUsable: isConfigUsable
      })

      expect(first.source).assertEqual('network')
      expect(first.value?.bedId).assertEqual(1491)

      const second = await RtcStartupDataCache.load<StartupConfig>({
        key: 'bedConfig',
        store,
        loader: async () => {
          throw new Error('api stopped')
        },
        isUsable: isConfigUsable
      })

      expect(second.source).assertEqual('cache')
      expect(second.usedCache).assertEqual(true)
      expect(second.value?.bedId).assertEqual(1491)
    })

    it('falls back to cache when network data is unusable', 0, async () => {
      const store = new MemoryCacheStore()
      await RtcStartupDataCache.save<StartupConfig>('bedConfig', createConfig(1491, 'bed'), { store })

      const result = await RtcStartupDataCache.load<StartupConfig>({
        key: 'bedConfig',
        store,
        loader: async () => createConfig(0, ''),
        isUsable: isConfigUsable
      })

      expect(result.source).assertEqual('cache')
      expect(result.value?.bedId).assertEqual(1491)
    })

    it('uses fallback value when network and cache are unavailable', 0, async () => {
      const store = new MemoryCacheStore()

      const result = await RtcStartupDataCache.load<StartupConfig>({
        key: 'bedConfig',
        store,
        loader: async () => {
          throw new Error('api stopped')
        },
        fallbackValue: createConfig(1, 'fallback'),
        isUsable: isConfigUsable
      })

      expect(result.source).assertEqual('fallback')
      expect(result.value?.name).assertEqual('fallback')
    })
  })
}
