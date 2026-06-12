import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode, RtcCallState, RtcHostPhase } from '../src/main/ets/model/RtcCallConfig'
import { RtcCallDirection, RtcCallViewPhase, RtcCallViewState } from '../src/main/ets/model/RtcCallViewState'
import {
  RTC_CALL_CONTROL_ACTION_HANGUP,
  RTC_CALL_CONTROL_ACTION_HOLD,
  RTC_CALL_CONTROL_ACTION_RESUME,
  RtcDefaultCallService,
  RtcDefaultCallServiceHandlers
} from '../src/main/ets/core/RtcDefaultCallService'
import {
  RTC_CALL_CONTROL_SOURCE_HANDSET,
  RtcCallControlCommandCodec
} from '../src/main/ets/core/RtcCallControlCommand'

function createService(handlers?: RtcDefaultCallServiceHandlers): RtcDefaultCallService {
  const service = new RtcDefaultCallService({
    handlers,
    idFactory: () => 'call-1'
  })
  service.configure({
    registerAddress: 'wss://rtc.example.com',
    local: {
      number: '1001',
      displayName: 'Local',
      clientType: 'client'
    },
    autoAnswer: false
  })
  return service
}

export default function rtcDefaultCallServiceTest() {
  describe('RtcDefaultCallService', () => {
    it('starts outgoing call and updates session/view state', 0, async () => {
      let started = false
      const service = createService({
        async onStartCall(_target, _mode, _session, _route) {
          started = true
        }
      })

      await service.startCall({ number: '1002', displayName: 'Remote' }, RtcCallMode.AUDIO)
      const session = service.getSession()
      const viewState = service.getViewState()

      expect(started).assertEqual(true)
      expect(session.requestId).assertEqual('call-1')
      expect(session.state).assertEqual(RtcCallState.CALLING)
      expect(session.hostPhase).assertEqual(RtcHostPhase.OUTGOING_READY)
      expect(session.active).assertEqual(true)
      expect(viewState.phase).assertEqual(RtcCallViewPhase.OUTGOING)
      expect(viewState.direction).assertEqual(RtcCallDirection.OUTGOING)
      expect(viewState.canHangup).assertEqual(true)
    })

    it('receives incoming call and accepts it', 0, async () => {
      let accepted = false
      const service = createService({
        async onAcceptCall(_session, _command) {
          accepted = true
        }
      })

      await service.receiveIncomingCall({
        callId: 'incoming-1',
        target: { number: '1002', displayName: 'Remote' },
        mode: RtcCallMode.AUDIO
      })
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.INCOMING)
      expect(service.getViewState().canAccept).assertEqual(true)

      await service.acceptCall()

      expect(accepted).assertEqual(true)
      expect(service.getSession().state).assertEqual(RtcCallState.CONNECTED)
      expect(service.getSession().hostPhase).assertEqual(RtcHostPhase.MEDIA_ACTIVE)
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.CONNECTING)
      expect(service.getViewState().canAccept).assertEqual(false)
    })

    it('auto accepts incoming call when requested', 0, async () => {
      let acceptCount = 0
      const service = createService({
        async onAcceptCall(_session, _command) {
          acceptCount += 1
        }
      })

      await service.receiveIncomingCall({
        callId: 'incoming-auto',
        target: { number: '1002' },
        autoAnswer: true
      })

      expect(acceptCount).assertEqual(1)
      expect(service.getSession().state).assertEqual(RtcCallState.CONNECTED)
      expect(service.getViewState().canAccept).assertEqual(false)
    })

    it('queues another incoming call without replacing active media session', 0, async () => {
      const service = createService()
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001', displayName: '1床' }
      })
      await service.acceptCall()
      service.markConnected()

      await service.receiveIncomingCall({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002', displayName: '2床' }
      })

      expect(service.getSession().requestId).assertEqual('bed-1')
      expect(service.getSession().uid).assertEqual('uid-1')
      expect(service.getSession().hostPhase).assertEqual(RtcHostPhase.MEDIA_ACTIVE)
      expect(service.getIncomingCalls().pendingCount).assertEqual(1)
      expect(service.getIncomingCalls().calls.length).assertEqual(2)
    })

    it('builds per-call list actions for accepted and pending bedside calls', 0, async () => {
      const service = createService()
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001', displayName: '1床' }
      })
      await service.acceptCall()
      service.markConnected()

      await service.receiveIncomingCall({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002', displayName: '2床' }
      })

      const items = service.getCallListItems()
      const first = items.find(item => item.uid === 'uid-1')
      const second = items.find(item => item.uid === 'uid-2')
      expect(first?.phase).assertEqual(RtcCallViewPhase.CONNECTED)
      expect(first?.canAccept).assertEqual(false)
      expect(first?.canHold).assertEqual(true)
      expect(second?.phase).assertEqual(RtcCallViewPhase.INCOMING)
      expect(second?.canAccept).assertEqual(true)
      expect(second?.canHold).assertEqual(false)
    })

    it('selects a pending bedside call without changing its accept state', 0, async () => {
      const service = createService()
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001' }
      })
      await service.acceptCall()
      service.markConnected()
      await service.receiveIncomingCall({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002' }
      })

      expect(service.selectCall('uid-2')).assertEqual(true)
      const selected = service.getCallListItems().find(item => item.uid === 'uid-2')

      expect(selected?.isSelected).assertEqual(true)
      expect(selected?.phase).assertEqual(RtcCallViewPhase.INCOMING)
      expect(selected?.canAccept).assertEqual(true)
      expect(service.getIncomingCalls().pendingCount).assertEqual(1)
    })

    it('terminates a pending call by uid without clearing the active call', 0, async () => {
      let terminatedUid = ''
      const service = createService({
        async onTerminateCall(session, _reason) {
          terminatedUid = session.uid
        }
      })
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001' }
      })
      await service.acceptCall()
      service.markConnected()
      await service.receiveIncomingCall({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002' }
      })

      await service.terminateCallById('uid-2', 'hangup second')

      expect(terminatedUid).assertEqual('uid-2')
      expect(service.getSession().uid).assertEqual('uid-1')
      expect(service.getSession().active).assertEqual(true)
      expect(service.getCallListItems().find(item => item.uid === 'uid-1')?.phase).assertEqual(RtcCallViewPhase.CONNECTED)
      expect(service.getCallListItems().find(item => item.uid === 'uid-2')?.phase).assertEqual(RtcCallViewPhase.ENDED)
    })

    it('terminates the active call by uid and switches to another pending call', 0, async () => {
      const service = createService()
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001' }
      })
      await service.acceptCall()
      service.markConnected()
      await service.receiveIncomingCall({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002' }
      })

      await service.terminateCallById('uid-1', 'hangup first')

      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.INCOMING)
      expect(service.getSession().uid).assertEqual('uid-2')
      expect(service.getSession().active).assertEqual(true)
      expect(service.getCallListItems().find(item => item.uid === 'uid-1')?.phase).assertEqual(RtcCallViewPhase.ENDED)
      expect(service.getCallListItems().find(item => item.uid === 'uid-2')?.phase).assertEqual(RtcCallViewPhase.INCOMING)
      expect(service.getIncomingCalls().pendingCount).assertEqual(1)
    })

    it('terminates all calls through an explicit all-hangup path', 0, async () => {
      let terminatedCount = 0
      const service = createService({
        async onTerminateAllCalls(sessions, _reason) {
          terminatedCount = sessions.length
        }
      })
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001' }
      })
      await service.acceptCall()
      service.markConnected()
      await service.receiveIncomingCall({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002' }
      })

      await service.terminateAllCalls('handset down')

      expect(terminatedCount).assertEqual(2)
      expect(service.getIncomingCalls().calls.length).assertEqual(0)
      expect(service.getSession().active).assertEqual(false)
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.HIDDEN)
    })

    it('holds and resumes an active call by uid', 0, async () => {
      let holdCount = 0
      let resumeCount = 0
      const service = createService({
        async onHoldCall(_session, _command) {
          holdCount += 1
        },
        async onResumeCall(_session, _command) {
          resumeCount += 1
        }
      })
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001' }
      })
      await service.acceptCall()

      await service.holdCallById('uid-1')
      expect(service.getSession().isHold).assertEqual('true')
      expect(service.getCallSessions().sessions[0].isHold).assertEqual(true)
      expect(holdCount).assertEqual(1)

      await service.resumeCallById('uid-1')
      expect(service.getSession().isHold).assertEqual('false')
      expect(service.getCallSessions().sessions[0].isHold).assertEqual(false)
      expect(resumeCount).assertEqual(1)
    })

    it('applies remote hold state without invoking local hold handlers', 0, async () => {
      let holdCount = 0
      const service = createService({
        async onHoldCall(_session, _command) {
          holdCount += 1
        }
      })
      await service.receiveIncomingCall({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001' }
      })
      await service.acceptCall()

      expect(service.applyHoldStateById('uid-1', true)).assertEqual(true)
      expect(service.getSession().isHold).assertEqual('true')
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.HELD)
      expect(holdCount).assertEqual(0)
    })

    it('dispatches hold and resume control commands', 0, async () => {
      const service = createService()
      await service.receiveIncomingCall({
        callId: 'incoming-1',
        target: { number: '1002' }
      })
      await service.acceptCall()
      service.markConnected()

      const hold = await service.handleControlCommand(
        RtcCallControlCommandCodec.build(RTC_CALL_CONTROL_ACTION_HOLD, 1, RTC_CALL_CONTROL_SOURCE_HANDSET, 1000)
      )
      expect(hold.handled).assertEqual(true)
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.HELD)

      const resume = await service.handleControlCommand(
        RtcCallControlCommandCodec.build(RTC_CALL_CONTROL_ACTION_RESUME, 2, RTC_CALL_CONTROL_SOURCE_HANDSET, 1001)
      )
      expect(resume.handled).assertEqual(true)
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.CONNECTED)
    })

    it('dispatches hangup command and emits terminal state', 0, async () => {
      let terminatedReason = ''
      const states: RtcCallViewState[] = []
      const service = createService({
        async onTerminateCall(_session, reason) {
          terminatedReason = reason
        }
      })
      service.onViewStateChange((state: RtcCallViewState) => {
        states.push(state)
      })
      await service.startCall({ number: '1002' }, RtcCallMode.AUDIO)

      const result = await service.handleControlCommand(
        RtcCallControlCommandCodec.build(RTC_CALL_CONTROL_ACTION_HANGUP, 1, '', 1000)
      )

      expect(result.handled).assertEqual(true)
      expect(terminatedReason).assertEqual('command:hangup')
      expect(service.getSession().active).assertEqual(false)
      expect(service.getViewState().phase).assertEqual(RtcCallViewPhase.HIDDEN)
      expect(states.length > 0).assertEqual(true)
    })
  })
}
