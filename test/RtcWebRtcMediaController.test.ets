import { describe, it, expect } from '@ohos/hypium'
import webrtc from '@ohos/webrtc'
import { RtcVideoRendererAdapter } from '../src/main/ets/audio/RtcAudioController'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcWebRtcMediaController } from '../src/main/ets/webrtc/RtcWebRtcMediaController'
import { RtcWebRtcTrackIdentityCodec } from '../src/main/ets/webrtc/RtcWebRtcTrackIdentity'

class TestVideoRenderer implements RtcVideoRendererAdapter {
  bindCount: number = 0
  lastTrackId: string = 'unset'

  setVideoTrack(videoTrack: webrtc.MediaStreamTrack | null): void {
    this.bindCount += 1
    this.lastTrackId = videoTrack?.id || ''
  }
}

export default function rtcWebRtcMediaControllerTest() {
  describe('RtcWebRtcMediaController', () => {
    it('round trips utf8 track identity', 0, () => {
      const trackId = RtcWebRtcTrackIdentityCodec.buildTrackId({
        number: '1101',
        displayName: '床旁1',
        clientType: 'bed'
      }, 'test', 'fixed')
      const identity = RtcWebRtcTrackIdentityCodec.parse(trackId)

      expect(identity?.number).assertEqual('1101')
      expect(identity?.display_name).assertEqual('床旁1')
      expect(identity?.client_type).assertEqual('bed')
    })

    it('requires video track for normal video device', 0, () => {
      expect(RtcWebRtcMediaController.isMediaConnected(
        RtcCallMode.VIDEO,
        'bed',
        true,
        false
      )).assertEqual(false)
      expect(RtcWebRtcMediaController.isMediaConnected(
        RtcCallMode.VIDEO,
        'bed',
        true,
        true
      )).assertEqual(true)
    })

    it('accepts audio track for audio call and watch device', 0, () => {
      expect(RtcWebRtcMediaController.isMediaConnected(
        RtcCallMode.AUDIO,
        'bed',
        true,
        false
      )).assertEqual(true)
      expect(RtcWebRtcMediaController.isMediaConnected(
        RtcCallMode.VIDEO,
        'watch',
        true,
        false
      )).assertEqual(true)
    })

    it('reports local video ready only for a live track', 0, () => {
      expect(RtcWebRtcMediaController.isLocalVideoReady()).assertEqual(false)
      expect(RtcWebRtcMediaController.isLocalVideoReady('ended')).assertEqual(false)
      expect(RtcWebRtcMediaController.isLocalVideoReady('live')).assertEqual(true)
    })

    it('clears only the renderer bound to the closed session', 0, () => {
      const controller = new RtcWebRtcMediaController({
        local: { number: '1000' },
        appVersion: 'test'
      })
      controller.registerSession({
        sessionKey: 'uid-a',
        sessionId: 'call-a',
        targetNumber: '1101'
      })
      controller.registerSession({
        sessionKey: 'uid-b',
        sessionId: 'call-b',
        targetNumber: '1111'
      })
      const rendererA = new TestVideoRenderer()
      const rendererB = new TestVideoRenderer()

      expect(controller.bindSessionRemoteVideoRenderer('uid-a', rendererA)).assertEqual(true)
      expect(controller.bindSessionRemoteVideoRenderer('uid-b', rendererB)).assertEqual(true)
      const rendererBBindCount = rendererB.bindCount

      expect(controller.closeSession('uid-a')).assertEqual(true)
      expect(rendererA.lastTrackId).assertEqual('')
      expect(rendererB.bindCount).assertEqual(rendererBBindCount)
      expect(controller.getMediaState('uid-b')?.sessionKey).assertEqual('uid-b')
      controller.dispose()
    })
  })
}
