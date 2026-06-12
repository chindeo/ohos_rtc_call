import {
  RtcCallGatewayAdapter,
  RtcCallGatewayClient,
  RtcCallGatewaySdpOptions,
  RtcWebRtcPeerConnectionAdapter,
  RtcWebRtcSessionDescription
} from '@chindeo/ohos-rtc-call'

class HostCallGatewayAdapter implements RtcCallGatewayAdapter {
  callInvite(to: string, isVideo: boolean): void {
    console.info(`CallInvite to=${to} isVideo=${isVideo}`)
  }

  callAnswer(uid: string): void {
    console.info(`CallAnswer uid=${uid}`)
  }

  callSwitch(uid: string): void {
    console.info(`CallSwitch uid=${uid}`)
  }

  callHangUp(uid: string, d: number): void {
    console.info(`CallHangUp uid=${uid} d=${d}`)
  }

  sendSdp(
    signalUID: string,
    rtcUID: string,
    channelType: 'publish' | 'subscribe',
    _sdp: string,
    sdpType: string,
    _status: number
  ): void {
    console.info(`SendSdp signalUID=${signalUID} rtcUID=${rtcUID} channelType=${channelType} type=${sdpType}`)
  }

  sendCandidate(
    signalUID: string,
    rtcUID: string,
    channelType: 'publish' | 'subscribe',
    sdpMid: string,
    _candidate: string,
    _sdpMLineIndex: number
  ): void {
    console.info(`SendCandidate signalUID=${signalUID} rtcUID=${rtcUID} channelType=${channelType} mid=${sdpMid}`)
  }
}

const peerAdapter: RtcWebRtcPeerConnectionAdapter = {
  async ensurePeerConnection(_role, _context) {},
  async setRemoteDescription(_role, _description, _context) {},
  async addIceCandidate(_role, _candidate, _context) {},
  async createAnswer(_role, _context): Promise<RtcWebRtcSessionDescription> {
    return {
      type: 'answer',
      sdp: 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:answer\r\na=ice-pwd:placeholder\r\n'
    }
  },
  async setLocalDescription(_role, _description, _context) {},
  async getLocalDescription(_role, _context): Promise<RtcWebRtcSessionDescription | undefined> {
    return undefined
  }
}

const client = new RtcCallGatewayClient({
  adapter: new HostCallGatewayAdapter(),
  peerAdapter,
  local: {
    number: 'host-1001',
    displayName: 'Host Device',
    clientType: 'host'
  }
})

client.handleOpenMultiActivity('bed-1002', 'Bed 1002', 'signal-uid-1002', false)

const inboundOffer: RtcCallGatewaySdpOptions = {
  from: 'bed-1002',
  to: 'host-1001',
  uid: 'signal-uid-1002',
  rtcUID: 'rtc-sub-1002',
  channelType: 'subscribe',
  sdp: 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=ice-ufrag:offer\r\na=ice-pwd:placeholder\r\na=sendonly\r\n',
  sdpType: 'offer'
}

client.handleReceiverSdp(inboundOffer)
