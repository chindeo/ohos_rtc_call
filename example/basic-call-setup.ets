import {
  RTC_WEBRTC_SIGNAL_EVENT_CANDIDATE,
  RTC_WEBRTC_SIGNAL_EVENT_SDP,
  RtcCallRouteResolver,
  RtcRingtoneChannel,
  RtcRingtoneController,
  RtcWebRtcSignalSession,
  RtcWebRtcSignalStateMachine
} from '@chindeo/ohos-rtc-call'

const registerAddress = 'wss://rtc.example.com/websocket'
const deviceNumber = '1001'

const route = RtcCallRouteResolver.resolve({ registerAddress })

if (route.registerAddress.valid) {
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
}

const ringtone = new RtcRingtoneController()
ringtone.configurePolicy({
  webrtcEnabled: route.registerAddress.valid,
  externalUrlEnabled: false
})

ringtone.playIncoming(RtcRingtoneChannel.WEBRTC)
