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

class TestCloseAllCall {
  reason: string = ''
}

class TrackingMediaController extends RtcWebRtcMediaController {
  closeSessionCalls: TestCloseSessionCall[] = []
  closeAllCalls: TestCloseAllCall[] = []

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

  closeAll(reason: string = 'close all'): void {
    const call = new TestCloseAllCall()
    call.reason = reason
    this.closeAllCalls.push(call)
    super.closeAll(reason)
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

    it('sends hold as a target switch apply', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = createController(signalSession)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)

      expect(controller.hold('call-a')).assertEqual(true)

      expect(signalSession.sentSignals.length).assertEqual(1)
      expect(signalSession.sentSignals[0].eventName).assertEqual('s__apply')
      const apply = parseApply(signalSession.sentSignals[0])
      expect(apply.applyType).assertEqual(4)
      expect(apply.isAll).assertEqual(false)
      expect(apply.commonRequest.uuid).assertEqual('call-a')
      controller.dispose()
    })

    it('sends resume as a target switch apply', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = createController(signalSession)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)

      expect(controller.resume('call-a')).assertEqual(true)

      expect(signalSession.sentSignals.length).assertEqual(1)
      expect(signalSession.sentSignals[0].eventName).assertEqual('s__apply')
      const apply = parseApply(signalSession.sentSignals[0])
      expect(apply.applyType).assertEqual(4)
      expect(apply.isAll).assertEqual(false)
      expect(apply.commonRequest.uuid).assertEqual('call-a')
      controller.dispose()
    })

    it('sends resume switch apply by unique target number', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = createController(signalSession)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)

      expect(controller.resume('1101')).assertEqual(true)

      expect(signalSession.sentSignals.length).assertEqual(1)
      const apply = parseApply(signalSession.sentSignals[0])
      expect(apply.applyType).assertEqual(4)
      expect(apply.isAll).assertEqual(false)
      expect(apply.commonRequest.uuid).assertEqual('call-a')
      controller.dispose()
    })

    it('does not send resume switch apply for unknown target number', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = createController(signalSession)
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)

      expect(controller.resume('9999')).assertEqual(false)

      expect(signalSession.sentSignals.length).assertEqual(0)
      controller.dispose()
    })

    it('does not send resume switch apply before server registration', 0, () => {
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {}, signalSession)
      controller.start({
        serverUrl: 'ws://rtc.example.com/websocket',
        appVersion: 'test',
        identity: { number: '1000' },
        local: { number: '1000' }
      })
      controller.registerOutgoingSession('call-a', { number: '1101' }, RtcCallMode.AUDIO)

      expect(controller.resume('call-a')).assertEqual(false)

      expect(signalSession.sentSignals.length).assertEqual(0)
      controller.dispose()
    })

    it('applies hold notice by uid', 0, () => {
      let holdKey = ''
      let holdState = false
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKey = sessionKey
          holdState = isHold
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            uid: 'call-a',
            is_hold: true,
            status: 'hold'
          })
        })
      })

      expect(holdKey).assertEqual('call-a')
      expect(holdState).assertEqual(true)
      controller.dispose()
    })

    it('applies resume notice by uid status', 0, () => {
      let holdKey = ''
      let holdState = true
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKey = sessionKey
          holdState = isHold
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            uid: 'call-a',
            status: 'answered'
          })
        })
      })

      expect(holdKey).assertEqual('call-a')
      expect(holdState).assertEqual(false)
      controller.dispose()
    })

    it('applies switch notice map by target uid', 0, () => {
      const holdKeys: string[] = []
      const holdStates: boolean[] = []
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKeys.push(sessionKey)
          holdStates.push(isHold)
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            type: 'switch',
            info: {
              'call-a': true,
              'call-b': false
            }
          })
        })
      })

      expect(holdKeys.length).assertEqual(2)
      expect(holdKeys[0]).assertEqual('call-a')
      expect(holdStates[0]).assertEqual(true)
      expect(holdKeys[1]).assertEqual('call-b')
      expect(holdStates[1]).assertEqual(false)
      controller.dispose()
    })

    it('applies switch notice map by target number', 0, () => {
      let holdKey = ''
      let holdState = false
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKey = sessionKey
          holdState = isHold
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            type: 'hold',
            info: {
              '1101': true
            }
          })
        })
      })

      expect(holdKey).assertEqual('call-a')
      expect(holdState).assertEqual(true)
      controller.dispose()
    })

    it('applies resume switch notice map by target number', 0, () => {
      let holdKey = ''
      let holdState = true
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKey = sessionKey
          holdState = isHold
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            type: 'switch',
            info: {
              '1101': false
            }
          })
        })
      })

      expect(holdKey).assertEqual('call-a')
      expect(holdState).assertEqual(false)
      controller.dispose()
    })

    it('applies camel case resume notice by uid', 0, () => {
      let holdKey = ''
      let holdState = true
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKey = sessionKey
          holdState = isHold
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            uid: 'call-a',
            isHold: false
          })
        })
      })

      expect(holdKey).assertEqual('call-a')
      expect(holdState).assertEqual(false)
      controller.dispose()
    })

    it('keeps legacy hold broadcast compatibility', 0, () => {
      let holdKey = ''
      let holdState = false
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, isHold: boolean) => {
          holdKey = sessionKey
          holdState = isHold
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            type: 'hold',
            info: 'call-a'
          })
        })
      })

      expect(holdKey).assertEqual('call-a')
      expect(holdState).assertEqual(true)
      controller.dispose()
    })

    it('ignores hold notice without uid in multi-call', 0, () => {
      let holdKey = ''
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onHoldChange: (sessionKey: string, _isHold: boolean) => {
          holdKey = sessionKey
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
        eventName: 'c__broadcast',
        data: JSON.stringify({
          data: JSON.stringify({
            status: 'hold',
            is_hold: true
          })
        })
      })

      expect(holdKey).assertEqual('')
      controller.dispose()
    })

    it('removes only the matched session for a remote terminal notice when other calls remain', 0, () => {
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
          isHangUp: false,
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

    it('merges outgoing local session with server invite uuid for the same target', 0, () => {
      let incomingKey = ''
      let incomingName = ''
      const signalSession = new TestSignalSession()
      const controller = new RtcWebRtcCallController(createMediaController(), {
        onIncoming: (session) => {
          incomingKey = session.sessionKey
          incomingName = session.targetName
        }
      }, signalSession)
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
      controller.registerOutgoingSession('local-call-1', { number: '1101' }, RtcCallMode.AUDIO)

      signalSession.emitMessage({
        eventName: 'c__invite',
        data: JSON.stringify({
          commonRequest: {
            uuid: 'server-call-1',
            number: '1000',
            from: '1000',
            fromName: '护士站',
            to: '1101',
            toName: '床旁1',
            clientType: 'nurses'
          }
        })
      })

      expect(incomingKey).assertEqual('server-call-1')
      expect(incomingName).assertEqual('床旁1')
      expect(controller.getSession('server-call-1')?.sessionKey).assertEqual('server-call-1')
      expect(controller.getSession('local-call-1')?.sessionKey).assertEqual('server-call-1')
      controller.dispose()
    })

    it('removes only the matched remote hangup target even when backend reports no other calls', 0, () => {
      let endedKey = ''
      let endedAll = false
      const signalSession = new TestSignalSession()
      const mediaController = new TrackingMediaController({
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
          isHangUp: true,
          commonRequest: {
            uuid: 'call-a',
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
      expect(mediaController.closeSessionCalls[0].preservePublish).assertEqual(true)
      expect(mediaController.closeAllCalls.length).assertEqual(0)
      controller.dispose()
    })

    it('releases publish for the last matched remote hangup target', 0, () => {
      let endedKey = ''
      let endedAll = false
      const signalSession = new TestSignalSession()
      const mediaController = new TrackingMediaController({
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

      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          isHangUp: true,
          commonRequest: {
            uuid: 'call-a',
            number: '1101',
            from: '1101',
            to: '1000'
          }
        })
      })

      expect(endedKey).assertEqual('call-a')
      expect(endedAll).assertEqual(false)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(mediaController.closeSessionCalls[0].preservePublish).assertEqual(false)
      expect(mediaController.closeAllCalls.length).assertEqual(0)
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

    it('hangs up the last call for an identityless c__hangup when no other call remains', 0, () => {
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
        eventName: 'c__hangup',
        data: JSON.stringify({
          isHangUp: true,
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

    it('hangs up the last call for an identityless c__hangup without isHangUp', 0, () => {
      let endedAll = false
      const signalSession = new TestSignalSession()
      const mediaController = new TrackingMediaController({
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
        eventName: 'c__hangup',
        data: JSON.stringify({
          commonRequest: {
            uuid: '',
            number: ''
          }
        })
      })

      expect(endedAll).assertEqual(true)
      expect(controller.getSession('call-a') === undefined).assertEqual(true)
      expect(mediaController.closeAllCalls.length).assertEqual(1)
      controller.dispose()
    })

    it('closes preserved publish after local hangup echo says no other call remains', 0, () => {
      let endedAll = false
      const signalSession = new TestSignalSession()
      const mediaController = new TrackingMediaController({
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

      expect(controller.hangup('call-a')).assertEqual(true)
      expect(mediaController.closeSessionCalls[0].preservePublish).assertEqual(true)

      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          isHangUp: true,
          commonRequest: {
            uuid: '',
            number: ''
          }
        })
      })

      expect(endedAll).assertEqual(true)
      expect(mediaController.closeAllCalls.length).assertEqual(1)
      controller.dispose()
    })

    it('keeps the last local call for an identityless c__hangup when backend reports other calls remain', 0, () => {
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

      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          isHangUp: false,
          commonRequest: {
            uuid: '',
            number: ''
          }
        })
      })

      expect(endedAll).assertEqual(false)
      expect(controller.getSession('call-a')?.sessionKey).assertEqual('call-a')
      expect(logs.some((message: string) =>
        message.indexOf('keep call page after remote hangup because other calls remain') >= 0)).assertEqual(true)
      controller.dispose()
    })

    it('keeps multi-call sessions for an identityless c__hangup when backend reports other calls remain', 0, () => {
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
      controller.registerOutgoingSession('call-b', { number: '1111' }, RtcCallMode.AUDIO)

      signalSession.emitMessage({
        eventName: 'c__hangup',
        data: JSON.stringify({
          isHangUp: false,
          isAll: true,
          commonRequest: {
            uuid: '',
            number: ''
          }
        })
      })

      expect(endedAll).assertEqual(false)
      expect(controller.getSession('call-a')?.sessionKey).assertEqual('call-a')
      expect(controller.getSession('call-b')?.sessionKey).assertEqual('call-b')
      controller.dispose()
    })

    it('does not keep the last call for c__offline even if isHangUp is false', 0, () => {
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
          isHangUp: false,
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
          isHangUp: false,
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
          isHangUp: false,
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
