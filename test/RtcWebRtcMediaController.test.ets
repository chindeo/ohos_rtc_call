import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcWebRtcMediaController } from '../src/main/ets/webrtc/RtcWebRtcMediaController'
import { RtcWebRtcTrackIdentityCodec } from '../src/main/ets/webrtc/RtcWebRtcTrackIdentity'

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
  })
}
