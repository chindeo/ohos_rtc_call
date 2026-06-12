import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcDefaultCallService } from '../src/main/ets/core/RtcDefaultCallService'
import {
  RtcHostMultiCallController
} from '../src/main/ets/core/RtcHostMultiCallController'

export default function rtcHostMultiCallControllerTest() {
  describe('RtcHostMultiCallController', () => {
    it('keeps two incoming calls isolated and exposes one active call', 0, async () => {
      const service = new RtcDefaultCallService()
      const controller = new RtcHostMultiCallController({ service })

      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101', displayName: '床旁1' },
        mode: RtcCallMode.AUDIO
      })
      await controller.receiveIncomingCall({
        callId: 'call-b',
        uid: 'uid-b',
        target: { number: '1111', displayName: '床旁2' },
        mode: RtcCallMode.VIDEO
      })

      const model = controller.getUiModel()
      expect(model.activeCall?.sessionKey).assertEqual('uid-a')
      expect(model.sideCalls.length).assertEqual(1)
      expect(model.sideCalls[0].sessionKey).assertEqual('uid-b')
      expect(model.showHangupAll).assertEqual(true)
      controller.dispose()
    })

    it('blocks a missing session key when multiple calls exist', 0, async () => {
      const service = new RtcDefaultCallService()
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })
      await controller.receiveIncomingCall({
        callId: 'call-b',
        uid: 'uid-b',
        target: { number: '1111' }
      })

      const result = await controller.hangup()

      expect(result.handled).assertEqual(false)
      expect(result.reason).assertEqual('ambiguous session key')
      expect(controller.getUiModel().sideCalls.length).assertEqual(1)
      controller.dispose()
    })

    it('enables accept only after publish answer is ready', 0, async () => {
      let accepted = 0
      const service = new RtcDefaultCallService({
        handlers: {
          onAcceptCall: async () => {
            accepted += 1
          }
        }
      })
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })

      expect(controller.getUiModel().activeCall?.canAccept).assertEqual(false)
      expect((await controller.accept('uid-a')).handled).assertEqual(false)

      controller.setCallAnswerReady('uid-a', true)
      expect(controller.getUiModel().activeCall?.canAccept).assertEqual(true)
      expect((await controller.accept('uid-a')).handled).assertEqual(true)
      expect(accepted).assertEqual(1)
      controller.dispose()
    })

    it('resolves publish answer aliases to the registered incoming session', 0, async () => {
      const service = new RtcDefaultCallService()
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })

      controller.setCallAnswerReady('sdp-session-a', true, ['call-a'], '1101')

      expect(controller.getUiModel().activeCall?.sessionKey).assertEqual('uid-a')
      expect(controller.getUiModel().activeCall?.canAccept).assertEqual(true)
      controller.dispose()
    })

    it('selects a side call without changing either call phase', 0, async () => {
      const service = new RtcDefaultCallService()
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })
      controller.setCallAnswerReady('uid-a', true)
      await controller.accept('uid-a')
      controller.markConnected('uid-a')
      await controller.receiveIncomingCall({
        callId: 'call-b',
        uid: 'uid-b',
        target: { number: '1111' }
      })

      const result = controller.select('uid-b')
      const model = controller.getUiModel()

      expect(result.handled).assertEqual(true)
      expect(model.activeCall?.sessionKey).assertEqual('uid-b')
      expect(model.activeCall?.phase).assertEqual('incoming')
      expect(model.sideCalls[0].sessionKey).assertEqual('uid-a')
      expect(model.sideCalls[0].phase).assertEqual('connected')
      controller.dispose()
    })

    it('hangs up one session without clearing another session', 0, async () => {
      const terminated: string[] = []
      const service = new RtcDefaultCallService({
        handlers: {
          onTerminateCall: async (session) => {
            terminated.push(session.uid)
          }
        }
      })
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })
      await controller.receiveIncomingCall({
        callId: 'call-b',
        uid: 'uid-b',
        target: { number: '1111' }
      })

      const result = await controller.hangup('uid-b')
      const model = controller.getUiModel()

      expect(result.handled).assertEqual(true)
      expect(terminated.length).assertEqual(1)
      expect(terminated[0]).assertEqual('uid-b')
      expect(model.activeCall?.sessionKey).assertEqual('uid-a')
      expect(model.sideCalls.length).assertEqual(0)
      controller.dispose()
    })

    it('hangs up all sessions only through explicit all action', 0, async () => {
      let terminatedCount = 0
      const service = new RtcDefaultCallService({
        handlers: {
          onTerminateAllCalls: async (sessions) => {
            terminatedCount = sessions.length
          }
        }
      })
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })
      await controller.receiveIncomingCall({
        callId: 'call-b',
        uid: 'uid-b',
        target: { number: '1111' }
      })

      const result = await controller.hangupAll()

      expect(result.handled).assertEqual(true)
      expect(terminatedCount).assertEqual(2)
      expect(controller.getUiModel().visible).assertEqual(false)
      controller.dispose()
    })

    it('applies remote hold to only the target session', 0, async () => {
      const service = new RtcDefaultCallService()
      const controller = new RtcHostMultiCallController({ service })
      await controller.receiveIncomingCall({
        callId: 'call-a',
        uid: 'uid-a',
        target: { number: '1101' }
      })
      await controller.receiveIncomingCall({
        callId: 'call-b',
        uid: 'uid-b',
        target: { number: '1111' }
      })
      service.applyHoldStateById('uid-a', false)
      service.applyHoldStateById('uid-b', false)

      const result = controller.applyRemoteHold('uid-b', true)
      const model = controller.getUiModel()

      expect(result.handled).assertEqual(true)
      expect(model.activeCall?.isHold).assertEqual(false)
      expect(model.sideCalls[0].isHold).assertEqual(true)
      controller.dispose()
    })

    it('tracks outgoing calls in the same session list', 0, async () => {
      let nextId = 0
      const service = new RtcDefaultCallService({
        idFactory: () => {
          nextId += 1
          return 'outgoing-' + nextId
        }
      })
      service.configure({
        registerAddress: 'ws://test',
        local: { number: '1000' }
      })
      const controller = new RtcHostMultiCallController({ service })

      await controller.startCall({ number: '1101' }, RtcCallMode.AUDIO)

      expect(controller.getUiModel().activeCall?.sessionKey).assertEqual('outgoing-1')
      expect(controller.getUiModel().activeCall?.canAccept).assertEqual(false)
      controller.dispose()
    })
  })
}
