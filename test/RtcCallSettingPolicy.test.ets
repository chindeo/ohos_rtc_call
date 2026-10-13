import { describe, it, expect } from '@ohos/hypium'
import {
  CALL_SETTING_SOURCE_FALLBACK,
  RtcCallSettingBean,
  RtcCallSettingIdentity
} from '../src/main/ets/callsetting/RtcCallSettingTypes'
import { RtcCallSettingPolicy as Policy } from '../src/main/ets/callsetting/RtcCallSettingPolicy'

const BED: RtcCallSettingIdentity = {
  mac: 'A4580F4F20BB',
  packageName: 'com.chindeo.bed',
  deviceType: 'Cdo-I101'
}

function bean(mac: string, deviceType: string, packageName: string, kbps: number,
  enabled: boolean = true): RtcCallSettingBean {
  const result: RtcCallSettingBean = {
    mac: mac,
    deviceType: deviceType,
    packageName: packageName,
    videoResolution: [
      { enabled: false, label: '240p', fps: 15, kbps: 280, width: 320, height: 240 },
      { enabled: enabled, label: '480P', fps: 15, kbps: kbps, width: 640, height: 480 }
    ]
  }
  return result
}

export default function rtcCallSettingPolicyTest() {
  describe('RtcCallSettingPolicyTest', () => {
    it('prefersExactMacMatchAndStops', 0, () => {
      const beans: RtcCallSettingBean[] = [bean('*', '', '', 800), bean(BED.mac, BED.deviceType, '', 1500)]
      expect(Policy.resolveVideoProfile(beans, BED, 'remote')?.maxBitrateKbps).assertEqual(1500)
    })

    it('rejectsBeanWithDifferentMac', 0, () => {
      expect(Policy.matchPriority(bean('FFFFFFFFFFFF', '', '', 1500), BED)).assertEqual(0)
    })

    it('rejectsBeanWhoseDeviceTypeOrPackageNameMismatch', 0, () => {
      expect(Policy.matchPriority(bean('', 'OTHER', '', 1500), BED)).assertEqual(0)
      expect(Policy.matchPriority(bean('', '', 'com.other', 1500), BED)).assertEqual(0)
      expect(Policy.matchPriority(bean('', BED.deviceType, BED.packageName, 1500), BED)).assertEqual(4)
    })

    it('usesWildcardEntryWhenNothingElseMatches', 0, () => {
      const beans: RtcCallSettingBean[] = [bean('', '', '', 800)]
      expect(Policy.resolveVideoProfile(beans, BED, 'remote')?.maxBitrateKbps).assertEqual(800)
      expect(Policy.selectBestMatch([bean('FFFFFFFFFFFF', 'OTHER', 'x', 800)], BED)).assertUndefined()
    })

    it('fallsBackPerFieldOnInvalidValues', 0, () => {
      const broken: RtcCallSettingBean = {
        videoResolution: [{ enabled: true, label: 'bad', fps: 0, kbps: -1, width: 99999, height: undefined }]
      }
      const profile = Policy.resolveVideoProfile([broken], BED, 'remote')
      expect(profile?.width).assertEqual(Policy.FALLBACK_WIDTH)
      expect(profile?.height).assertEqual(Policy.FALLBACK_HEIGHT)
      expect(profile?.frameRate).assertEqual(Policy.FALLBACK_FPS)
      expect(profile?.maxBitrateKbps).assertEqual(Policy.FALLBACK_MAX_KBPS)
    })

    it('returnsUndefinedWithoutEnabledResolution', 0, () => {
      expect(Policy.resolveVideoProfile([bean('', '', '', 800, false)], BED, 'remote')).assertUndefined()
      expect(Policy.resolveVideoProfile([], BED, 'remote')).assertUndefined()
      expect(Policy.resolveVideoProfile(undefined, BED, 'remote')).assertUndefined()
    })

    it('treatsFallbackProfileAsNoServerConfiguration', 0, () => {
      expect(Policy.isServerProfile(Policy.fallbackProfile())).assertEqual(false)
      expect(Policy.isServerProfile(undefined)).assertEqual(false)
      expect(Policy.isServerProfile(Policy.resolveVideoProfile([bean('', '', '', 800)], BED, 'remote')))
        .assertEqual(true)
      expect(Policy.fallbackProfile().source).assertEqual(CALL_SETTING_SOURCE_FALLBACK)
    })

    it('normalizesMacOnlyWhenAsked', 0, () => {
      expect(Policy.normalizeMac('a4:58-0f 4f20bb')).assertEqual('A4580F4F20BB')
      expect(Policy.identityMac('a4:58-0f 4f20bb')).assertEqual('a4:58-0f 4f20bb')
      expect(Policy.identityMac('  A4580F4F20BB  ')).assertEqual('A4580F4F20BB')
    })

    it('clampsStartKbpsToAndroidRules', 0, () => {
      expect(Policy.resolveStartKbps(1500)).assertEqual(600)
      expect(Policy.resolveStartKbps(800)).assertEqual(320)
      expect(Policy.resolveStartKbps(280)).assertEqual(280)
      expect(Policy.resolveStartKbps(5000)).assertEqual(1800)
    })

    it('buildsOverrideProfileFromLabeledOption', 0, () => {
      const target = bean('', '', '', 800)
      const profile = Policy.profileFromResolution(Policy.findResolutionByLabel(target, '240p'), 'override')
      expect(profile?.label).assertEqual('240p')
      expect(profile?.width).assertEqual(320)
      expect(profile?.maxBitrateKbps).assertEqual(280)
      expect(profile?.source).assertEqual('override')
      expect(Policy.resolveVideoProfile([target], BED, 'remote')?.label).assertEqual('480P')
      expect(Policy.findResolutionByLabel(target, '1080p')).assertUndefined()
      expect(Policy.findResolutionByLabel(target, '')).assertUndefined()
      expect(Policy.profileFromResolution(undefined, 'override')).assertUndefined()
    })

    it('resolvesAndClampsServerVolumes', 0, () => {
      const withVolume: RtcCallSettingBean = bean('', '', '', 800)
      withVolume.deviceVolume = 50
      withVolume.streamVolume = 2500
      const audio = Policy.resolveAudioSetting([withVolume], BED, 'remote')
      expect(audio.deviceVolume).assertEqual(50)
      expect(audio.streamVolume).assertEqual(250)
      expect(audio.source).assertEqual('remote')

      const defaults = Policy.resolveAudioSetting(undefined, BED, 'remote')
      expect(defaults.deviceVolume).assertEqual(-1)
      expect(defaults.streamVolume).assertEqual(100)
      expect(defaults.source).assertEqual('default')
    })
  })
}
