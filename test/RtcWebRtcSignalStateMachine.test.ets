import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import {
  RTC_WEBRTC_PEER_ROLE_PUBLISH,
  RTC_WEBRTC_PEER_ROLE_SUBSCRIBE,
  RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP,
  RtcWebRtcIceCandidate,
  RtcWebRtcPeerConnectionAdapter,
  RtcWebRtcPeerRole,
  RtcWebRtcSessionDescription,
  RtcWebRtcSignalContext,
  RtcWebRtcSignalStateMachine
} from '../src/main/ets/signaling/RtcWebRtcSignalStateMachine'
import {
  RtcCandidateSignalData,
  RtcCommonRequest,
  RtcSdpSignalData,
  RtcSignalMessage
} from '../src/main/ets/model/RtcSignalTypes'

const VALID_OFFER_SDP = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:offer\r\na=ice-pwd:testpwd\r\na=sendonly\r\n'
const VALID_ANSWER_SDP = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:answer\r\na=ice-pwd:testpwd\r\na=sendrecv\r\n'
const VALID_RECVONLY_SDP = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:offer\r\na=ice-pwd:testpwd\r\na=recvonly\r\n'

class MemoryPeerConnectionAdapter implements RtcWebRtcPeerConnectionAdapter {
  ensuredRoles: string[] = []
  ensuredSessionIds: string[] = []
  remoteDescriptions: RtcWebRtcSessionDescription[] = []
  localDescription?: RtcWebRtcSessionDescription
  candidates: RtcWebRtcIceCandidate[] = []
  sentSignals: RtcSignalMessage[] = []
  current: boolean = true

  async ensurePeerConnection(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): Promise<void> {
    this.ensuredRoles.push(role)
    this.ensuredSessionIds.push(context.sessionId)
  }

  hasPeerConnection(_role: RtcWebRtcPeerRole, _context: RtcWebRtcSignalContext): boolean {
    return true
  }

  isPeerConnectionCurrent(_role: RtcWebRtcPeerRole, _context: RtcWebRtcSignalContext): boolean {
    return this.current
  }

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

  sendSignal(message: RtcSignalMessage, _context: RtcWebRtcSignalContext): void {
    this.sentSignals.push(message)
  }
}

function commonRequest(uuid: string): RtcCommonRequest {
  return {
    uuid,
    locId: 'loc-1',
    hospitalId: 'hospital-1',
    number: '1001',
    displayName: 'Local',
    clientType: 'client',
    identity: 'local-identity',
    to: '1002',
    toName: 'Remote',
    from: '1001',
    fromName: 'Local',
    grpcFrom: '1001',
    grpcTo: '1002',
    isVideo: false
  }
}

function sdpData(uuid: string, rtcUid: string, sdpType: string, sdp: string): RtcSdpSignalData {
  return {
    sdp,
    sdpType,
    rtcUid,
    commonRequest: commonRequest(uuid)
  }
}

function candidateData(uuid: string, rtcUid: string): RtcCandidateSignalData {
  return {
    candidateType: RTC_WEBRTC_PEER_ROLE_PUBLISH,
    candidate: 'candidate:1 1 udp 1 192.0.2.10 10000 typ host',
    sdpMLineIndex: 0,
    sdpMid: '0',
    rtcUid,
    commonRequest: commonRequest(uuid)
  }
}

export default function rtcWebRtcSignalStateMachineTest() {
  describe('RtcWebRtcSignalStateMachine', () => {
    it('encodes and decodes scoped rtc uid', 0, () => {
      const scoped = RtcWebRtcSignalStateMachine.encodeRtcScope('rtc-1', RTC_WEBRTC_PEER_ROLE_SUBSCRIBE)
      const decoded = RtcWebRtcSignalStateMachine.decodeRtcScope(scoped)
      const plain = RtcWebRtcSignalStateMachine.decodeRtcScope('plain-rtc')

      expect(scoped).assertEqual('subscribe|rtc-1')
      expect(decoded.channelType).assertEqual(RTC_WEBRTC_PEER_ROLE_SUBSCRIBE)
      expect(decoded.rtcUid).assertEqual('rtc-1')
      expect(plain.channelType).assertEqual(RTC_WEBRTC_PEER_ROLE_SUBSCRIBE)
    })

    it('builds answer sdp signal with send event by default', 0, () => {
      const message = RtcWebRtcSignalStateMachine.buildSdpSignal({
        uuid: 'call-1',
        rtcUid: RtcWebRtcSignalStateMachine.encodeRtcScope('rtc-1', RTC_WEBRTC_PEER_ROLE_SUBSCRIBE),
        local: { number: '1001', displayName: 'Local', clientType: 'client' },
        remote: { number: '1002', displayName: 'Remote', clientType: 'client' },
        mode: RtcCallMode.AUDIO,
        sdp: VALID_ANSWER_SDP,
        sdpType: 'answer'
      })
      const payload = JSON.parse(message.data) as RtcSdpSignalData

      expect(message.eventName).assertEqual(RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP)
      expect(payload.rtcUid).assertEqual('subscribe|rtc-1')
      expect(payload.commonRequest.grpcTo).assertEqual('1002')
    })

    it('skips stale candidate without creating subscribe state', 0, async () => {
      const adapter = new MemoryPeerConnectionAdapter()
      const machine = new RtcWebRtcSignalStateMachine({ adapter })
      machine.startSession('active-call', 'rtc-active')

      const result = await machine.handleCandidate(candidateData('old-call', 'subscribe|rtc-old'))

      expect(result.skipped).assertEqual(true)
      expect(result.reason).assertEqual('stale session')
      expect(machine.getState().subscribes.length).assertEqual(0)
      expect(adapter.candidates.length).assertEqual(0)
    })

    it('queues candidate until descriptions are ready and then flushes', 0, async () => {
      const adapter = new MemoryPeerConnectionAdapter()
      const machine = new RtcWebRtcSignalStateMachine({ adapter })
      machine.startSession('call-1', 'rtc-1')

      await machine.handleSdp(sdpData('call-1', 'publish|rtc-1', 'offer', VALID_OFFER_SDP), {
        role: RTC_WEBRTC_PEER_ROLE_PUBLISH,
        autoCreateAnswer: false
      })
      await machine.handleCandidate(candidateData('call-1', 'publish|rtc-1'), {
        role: RTC_WEBRTC_PEER_ROLE_PUBLISH
      })
      expect(adapter.candidates.length).assertEqual(0)
      expect(machine.getState().publish.pendingCandidates.length).assertEqual(1)

      await machine.handleSdp(sdpData('call-1', 'publish|rtc-1', 'answer', VALID_ANSWER_SDP), {
        role: RTC_WEBRTC_PEER_ROLE_PUBLISH
      })

      expect(adapter.candidates.length).assertEqual(1)
      expect(machine.getState().publish.pendingCandidates.length).assertEqual(0)
    })

    it('creates local answer and sends sdp response for subscribe offer', 0, async () => {
      const adapter = new MemoryPeerConnectionAdapter()
      const machine = new RtcWebRtcSignalStateMachine({ adapter })

      const result = await machine.handleSdp(sdpData('call-1', 'subscribe|rtc-2', 'offer', VALID_OFFER_SDP), {
        local: { number: '1001', displayName: 'Local', clientType: 'client' },
        remote: { number: '1002', displayName: 'Remote', clientType: 'client' }
      })
      const payload = JSON.parse(adapter.sentSignals[0].data) as RtcSdpSignalData

      expect(result.handled).assertEqual(true)
      expect(result.role).assertEqual(RTC_WEBRTC_PEER_ROLE_SUBSCRIBE)
      expect(adapter.sentSignals.length).assertEqual(1)
      expect(adapter.sentSignals[0].eventName).assertEqual(RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP)
      expect(payload.sdpType).assertEqual('answer')
      expect(payload.rtcUid).assertEqual('subscribe|rtc-2')
    })

    it('rebinds recvonly subscribe offer to publish role', 0, async () => {
      const adapter = new MemoryPeerConnectionAdapter()
      const machine = new RtcWebRtcSignalStateMachine({ adapter })

      const result = await machine.handleSdp(sdpData('call-1', 'subscribe|rtc-3', 'offer', VALID_RECVONLY_SDP), {
        local: { number: '1001', displayName: 'Local', clientType: 'client' },
        remote: { number: '1002', displayName: 'Remote', clientType: 'client' }
      })

      expect(result.role).assertEqual(RTC_WEBRTC_PEER_ROLE_PUBLISH)
      expect(adapter.ensuredRoles[0]).assertEqual(RTC_WEBRTC_PEER_ROLE_PUBLISH)
    })

    it('accepts multiple explicitly registered sessions without clearing subscribe state', 0, async () => {
      const adapter = new MemoryPeerConnectionAdapter()
      const machine = new RtcWebRtcSignalStateMachine({
        adapter,
        requireIceParamsForRemoteSdp: false,
        requireIceParamsForLocalAnswer: false
      })
      machine.registerSession('call-a')
      machine.registerSession('call-b')

      const first = await machine.handleSdp(
        sdpData('call-a', 'subscribe|rtc-a', 'offer', VALID_OFFER_SDP),
        { autoCreateAnswer: false }
      )
      const second = await machine.handleSdp(
        sdpData('call-b', 'subscribe|rtc-b', 'offer', VALID_OFFER_SDP),
        { autoCreateAnswer: false }
      )

      expect(first.handled).assertEqual(true)
      expect(second.handled).assertEqual(true)
      expect(machine.getState().subscribes.length).assertEqual(2)
    })

    it('keeps publish signaling state isolated by session', 0, async () => {
      const adapter = new MemoryPeerConnectionAdapter()
      const machine = new RtcWebRtcSignalStateMachine({
        adapter,
        requireIceParamsForRemoteSdp: false,
        requireIceParamsForLocalAnswer: false
      })
      machine.registerSession('call-a')
      machine.registerSession('call-b')

      await machine.handleSdp(
        sdpData('call-a', 'publish|rtc-a', 'offer', VALID_RECVONLY_SDP),
        { role: RTC_WEBRTC_PEER_ROLE_PUBLISH }
      )
      await machine.handleSdp(
        sdpData('call-b', 'publish|rtc-b', 'offer', VALID_RECVONLY_SDP),
        { role: RTC_WEBRTC_PEER_ROLE_PUBLISH }
      )

      expect(machine.getState().publishes.length).assertEqual(2)
      expect(adapter.ensuredSessionIds[0]).assertEqual('call-a')
      expect(adapter.ensuredSessionIds[1]).assertEqual('call-b')
    })
  })
}
