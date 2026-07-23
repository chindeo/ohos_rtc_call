import { describe, it, expect } from '@ohos/hypium'
import webrtc from '../src/main/ets/webrtc/OhosWebRtc'
import { RtcAudioController, RtcVideoRendererAdapter } from '../src/main/ets/audio/RtcAudioController'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcWebRtcMediaController } from '../src/main/ets/webrtc/RtcWebRtcMediaController'
import { RtcWebRtcTrackIdentityCodec } from '../src/main/ets/webrtc/RtcWebRtcTrackIdentity'

class TestVideoRenderer implements RtcVideoRendererAdapter {
  bindCount: number = 0
  deactivateCount: number = 0
  lastTrackId: string = 'unset'
  events: string[] = []

  setVideoTrack(videoTrack: webrtc.MediaStreamTrack | null): void {
    this.bindCount += 1
    this.lastTrackId = videoTrack?.id || ''
    this.events.push(videoTrack ? 'bind' : 'clear')
  }

  deactivate(): void {
    this.deactivateCount += 1
    this.events.push('deactivate')
  }
}

class TrackingAudioController extends RtcAudioController {
  cleanupCount: number = 0
  releaseLocalVideoCount: number = 0

  releaseLocalVideo(): void {
    this.releaseLocalVideoCount += 1
  }

  cleanupRtcCallResources(_reason: string = 'cleanup'): void {
    this.cleanupCount += 1
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

    it('prefers constrained baseline h264 and keeps vp8 fallback', 0, () => {
      const codecs: webrtc.RTCRtpCodec[] = [
        { mimeType: 'video/VP8', clockRate: 90000 },
        {
          mimeType: 'video/H264',
          clockRate: 90000,
          sdpFmtpLine: 'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f'
        },
        { mimeType: 'video/H265', clockRate: 90000 },
        { mimeType: 'video/rtx', clockRate: 90000, sdpFmtpLine: 'apt=96' }
      ]

      const ordered = RtcWebRtcMediaController.prioritizeVideoCodecs(codecs)

      expect(ordered[0].mimeType).assertEqual('video/H264')
      expect(ordered[1].mimeType).assertEqual('video/VP8')
      expect(ordered[2].mimeType).assertEqual('video/H265')
      expect(ordered.length).assertEqual(4)
    })

    it('caps every video encoding at the configured frame rate', 0, () => {
      const parameters: webrtc.RTCRtpSendParameters = {
        codecs: [],
        headerExtensions: [],
        rtcp: {},
        encodings: [{}, {}],
        transactionId: 'test'
      }

      expect(RtcWebRtcMediaController.applyVideoMaxFrameRate(parameters, 10)).assertEqual(2)
      expect(parameters.encodings[0].maxFramerate).assertEqual(10)
      expect(parameters.encodings[1].maxFramerate).assertEqual(10)
      expect(RtcWebRtcMediaController.applyVideoMaxFrameRate(parameters, 0)).assertEqual(0)
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
      expect(rendererA.deactivateCount).assertEqual(1)
      expect(rendererA.events[rendererA.events.length - 2]).assertEqual('clear')
      expect(rendererA.events[rendererA.events.length - 1]).assertEqual('deactivate')
      expect(rendererB.bindCount).assertEqual(rendererBBindCount)
      expect(rendererB.deactivateCount).assertEqual(0)
      expect(controller.getMediaState('uid-b')?.sessionKey).assertEqual('uid-b')
      controller.dispose()
    })

    it('runs full media teardown once per resource generation', 0, () => {
      const audioController = new TrackingAudioController()
      const controller = new RtcWebRtcMediaController({
        local: { number: '1000' },
        appVersion: 'test',
        audioController
      })

      controller.closeAll('first close')
      controller.closeAll('duplicate close')
      expect(audioController.cleanupCount).assertEqual(1)
      expect(audioController.releaseLocalVideoCount).assertEqual(0)

      controller.registerSession({
        sessionKey: 'uid-a',
        sessionId: 'call-a',
        targetNumber: '1101'
      })
      controller.closeAll('next generation')
      controller.dispose()

      expect(audioController.cleanupCount).assertEqual(2)
      expect(audioController.releaseLocalVideoCount).assertEqual(0)
    })
  })
}
