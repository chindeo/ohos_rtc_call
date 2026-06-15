import { describe, it, expect } from '@ohos/hypium'
import {
  RTC_CALL_CONTROL_SOURCE_HANDSET,
  RTC_CALL_CONTROL_SOURCE_SCREEN
} from '../src/main/ets/core/RtcCallControlCommand'
import {
  RtcCallAudioPolicyController,
  RtcCallAudioPolicyDriver
} from '../src/main/ets/audio/RtcCallAudioPolicyController'
import { RtcCallVolumeSnapshot } from '../src/main/ets/audio/RtcCallVolumeMonitor'

class MemoryVolumeSnapshot implements RtcCallVolumeSnapshot {
  minLevel: number = 0
  maxLevel: number = 10
  currentLevel: number = 3
  percent: number = 30
}

class MemoryAudioPolicyDriver implements RtcCallAudioPolicyDriver {
  snapshot: RtcCallVolumeSnapshot = new MemoryVolumeSnapshot()
  volume: number = -1
  speakerEnabled: boolean = false
  handsetMode: boolean = false
  muted: boolean = false

  readVoiceCallVolumeSnapshot(): RtcCallVolumeSnapshot {
    return this.snapshot
  }

  async setVoiceCallVolume(volume: number): Promise<void> {
    this.volume = volume
  }

  async setSpeaker(enabled: boolean): Promise<void> {
    this.speakerEnabled = enabled
  }

  setHandsetMode(enabled: boolean, _reason: string): void {
    this.handsetMode = enabled
  }

  setMuted(muted: boolean): void {
    this.muted = muted
  }
}

export default function rtcCallAudioPolicyControllerTest() {
  describe('RtcCallAudioPolicyController', () => {
    it('applies screen answer route and restores original volume', 0, async () => {
      const driver = new MemoryAudioPolicyDriver()
      const controller = new RtcCallAudioPolicyController({ driver })

      const route = await controller.applyAnswerPolicy(RTC_CALL_CONTROL_SOURCE_SCREEN)
      expect(route.speakerEnabled).assertEqual(true)
      expect(route.volumePercent).assertEqual(90)
      expect(driver.speakerEnabled).assertEqual(true)
      expect(driver.volume).assertEqual(9)
      controller.setMuted(true)
      expect(driver.muted).assertEqual(true)

      await controller.restoreAfterCall()
      expect(driver.speakerEnabled).assertEqual(false)
      expect(driver.muted).assertEqual(false)
      expect(driver.volume).assertEqual(3)
      expect(controller.getState().muted).assertEqual(false)
      expect(controller.getState().currentVolumePercent).assertEqual(30)
    })

    it('applies handset route and mute state', 0, async () => {
      const driver = new MemoryAudioPolicyDriver()
      const controller = new RtcCallAudioPolicyController({ driver })

      const route = await controller.applyAnswerPolicy(RTC_CALL_CONTROL_SOURCE_HANDSET)
      controller.setMuted(true)

      expect(route.speakerEnabled).assertEqual(false)
      expect(route.volumePercent).assertEqual(40)
      expect(driver.handsetMode).assertEqual(true)
      expect(driver.muted).assertEqual(true)
    })
  })
}
