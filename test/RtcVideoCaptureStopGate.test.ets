import { describe, it, expect } from '@ohos/hypium'
import { RtcVideoCaptureStopGate, RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS }
  from '../src/main/ets/audio/RtcVideoCaptureStopGate'
import { RtcAudioController } from '../src/main/ets/audio/RtcAudioController'

export default function rtcVideoCaptureStopGateTest() {
  describe('RtcVideoCaptureStopGate', () => {
    it('starts quiesced with an exportable default deadline', 0, () => {
      const gate = new RtcVideoCaptureStopGate()

      expect(gate.isPending()).assertEqual(false)
      expect(gate.pendingAgeMs()).assertEqual(0)
      expect(RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS > 0).assertEqual(true)
    })

    it('resolves a waiter as stopped once native confirms capture stopped', 0, async () => {
      const gate = new RtcVideoCaptureStopGate()
      const token: number = gate.arm()
      const pending: Promise<string> = gate.wait(1000)

      expect(gate.isPending()).assertEqual(true)
      expect(gate.settle(token)).assertEqual(true)

      expect(await pending).assertEqual('stopped')
      expect(gate.isPending()).assertEqual(false)
    })

    it('resolves immediately when there is nothing to wait for', 0, async () => {
      const gate = new RtcVideoCaptureStopGate()

      expect(await gate.wait(50)).assertEqual('quiesced')
    })

    it('keeps an unconfirmed release pending after the deadline', 0, async () => {
      const gate = new RtcVideoCaptureStopGate()
      gate.arm()

      expect(await gate.wait(30)).assertEqual('timeout')
      expect(gate.isPending()).assertEqual(true)
      expect(gate.pendingAgeMs() >= 0).assertEqual(true)
    })

    it('ignores a stale stop callback from an earlier release', 0, () => {
      const gate = new RtcVideoCaptureStopGate()
      const staleToken: number = gate.arm()
      const currentToken: number = gate.arm()

      expect(gate.settle(staleToken)).assertEqual(false)
      expect(gate.isPending()).assertEqual(true)
      expect(gate.settle(currentToken)).assertEqual(true)
      expect(gate.isPending()).assertEqual(false)
    })
  })

  describe('RtcAudioController local video release', () => {
    it('reports quiescence and resolves the async release without any media resource', 0, async () => {
      const controller = new RtcAudioController()

      expect(controller.isLocalVideoCaptureQuiesced()).assertEqual(true)

      const result: string = await controller.releaseLocalVideoAsync(50)

      expect(result).assertEqual('quiesced')
      expect(controller.isLocalVideoCaptureQuiesced()).assertEqual(true)
      const snapshot = controller.getSnapshot()
      expect(snapshot.hasLocalVideoTrack).assertEqual(false)
    })

    it('keeps the stop gate closed for repeated idempotent releases', 0, async () => {
      const controller = new RtcAudioController()

      expect(await controller.releaseLocalVideoAsync(50)).assertEqual('quiesced')
      expect(await controller.releaseLocalVideoAsync(50)).assertEqual('quiesced')
      expect(controller.localVideoCapturePendingAgeMs()).assertEqual(0)
    })
  })
}
