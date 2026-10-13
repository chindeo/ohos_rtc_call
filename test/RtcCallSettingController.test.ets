import { describe, it, expect } from '@ohos/hypium'
import { RtcCallSettingController } from '../src/main/ets/callsetting/RtcCallSettingController'
import {
  RtcCallSettingFetcher,
  RtcCallSettingLogger,
  RtcCallSettingOverride,
  RtcCallSettingPorts
} from '../src/main/ets/callsetting/RtcCallSettingPorts'
import {
  RtcCallSettingBean,
  RtcCallSettingIdentity,
  RtcCallSettingSnapshot
} from '../src/main/ets/callsetting/RtcCallSettingTypes'

const BED: RtcCallSettingIdentity = {
  mac: 'A4580F4F20BB',
  packageName: 'com.chindeo.bed',
  deviceType: 'Cdo-I101'
}

function bean(kbps: number, enabled: boolean, mac: string = ''): RtcCallSettingBean {
  const result: RtcCallSettingBean = {
    mac: mac,
    deviceVolume: 15,
    streamVolume: 100,
    videoResolution: [
      { enabled: false, label: '240p', fps: 15, kbps: 280, width: 320, height: 240 },
      { enabled: enabled, label: '480P', fps: 15, kbps: kbps, width: 640, height: 480 }
    ]
  }
  return result
}

class SilentLogger implements RtcCallSettingLogger {
  info(_message: string): void {
  }

  warn(_message: string): void {
  }

  error(_message: string): void {
  }
}

class FakeOverride implements RtcCallSettingOverride {
  label: string = ''
  percent: number = -1

  restore(): Promise<void> {
    return Promise.resolve()
  }

  profileLabel(): string {
    return this.label
  }

  answerVolumePercent(): number {
    return this.percent
  }

  setProfileLabel(label: string): Promise<void> {
    this.label = label
    return Promise.resolve()
  }

  setAnswerVolumePercent(percent: number): Promise<void> {
    this.percent = percent
    return Promise.resolve()
  }

  clear(): Promise<void> {
    this.label = ''
    this.percent = -1
    return Promise.resolve()
  }
}

function controllerWith(
  remote: RtcCallSettingBean[] | undefined,
  bundled: RtcCallSettingBean[] | undefined,
  override: FakeOverride
): RtcCallSettingController {
  const fetcher: RtcCallSettingFetcher = {
    fetchRemote: async (): Promise<RtcCallSettingBean[] | undefined> => remote,
    readBundled: async (): Promise<RtcCallSettingBean[] | undefined> => bundled
  }
  const ports: RtcCallSettingPorts = {
    fetcher: fetcher,
    logger: new SilentLogger(),
    identity: (): RtcCallSettingIdentity => BED,
    override: override
  }
  return new RtcCallSettingController(ports)
}

export default function rtcCallSettingControllerTest() {
  describe('RtcCallSettingControllerTest', () => {
    it('usesRemoteBeansAndMarksMatchSource', 0, async () => {
      const snapshot: RtcCallSettingSnapshot =
        await controllerWith([bean(1500, true)], [bean(280, true)], new FakeOverride()).load('test')
      expect(snapshot.profile.maxBitrateKbps).assertEqual(1500)
      expect(snapshot.source).assertEqual('remote')
      expect(snapshot.matchedBy).assertEqual('match')
      expect(snapshot.audio.deviceVolume).assertEqual(15)
    })

    it('fallsBackToBundledWhenRemoteIsEmpty', 0, async () => {
      const snapshot: RtcCallSettingSnapshot =
        await controllerWith([], [bean(800, true)], new FakeOverride()).load('test')
      expect(snapshot.profile.maxBitrateKbps).assertEqual(800)
      expect(snapshot.source).assertEqual('rawfile')
    })

    it('takesFirstBeanWhenNothingMatches', 0, async () => {
      const mismatching = bean(800, true)
      mismatching.mac = 'FFFFFFFFFFFF'
      const snapshot: RtcCallSettingSnapshot =
        await controllerWith([mismatching], undefined, new FakeOverride()).load('test')
      expect(snapshot.matchedBy).assertEqual('firstBean')
      expect(snapshot.profile.maxBitrateKbps).assertEqual(800)
    })

    it('usesCodeFallbackWhenNoBeansAtAll', 0, async () => {
      const snapshot: RtcCallSettingSnapshot =
        await controllerWith(undefined, undefined, new FakeOverride()).load('test')
      expect(snapshot.matchedBy).assertEqual('codeFallback')
      expect(snapshot.profile.source).assertEqual('fallback')
      expect(snapshot.audio.deviceVolume).assertEqual(-1)
    })

    it('appliesLocalOverrideOverServerValues', 0, async () => {
      const override = new FakeOverride()
      override.label = '240p'
      override.percent = 80
      const snapshot: RtcCallSettingSnapshot =
        await controllerWith([bean(1500, true)], undefined, override).load('test')
      expect(snapshot.profile.label).assertEqual('240p')
      expect(snapshot.profile.source).assertEqual('override')
      expect(snapshot.matchedBy).assertEqual('localOverride')
      expect(snapshot.audio.deviceVolume).assertEqual(80)
      expect(snapshot.audio.source).assertEqual('override')
    })

    it('ignoresOverrideLabelAbsentFromServerOptions', 0, async () => {
      const override = new FakeOverride()
      override.label = '1080p'
      const snapshot: RtcCallSettingSnapshot =
        await controllerWith([bean(1500, true)], undefined, override).load('test')
      expect(snapshot.profile.label).assertEqual('480P')
      expect(snapshot.matchedBy).assertEqual('match')
    })

    it('emitsDiffOnlyWhenResolvedValuesChange', 0, async () => {
      let diffs = 0
      const controller = controllerWith([bean(1500, true)], undefined, new FakeOverride())
      controller.onChange(() => {
        diffs += 1
      })
      await controller.load('first')
      expect(diffs).assertEqual(1)
      await controller.load('repeat same server')
      expect(diffs).assertEqual(1)
      await controller.saveOverride('240p', -1, 'override saved')
      expect(diffs).assertEqual(2)
      expect(controller.snapshot()?.profile.label).assertEqual('240p')
    })
  })
}
