import { describe, it, expect } from '@ohos/hypium'
import { RtcAudioController, RtcVideoRendererAdapter } from '../src/main/ets/audio/RtcAudioController'
import webrtc from '@ohos/webrtc'

class MemoryVideoRenderer implements RtcVideoRendererAdapter {
  bindCount: number = 0
  lastTrack: webrtc.MediaStreamTrack | null | undefined = undefined

  setVideoTrack(videoTrack: webrtc.MediaStreamTrack | null): void {
    this.bindCount += 1
    this.lastTrack = videoTrack
  }
}

export default function rtcAudioControllerTest() {
  describe('RtcAudioController', () => {
    it('starts with empty resource snapshot', 0, () => {
      const controller = new RtcAudioController()
      const snapshot = controller.getSnapshot()

      expect(snapshot.ready).assertEqual(false)
      expect(snapshot.hasAudioDeviceModule).assertEqual(false)
      expect(snapshot.hasPeerConnectionFactory).assertEqual(false)
      expect(snapshot.hasLocalAudioTrack).assertEqual(false)
      expect(snapshot.hasLocalVideoTrack).assertEqual(false)
      expect(snapshot.aecDumpStarted).assertEqual(false)
      expect(snapshot.audioSampleCount).assertEqual(0)
    })

    it('binds empty video renderers without creating media resources', 0, () => {
      const controller = new RtcAudioController()
      const localRenderer = new MemoryVideoRenderer()
      const remoteRenderer = new MemoryVideoRenderer()

      controller.bindLocalVideoRenderer(localRenderer)
      controller.bindRemoteVideoRenderer(remoteRenderer)
      controller.clearRemoteMedia()
      const snapshot = controller.getSnapshot()

      expect(localRenderer.bindCount).assertEqual(1)
      expect(remoteRenderer.bindCount).assertEqual(2)
      expect(localRenderer.lastTrack).assertEqual(null)
      expect(remoteRenderer.lastTrack).assertEqual(null)
      expect(snapshot.hasLocalVideoTrack).assertEqual(false)
      expect(snapshot.hasRemoteVideoTrack).assertEqual(false)
    })

    it('counts non-zero audio sample bytes', 0, () => {
      const buffer = new ArrayBuffer(6)
      const bytes = new Uint8Array(buffer)
      bytes[0] = 0
      bytes[1] = 1
      bytes[2] = 2
      bytes[3] = 0
      bytes[4] = 3
      bytes[5] = 0

      expect(RtcAudioController.countNonZeroArrayBufferBytes(buffer)).assertEqual(3)
      expect(RtcAudioController.countNonZeroArrayBufferBytes()).assertEqual(0)
    })

    it('cleanup without prepared resources is idempotent', 0, () => {
      const controller = new RtcAudioController()

      controller.cleanupRtcCallResources('unit test')
      controller.cleanupRtcCallResources('unit test repeat')
      const snapshot = controller.getSnapshot()

      expect(snapshot.ready).assertEqual(false)
      expect(snapshot.hasLocalAudioTrack).assertEqual(false)
      expect(snapshot.hasLocalVideoTrack).assertEqual(false)
      expect(snapshot.hasRemoteAudioTrack).assertEqual(false)
      expect(snapshot.hasRemoteVideoTrack).assertEqual(false)
    })
  })
}
