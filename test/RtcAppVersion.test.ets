import { describe, it, expect } from '@ohos/hypium'
import { RtcAppVersion } from '../src/main/ets/core/RtcAppVersion'

export default function rtcAppVersionTest() {
  describe('RtcAppVersion', () => {
    it('builds the version string the admin console shows as 音视频版本', 0, () => {
      expect(RtcAppVersion.build('1.0.0', '20261019153813'))
        .assertEqual('v1.0.0_hmos_20261019153813')
    })

    it('keeps a usable string when the build script did not stamp a build time', 0, () => {
      expect(RtcAppVersion.build('1.0.0', '')).assertEqual('v1.0.0_hmos')
      expect(RtcAppVersion.build('', '20261019153813')).assertEqual('v_unknown_hmos_20261019153813')
    })
  })
}
