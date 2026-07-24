import { describe, it, expect } from '@ohos/hypium'
import {
  createSuccessResult,
  RtcDeviceCapabilityAdapter,
  RtcDeviceCapabilityResult,
  RtcDeviceKeepAliveReleaseOptions
} from '../src/main/ets/device/RtcDeviceCapabilityAdapter'
import { RtcDeviceCapabilityManager } from '../src/main/ets/device/RtcDeviceCapabilityManager'
import { RtcDeviceVendor } from '../src/main/ets/device/RtcDeviceVendor'

class KeepAliveReleaseAdapter implements RtcDeviceCapabilityAdapter {
  readonly vendor: string = RtcDeviceVendor.DNAKE
  releasedBundleName: string = ''

  isAvailable(): boolean {
    return true
  }

  async releaseKeepAlive(options: RtcDeviceKeepAliveReleaseOptions): Promise<RtcDeviceCapabilityResult<boolean>> {
    this.releasedBundleName = options.bundleName
    return createSuccessResult<boolean>(true, 'released')
  }
}

export default function rtcDeviceCapabilityManagerTest() {
  describe('RtcDeviceCapabilityManager', () => {
    it('delegates explicit keep alive release to the selected adapter', 0, async () => {
      const adapter = new KeepAliveReleaseAdapter()
      RtcDeviceCapabilityManager.clearAdapters()
      RtcDeviceCapabilityManager.registerAdapter(adapter)

      const result = await RtcDeviceCapabilityManager.releaseKeepAlive({
        bundleName: 'com.example.bed',
        reason: 'prepare uninstall'
      }, RtcDeviceVendor.DNAKE)

      expect(result.success).assertEqual(true)
      expect(adapter.releasedBundleName).assertEqual('com.example.bed')
      RtcDeviceCapabilityManager.clearAdapters()
    })

    it('reports unsupported instead of removing a dog through an unknown adapter', 0, async () => {
      RtcDeviceCapabilityManager.clearAdapters()
      const result = await RtcDeviceCapabilityManager.releaseKeepAlive({
        bundleName: 'com.example.bed'
      }, RtcDeviceVendor.UNKNOWN)

      expect(result.supported).assertEqual(false)
      expect(result.success).assertEqual(false)
    })
  })
}
