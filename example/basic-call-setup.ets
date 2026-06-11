import {
  RTC_WEBRTC_SIGNAL_EVENT_CANDIDATE,
  RTC_WEBRTC_SIGNAL_EVENT_SDP,
  RtcCallRouteResolver,
  RtcRingtoneChannel,
  RtcRingtoneController,
  RtcTransportProtocol,
  RtcWebRtcSignalSession,
  RtcWebRtcSignalStateMachine
} from '@chindeo/ohos-rtc-call'

const registerAddress = 'wss://rtc.example.com/websocket'
const deviceNumber = '1001'

const route = RtcCallRouteResolver.resolve({
  registerAddress,
  sipUser: deviceNumber,
  sipPassword: '',
  deviceIp: ''
})

if (route.protocol === RtcTransportProtocol.WEBRTC) {
  const session = new RtcWebRtcSignalSession()
  const signalStateMachine = new RtcWebRtcSignalStateMachine({
    adapter: {
      async ensurePeerConnection(_role, _context) {},
      async setRemoteDescription(_role, _description, _context) {},
      async addIceCandidate(_role, _candidate, _context) {}
    },
    logger: {
      info: message => console.info(message),
      warn: message => console.warn(message),
      error: message => console.error(message)
    }
  })

  session.setListener({
    onRegister: (_message, server) => {
      console.info(`WebRTC registered: ${server?.serveNumber || ''}`)
    },
    onError: message => {
      console.error(`WebRTC signal error: ${message}`)
    },
    onMessage: message => {
      if (message.eventName === RTC_WEBRTC_SIGNAL_EVENT_SDP) {
        signalStateMachine.handleSdpMessage(message)
        return
      }
      if (message.eventName === RTC_WEBRTC_SIGNAL_EVENT_CANDIDATE) {
        signalStateMachine.handleCandidateMessage(message)
      }
    }
  })

  session.connect({
    serverUrl: route.webrtcSignalUrl || '',
    appVersion: 'example_webrtc',
    identity: {
      number: deviceNumber,
      clientType: 'client',
      displayName: 'Example Device'
    }
  })
} else if (route.sipConfig) {
  // Pass route.sipConfig to the host application's SIP vendor adapter.
  console.info(`SIP server: ${route.sipConfig.sipServer}`)
}

const ringtone = new RtcRingtoneController()
ringtone.configurePolicy({
  webrtcEnabled: route.protocol === RtcTransportProtocol.WEBRTC,
  sipEnabled: route.protocol === RtcTransportProtocol.SIP,
  externalUrlEnabled: false
})

ringtone.playIncoming(
  route.protocol === RtcTransportProtocol.WEBRTC ? RtcRingtoneChannel.WEBRTC : RtcRingtoneChannel.SIP
)
