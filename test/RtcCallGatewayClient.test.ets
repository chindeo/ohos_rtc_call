import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import {
  RtcCallGatewayClient
} from '../src/main/ets/gateway/RtcCallGatewayClient'
import {
  RtcCallGatewayAdapter,
  RtcCallGatewayChannelType
} from '../src/main/ets/gateway/RtcCallGatewayTypes'
import {
  RtcWebRtcIceCandidate,
  RtcWebRtcPeerConnectionAdapter,
  RtcWebRtcPeerRole,
  RtcWebRtcSessionDescription,
  RtcWebRtcSignalContext
} from '../src/main/ets/signaling/RtcWebRtcSignalStateMachine'

const VALID_OFFER_SDP = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:offer\r\na=ice-pwd:testpwd\r\na=sendonly\r\n'
const VALID_ANSWER_SDP = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:answer\r\na=ice-pwd:testpwd\r\na=sendrecv\r\n'

class SentGatewaySdp {
  signalUID: string = ''
  rtcUID: string = ''
  channelType: string = ''
  sdp: string = ''
  sdpType: string = ''
  status: number = 0
}

class SentGatewayCandidate {
  signalUID: string = ''
  rtcUID: string = ''
  channelType: string = ''
  sdpMid: string = ''
  candidate: string = ''
  sdpMLineIndex: number = 0
}

class MemoryGatewayAdapter implements RtcCallGatewayAdapter {
  invited: string[] = []
  answered: string[] = []
  switched: string[] = []
  hungUp: string[] = []
  sentSdp: SentGatewaySdp[] = []
  sentCandidates: SentGatewayCandidate[] = []

  callInvite(to: string, _isVideo: boolean): void {
    this.invited.push(to)
  }

  callAnswer(uid: string): void {
    this.answered.push(uid)
  }

  callSwitch(uid: string): void {
    this.switched.push(uid)
  }

  callHangUp(uid: string, _d: number): void {
    this.hungUp.push(uid)
  }

  sendSdp(
    signalUID: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    sdp: string,
    sdpType: string,
    status: number
  ): void {
    this.sentSdp.push({ signalUID, rtcUID, channelType, sdp, sdpType, status })
  }

  sendCandidate(
    signalUID: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    sdpMid: string,
    candidate: string,
    sdpMLineIndex: number
  ): void {
    this.sentCandidates.push({ signalUID, rtcUID, channelType, sdpMid, candidate, sdpMLineIndex })
  }
}

class MemoryPeerConnectionAdapter implements RtcWebRtcPeerConnectionAdapter {
  remoteDescriptions: RtcWebRtcSessionDescription[] = []
  localDescription?: RtcWebRtcSessionDescription
  candidates: RtcWebRtcIceCandidate[] = []

  async ensurePeerConnection(_role: RtcWebRtcPeerRole, _context: RtcWebRtcSignalContext): Promise<void> {}

  async setRemoteDescription(
    _role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    _context: RtcWebRtcSignalContext
  ): Promise<void> {
    this.remoteDescriptions.push(description)
  }

  async addIceCandidate(
    _role: RtcWebRtcPeerRole,
    candidate: RtcWebRtcIceCandidate,
    _context: RtcWebRtcSignalContext
  ): Promise<void> {
    this.candidates.push(candidate)
  }

  async createAnswer(_role: RtcWebRtcPeerRole, _context: RtcWebRtcSignalContext):
    Promise<RtcWebRtcSessionDescription> {
    return {
      type: 'answer',
      sdp: VALID_ANSWER_SDP
    }
  }

  async setLocalDescription(
    _role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    _context: RtcWebRtcSignalContext
  ): Promise<void> {
    this.localDescription = description
  }

  async getLocalDescription(_role: RtcWebRtcPeerRole, _context: RtcWebRtcSignalContext):
    Promise<RtcWebRtcSessionDescription | undefined> {
    return this.localDescription
  }
}

function createClient(adapter: MemoryGatewayAdapter, peerAdapter?: MemoryPeerConnectionAdapter): RtcCallGatewayClient {
  return new RtcCallGatewayClient({
    adapter,
    peerAdapter,
    local: {
      number: 'host-1001',
      displayName: 'Host'
    }
  })
}

export default function rtcCallGatewayClientTest() {
  describe('RtcCallGatewayClient', () => {
    it('rejects ambiguous answer without uid in multi call', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const client = createClient(adapter)

      client.handleOpenMultiActivity('bed-1', 'Bed 1', 'uid-a', false)
      client.handleOpenMultiActivity('bed-2', 'Bed 2', 'uid-b', false)
      const result = await client.answer('')

      expect(result.handled).assertEqual(false)
      expect(result.reason).assertEqual('ambiguous uid')
      expect(adapter.answered.length).assertEqual(0)
    })

    it('marks answered only after gateway answer succeeds', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const client = createClient(adapter)

      client.handleOpenActivity('bed-1', 'Bed 1', 'uid-a', false)
      const before = client.getSnapshot().calls[0]
      const result = await client.answer('uid-a')
      const after = client.getSnapshot().calls[0]

      expect(before.uplinkMuted).assertEqual(true)
      expect(result.handled).assertEqual(true)
      expect(adapter.answered[0]).assertEqual('uid-a')
      expect(after.phase).assertEqual('answered')
      expect(after.uplinkMuted).assertEqual(false)
    })

    it('sends answer sdp with gateway signal uid and rtc route', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const peerAdapter = new MemoryPeerConnectionAdapter()
      const client = createClient(adapter, peerAdapter)

      client.handleOpenActivity('bed-1', 'Bed 1', 'signal-uid-1', false)
      const result = await client.handleReceiverSdp({
        from: 'bed-1',
        to: 'host-1001',
        uid: 'signal-uid-1',
        rtcUID: 'rtc-sub-1',
        channelType: 'subscribe',
        sdp: VALID_OFFER_SDP,
        sdpType: 'offer',
        isVideo: false
      })

      expect(result.handled).assertEqual(true)
      expect(adapter.sentSdp.length).assertEqual(1)
      expect(adapter.sentSdp[0].signalUID).assertEqual('signal-uid-1')
      expect(adapter.sentSdp[0].rtcUID).assertEqual('rtc-sub-1')
      expect(adapter.sentSdp[0].channelType).assertEqual('subscribe')
      expect(adapter.sentSdp[0].sdpType).assertEqual('answer')
    })

    it('creates minimal session when sdp arrives before activity callback', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const peerAdapter = new MemoryPeerConnectionAdapter()
      const client = createClient(adapter, peerAdapter)

      const result = await client.handleReceiverSdp({
        from: 'bed-9',
        to: 'host-1001',
        uid: 'signal-uid-9',
        rtcUID: 'rtc-sub-9',
        channelType: 'subscribe',
        sdp: VALID_OFFER_SDP,
        sdpType: 'offer'
      })
      const snapshot = client.getSnapshot()

      expect(result.handled).assertEqual(true)
      expect(snapshot.calls[0].uid).assertEqual('signal-uid-9')
      expect(snapshot.calls[0].number).assertEqual('bed-9')
      expect(snapshot.peers[0].rtcUID).assertEqual('rtc-sub-9')
    })

    it('removes only target session on remote hangup', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const client = createClient(adapter)

      client.handleOpenMultiActivity('bed-1', 'Bed 1', 'uid-a', false)
      client.handleOpenMultiActivity('bed-2', 'Bed 2', 'uid-b', false)
      const result = await client.handleHangUp({ uid: 'uid-b' })
      const snapshot = client.getSnapshot()

      expect(result.handled).assertEqual(true)
      expect(snapshot.calls.length).assertEqual(1)
      expect(snapshot.calls[0].uid).assertEqual('uid-a')
    })

    it('sends local candidate with original gateway route fields', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const client = createClient(adapter)

      client.handleOpenActivity('bed-1', 'Bed 1', 'uid-a', false)
      const result = await client.sendLocalCandidate({
        from: 'host-1001',
        to: 'bed-1',
        uid: 'uid-a',
        rtcUID: 'rtc-pub-1',
        channelType: 'publish',
        sdpMid: '0',
        candidate: 'candidate:1 1 udp 1 192.0.2.10 10000 typ host',
        sdpMLineIndex: 0
      })

      expect(result.handled).assertEqual(true)
      expect(adapter.sentCandidates[0].signalUID).assertEqual('uid-a')
      expect(adapter.sentCandidates[0].rtcUID).assertEqual('rtc-pub-1')
      expect(adapter.sentCandidates[0].channelType).assertEqual('publish')
    })

    it('invites with call-gateway target number and video flag', 0, async () => {
      const adapter = new MemoryGatewayAdapter()
      const client = createClient(adapter)

      const result = await client.invite({ number: 'bed-3', uid: 'uid-c' }, RtcCallMode.VIDEO)

      expect(result.handled).assertEqual(true)
      expect(adapter.invited[0]).assertEqual('bed-3')
      expect(client.getSnapshot().calls[0].uid).assertEqual('uid-c')
      expect(client.getSnapshot().calls[0].mode).assertEqual(RtcCallMode.VIDEO)
    })
  })
}
