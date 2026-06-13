import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcApplySignalData, RtcServerInfo, RtcSignalMessage } from '../src/main/ets/model/RtcSignalTypes'
import {
  RtcWebRtcSignalConnectOptions,
  RtcWebRtcSignalConnectResult,
  RtcWebRtcSignalMessage,
  RtcWebRtcSignalSession,
  RtcWebRtcSignalSessionListener
} from '../src/main/ets/signaling/RtcWebRtcSignalSession'
import { RtcWebRtcCallController } from '../src/main/ets/webrtc/RtcWebRtcCallController'
import {
  RtcWebRtcCloseSessionOptions,
  RtcWebRtcMediaController
} from '../src/main/ets/webrtc/RtcWebRtcMediaController'

class TestSignalSession extends RtcWebRtcSignalSession {
  listener?: RtcWebRtcSignalSessionListener
  sentSignals: RtcSignalMessage[] = []

  setListener(listener: RtcWebRtcSignalSessionListener): void {
    this.listener = listener
  }

  connect(options: RtcWebRtcSignalConnectOptions): RtcWebRtcSignalConnectResult {
    return {
      started: true,
      skipped: false,
      reason: 'test',
      url: options.serverUrl
    }
  }

  close(): void {
  }

  sendSignal(message: RtcSignalMessage): void {
    this.sentSignals.push(message)
  }

  emitRegister(): void {
    const server: RtcServerInfo = {
      serveNumber: 'serve-1',
      serveIp: '127.0.0.1',
      serveDisplayName: 'serve'
    }
    this.listener?.onRegister?.({
      eventName: 'c__register',
      status: 200,
      data: JSON.stringify(server)
    }, server)
  }

  emitMessage(message: RtcWebRtcSignalMessage): void {
    this.listener?.onMessage?.(message)
  }
}

class TestCloseSessionCall {
  sessionKey: string = ''
  preservePublish: boolean = false
}

class TrackingMediaController extends RtcWebRtcMediaController {
  closeSessionCalls: TestCloseSessionCall[] = []

  closeSession(
    sessionKey: string,
    reason: string = 'close session',
    options?: RtcWebRtcCloseSessionOptions
  ): boolean {
    const call = new TestCloseSessionCall()
    call.sessionKey = sessionKey
    call.preservePublish = options?.preservePublish === true
    this.closeSessionCalls.push(call)
    return super.closeSession(sessionKey, reason, options)
  }
}

function createMediaController(): RtcWebRtcMediaController {
  return new RtcWebRtcMediaController({
    local: { number: '1000' },
    appVersion: 'test'
  })
}

function createController(signalSession: TestSignalSession): RtcWebRtcCallController {
  return createControllerWithMedia(signalSession, createMediaController())
}

function createControllerWithMedia(
  signalSession: TestSignalSession,
  mediaController: RtcWebRtcMediaController
): RtcWebRtcCallController {
  const controller = new RtcWebRtcCallController(mediaController, {}, signalSession)
  controller.start({
    serverUrl: 'ws://rtc.example.com/websocket',
    appVersion: 'test',
    identity: {
      number: '1000',
      displayName: '护士站',
      clientType: 'nurses'
    },
    local: {
      number: '1000',
      displayName: '护士站',
      clientType: 'nurses'
    }
  })
  signalSession.emitRegister()
  return controller
}

function parseApply(message: RtcSignalMessage): RtcApplySignalData {
  return JSON.parse(message.data) as RtcApplySignalData
}

export default function rtcWebRtcCallControllerTest() {
  describe('RtcWebRtcCallController', () => {
    it('sends a single hangup apply for one session', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = createController(signalSession)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      expect(controller.hangup('call-a')).assertEqual(true)

      expect(signalSession.sentSignals.length).assertEqual(1)
      const apply = parseApply(signalSession.sentSignals[0])
      expect(signalSession.sentSignals[0].eventName).assertEqual('s__apply')
      expect(apply.applyType).assertEqual(3)
      expect(apply.isAll).assertEqual(false)
      expect(apply.commonRequest.uuid).assertEqual('call-a')
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(controller.getSession('call-b')?.sessionKey).assertEqual('call-b')
      controller.dispose()
    })

    it('preserves shared publish for single hangup until explicit all hangup', 0, () => {
      const signalSession = new TestSignalSession()
      const mediaController = new TrackingMediaController({
        local: { number: '1000' },
        appVersion: 'test'
      })
      const controller = createControllerWithMedia(signalSession, mediaController)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      expect(controller.hangup('call-a')).assertEqual(true)

      expect(mediaController.closeSessionCalls.length).assertEqual(1)
      expect(mediaController.closeSessionCalls[0].sessionKey).assertEqual('call-a')
      expect(mediaController.closeSessionCalls[0].preservePublish).assertEqual(true)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(controller.getSession('call-b')?.sessionKey).assertEqual('call-b')

      expect(controller.hangup('call-b')).assertEqual(true)

      expect(mediaController.closeSessionCalls.length).assertEqual(2)
      expect(mediaController.closeSessionCalls[1].sessionKey).assertEqual('call-b')
      expect(mediaController.closeSessionCalls[1].preservePublish).assertEqual(true)
      expect(controller.getSession('call-b') === undefined).assertEqual(true)
      controller.dispose()
    })

    it('sends all hangup apply only for hangupAll', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = createController(signalSession)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      controller.hangupAll()

      expect(signalSession.sentSignals.length).assertEqual(1)
      const apply = parseApply(signalSession.sentSignals[0])
      expect(apply.applyType).assertEqual(3)
      expect(apply.isAll).assertEqual(true)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(controller.getSession('call-b') === undefined).assertEqual(true)
      controller.dispose()
    })

    it('removes only the matched session for a remote terminal notice', 0, () => {
      let endedKey = ''
      let endedAll = false
      const signalSession = new TestSignalSession()
      const mediaController = new RtcWebRtcMediaController({
        local: { number: '1000' },
        appVersion: 'test'
      })
      const controller = new RtcWebRtcCallController(mediaController, {
        onHangup: (sessionKey: string, all: boolean) => {
          endedKey = sessionKey
          endedAll = all
        }
      }, signalSession)
      controller.start({
        serverUrl: 'ws://rtc.example.com/websocket',
        appVersion: 'test',
        identity: { number: '1000' },
        local: { number: '1000' }
      })
      signalSession.emitRegister()
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          isAll: true,
          commonRequest: {
            uuid: '',
            number: '1101',
            from: '1101',
            to: '1000'
          }
        })
      })

      expect(endedKey).assertEqual('call-a')
      expect(endedAll).assertEqual(false)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(controller.getSession('call-b')?.sessionKey).assertEqual('call-b')
      controller.dispose()
    })

    it('hangs up the last call for a remote terminal notice without target identity', 0, () => {
      let endedAll = false
      const signalSession = new TestSignalSession()
      const mediaController = new RtcWebRtcMediaController({
        local: { number: '1000' },
        appVersion: 'test'
      })
      const controller = new RtcWebRtcCallController(mediaController, {
        onHangup: (_sessionKey: string, all: boolean) => {
          endedAll = all
        }
      }, signalSession)
      controller.start({
        serverUrl: 'ws://rtc.example.com/websocket',
        appVersion: 'test',
        identity: { number: '1000' },
        local: { number: '1000' }
      })
      signalSession.emitRegister()
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)

      signalSession.emitMessage({
        eventName: 'c__offline',
        data: JSON.stringify({
          commonRequest: {
            uuid: '',
            number: ''
          }
        })
      })

      expect(endedAll).assertEqual(true)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      controller.dispose()
    })

    it('ignores identityless terminal echo after a local single hangup in multi-call', 0, () => {
      let endedAll = false
      const logs: string[] = []
      const signalSession = new TestSignalSession()
      const mediaController = new RtcWebRtcMediaController({
        local: { number: '1000' },
        appVersion: 'test'
      })
      const controller = new RtcWebRtcCallController(mediaController, {
        onHangup: (_sessionKey: string, all: boolean) => {
          endedAll = all
        },
        onLog: (message: string) => {
          logs.push(message)
        }
      }, signalSession)
      controller.start({
        serverUrl: 'ws://rtc.example.com/websocket',
        appVersion: 'test',
        identity: { number: '1000' },
        local: { number: '1000' }
      })
      signalSession.emitRegister()
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      expect(controller.hangup('call-a')).assertEqual(true)
      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          isAll: true,
          commonRequest: {
            uuid: '',
            number: ''
          }
        })
      })

      expect(endedAll).assertEqual(false)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(controller.getSession('call-b')?.sessionKey).assertEqual('call-b')
      expect(logs.some((message: string) =>
        message.indexOf('ignore terminal echo after local single hangup') >= 0)).assertEqual(true)
      controller.dispose()
    })

    it('ignores sibling terminal echo after a local single hangup in multi-call', 0, () => {
      let endedKey = ''
      const logs: string[] = []
      const signalSession = new TestSignalSession()
      const mediaController = new RtcWebRtcMediaController({
        local: { number: '1000' },
        appVersion: 'test'
      })
      const controller = new RtcWebRtcCallController(mediaController, {
        onHangup: (sessionKey: string) => {
          endedKey = sessionKey
        },
        onLog: (message: string) => {
          logs.push(message)
        }
      }, signalSession)
      controller.start({
        serverUrl: 'ws://rtc.example.com/websocket',
        appVersion: 'test',
        identity: { number: '1000' },
        local: { number: '1000' }
      })
      signalSession.emitRegister()
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      expect(controller.hangup('call-a')).assertEqual(true)
      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          commonRequest: {
            uuid: 'call-b',
            number: '1111',
            from: '1111',
            to: '1000'
          }
        })
      })

      expect(endedKey).assertEqual('')
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(controller.getSession('call-b')?.sessionKey).assertEqual('call-b')
      expect(logs.some((message: string) =>
        message.indexOf('ignore terminal echo after local single hangup') >= 0)).assertEqual(true)
      controller.dispose()
    })
  })
}
