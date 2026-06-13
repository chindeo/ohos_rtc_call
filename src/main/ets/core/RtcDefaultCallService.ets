import {
  RtcCallMode,
  RtcPeerIdentity,
  RtcCallSession,
  RtcCallState,
  RtcHostPhase
} from '../model/RtcCallConfig'
import {
  RtcCallDirection,
  RtcCallViewPeer,
  RtcCallViewPhase,
  RtcCallViewState,
  RtcCallViewStateListener
} from '../model/RtcCallViewState'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcCallRoute, RtcCallRouteResolver } from './RtcCallRouteResolver'
import {
  RtcCallControlCommand,
  RtcCallControlCommandCodec
} from './RtcCallControlCommand'
import {
  RtcCallPrepareResult,
  RtcCallRefreshOptions,
  RtcCallRuntimeConfig,
  RtcCallService,
  RtcCallTarget,
  RtcCallUnsubscribe
} from './RtcCallService'
import {
  RtcIncomingCallQueue,
  RtcIncomingCallQueueListener,
  RtcIncomingCallQueueSnapshot,
  RtcIncomingCallRecord
} from './RtcIncomingCallQueue'
import { RtcCallSessionStore, RtcCallSessionStoreSnapshot } from './RtcCallSessionStore'

export const RTC_CALL_CONTROL_ACTION_ACCEPT = 'accept'
export const RTC_CALL_CONTROL_ACTION_ANSWER = 'answer'
export const RTC_CALL_CONTROL_ACTION_HANGUP = 'hangup'
export const RTC_CALL_CONTROL_ACTION_TERMINATE = 'terminate'
export const RTC_CALL_CONTROL_ACTION_HOLD = 'hold'
export const RTC_CALL_CONTROL_ACTION_RESUME = 'resume'
export const RTC_CALL_CONTROL_ACTION_TOGGLE_HOLD = 'toggleHold'

export interface RtcDefaultCallServiceHandlers {
  onPrepare?(route: RtcCallRoute, config: RtcCallRuntimeConfig, reason: string): Promise<void>
  onStartCall?(target: RtcCallTarget, mode: RtcCallMode, session: RtcCallSession, route: RtcCallRoute): Promise<void>
  onAcceptCall?(session: RtcCallSession, command?: RtcCallControlCommand): Promise<void>
  onTerminateCall?(session: RtcCallSession, reason: string): Promise<void>
  onTerminateAllCalls?(sessions: RtcCallSession[], reason: string): Promise<void>
  onHoldCall?(session: RtcCallSession, command?: RtcCallControlCommand): Promise<void>
  onResumeCall?(session: RtcCallSession, command?: RtcCallControlCommand): Promise<void>
  onStateChange?(session: RtcCallSession, viewState: RtcCallViewState): void
}

export interface RtcDefaultCallServiceOptions {
  handlers?: RtcDefaultCallServiceHandlers
  idFactory?: () => string
  incomingQueue?: RtcIncomingCallQueue
  sessionStore?: RtcCallSessionStore
}

export interface RtcIncomingCallOptions {
  callId?: string
  uid?: string
  from?: string
  to?: string
  status?: string
  isHold?: boolean
  target: RtcCallTarget
  mode?: RtcCallMode
  autoAnswer?: boolean
}

export interface RtcAcceptIncomingCallOptions {
  focus?: boolean
}

export interface RtcCallCommandResult {
  handled: boolean
  reason: string
  command: RtcCallControlCommand
}

export class RtcCallListItem {
  key: string = ''
  callId: string = ''
  uid: string = ''
  sessionKey: string = ''
  peerNumber: string = ''
  displayName: string = ''
  direction: RtcCallDirection = RtcCallDirection.NONE
  phase: RtcCallViewPhase = RtcCallViewPhase.HIDDEN
  status: string = ''
  isHold: boolean = false
  isActive: boolean = false
  isSelected: boolean = false
  canAccept: boolean = false
  canHold: boolean = false
  canResume: boolean = false
  canHangup: boolean = false
  mode: RtcCallMode = RtcCallMode.AUDIO
  receivedAt: number = 0
  connectedAt: number = 0
  target: RtcCallTarget = { number: '' }
}

export class RtcDefaultCallService implements RtcCallService {
  private config?: RtcCallRuntimeConfig
  private route?: RtcCallRoute
  private session: RtcCallSession = new RtcCallSession()
  private viewState: RtcCallViewState = new RtcCallViewState()
  private listeners: RtcCallViewStateListener[] = []
  private handlers?: RtcDefaultCallServiceHandlers
  private idFactory: () => string
  private incomingQueue: RtcIncomingCallQueue
  private sessionStore: RtcCallSessionStore

  constructor(options?: RtcDefaultCallServiceOptions) {
    this.handlers = options?.handlers
    this.idFactory = options?.idFactory || (() => `${Date.now()}`)
    this.incomingQueue = options?.incomingQueue || new RtcIncomingCallQueue()
    this.sessionStore = options?.sessionStore || new RtcCallSessionStore()
  }

  configure(config: RtcCallRuntimeConfig): void {
    this.config = config
    this.route = RtcCallRouteResolver.resolve(config)
    this.viewState.protocol = config.protocol || this.route.protocol
    this.viewState.local = RtcDefaultCallService.toViewPeerFromIdentity(config.local)
    this.viewState.autoAnswer = config.autoAnswer === true
    this.session.localNumber = config.local.number
    this.session.displayName = config.local.displayName || ''
    this.session.clientType = config.local.clientType || ''
    this.session.ip = config.local.ip || ''
    this.session.identity = config.local.identity || ''
    this.session.locId = config.local.locId || ''
    this.session.hospitalId = config.local.hospitalId || ''
    this.session.isAutoAnswer = config.autoAnswer === true ? 'true' : 'false'
    this.emitState()
  }

  async prepare(reason: string = 'prepare'): Promise<RtcCallPrepareResult> {
    const route = this.ensureRoute()
    const previous = this.viewState.phase
    this.session.state = RtcCallState.PREPARING
    this.session.hostPhase = RtcHostPhase.STANDBY_READY
    this.session.active = false
    this.session.visible = false
    this.viewState.phase = RtcCallViewPhase.HIDDEN
    this.viewState.visible = false
    this.viewState.registered = true
    this.viewState.registrationErrorMessage = ''
    this.emitState()
    if (this.config) {
      await this.handlers?.onPrepare?.(route, this.config, reason)
    }
    this.session.state = RtcCallState.REGISTERING
    this.emitState()
    return {
      route,
      viewState: this.copyViewState(),
      changed: previous !== this.viewState.phase,
      reason
    }
  }

  async startCall(target: RtcCallTarget, mode: RtcCallMode): Promise<void> {
    const route = this.ensureRoute()
    this.resetForNewCall(this.idFactory(), target, mode)
    this.sessionStore.upsert({
      uid: this.session.requestId,
      peerNumber: target.number,
      displayName: target.displayName,
      status: 'outgoing',
      isHold: false,
      mode,
      target
    })
    this.incomingQueue.upsert({
      callId: this.session.requestId,
      uid: this.session.requestId,
      peerNumber: target.number,
      sessionKey: this.session.requestId,
      target,
      mode,
      direction: RtcCallDirection.OUTGOING,
      phase: 'outgoing',
      status: 'outgoing'
    })
    this.session.state = RtcCallState.CALLING
    this.session.hostPhase = RtcHostPhase.OUTGOING_READY
    this.session.active = true
    this.session.visible = true
    this.session.pendingTrigger = true
    this.viewState.visible = true
    this.viewState.phase = RtcCallViewPhase.OUTGOING
    this.viewState.direction = RtcCallDirection.OUTGOING
    this.viewState.canAccept = false
    this.viewState.canHangup = true
    this.emitState()
    await this.handlers?.onStartCall?.(target, mode, this.copySession(), route)
  }

  async receiveIncomingCall(options: RtcIncomingCallOptions): Promise<void> {
    const callId = options.callId || this.idFactory()
    const mode = options.mode || RtcCallMode.AUDIO
    const uid = options.uid || callId
    const stored = this.sessionStore.upsert({
      uid,
      peerNumber: options.target.number,
      displayName: options.target.displayName,
      from: options.from,
      to: options.to,
      status: options.status || 'incoming',
      isHold: options.isHold === true,
      mode,
      target: options.target
    })
    const incoming = this.incomingQueue.upsert({
      callId,
      uid,
      peerNumber: options.target.number,
      sessionKey: stored?.uid || uid,
      target: options.target,
      mode,
      autoAnswer: options.autoAnswer,
      isHold: options.isHold,
      direction: RtcCallDirection.INCOMING,
      status: options.status || 'incoming'
    })
    const mediaBusy = this.session.active && this.session.hostPhase === RtcHostPhase.MEDIA_ACTIVE
    const hasActiveVisibleSession = this.session.active && this.session.visible
    if ((mediaBusy || hasActiveVisibleSession) && options.autoAnswer !== true && !this.viewState.autoAnswer) {
      this.emitState()
      return
    }
    this.activateIncomingCall(incoming)
    this.emitState()
    if (options.autoAnswer === true || this.viewState.autoAnswer) {
      await this.acceptCall()
    }
  }

  async acceptIncomingCall(
    callIdOrUid: string,
    command?: RtcCallControlCommand,
    options?: RtcAcceptIncomingCallOptions
  ): Promise<void> {
    const shouldFocus = options?.focus !== false
    const incoming = this.incomingQueue.accept(callIdOrUid, { focus: shouldFocus })
    if (!incoming) {
      return
    }
    if (incoming.uid) {
      this.sessionStore.upsert({
        uid: incoming.uid,
        peerNumber: incoming.peerNumber || incoming.target.number,
        displayName: incoming.target.displayName,
        status: 'accepted',
        isHold: false,
        mode: incoming.mode,
        target: incoming.target
      })
    }
    if (!shouldFocus) {
      await this.handlers?.onAcceptCall?.(this.toSessionFromRecord(incoming, false), command)
      return
    }
    if (this.session.requestId !== incoming.callId) {
      this.activateIncomingCall(incoming)
    }
    await this.acceptCall(command)
  }

  async acceptCall(command?: RtcCallControlCommand): Promise<void> {
    if (!this.session.active) {
      return
    }
    this.session.state = RtcCallState.CONNECTED
    this.session.hostPhase = RtcHostPhase.MEDIA_ACTIVE
    this.session.visible = true
    this.session.pendingTrigger = false
    this.session.isHold = 'false'
    this.incomingQueue.accept(this.session.requestId)
    this.sessionStore.upsert({
      uid: this.session.uid || this.session.requestId,
      peerNumber: this.session.calleeNumber,
      displayName: this.session.displayName,
      status: 'accepted',
      isHold: false,
      mode: this.session.mode,
      target: RtcDefaultCallService.toTargetFromSession(this.session)
    })
    this.viewState.visible = true
    this.viewState.phase = RtcCallViewPhase.CONNECTING
    this.viewState.canAccept = false
    this.viewState.canHangup = true
    this.emitState()
    await this.handlers?.onAcceptCall?.(this.copySession(), command)
  }

  markConnected(): void {
    if (!this.session.active) {
      return
    }
    this.session.state = RtcCallState.CONNECTED
    this.session.hostPhase = RtcHostPhase.MEDIA_ACTIVE
    this.session.isHold = 'false'
    this.session.pendingTrigger = false
    this.incomingQueue.markConnected(
      this.session.uid || this.session.requestId || this.session.calleeNumber
    )
    this.sessionStore.upsert({
      uid: this.session.uid || this.session.requestId,
      peerNumber: this.session.calleeNumber,
      displayName: this.session.displayName,
      status: 'accepted',
      isHold: false,
      mode: this.session.mode,
      target: RtcDefaultCallService.toTargetFromSession(this.session)
    })
    this.viewState.phase = RtcCallViewPhase.CONNECTED
    this.viewState.canAccept = false
    this.viewState.canHangup = true
    this.emitState()
  }

  markConnectedById(callIdOrUid: string): boolean {
    if (this.isCurrentCall(callIdOrUid)) {
      this.markConnected()
      return true
    }
    const incoming = this.incomingQueue.getCall(callIdOrUid)
    if (!incoming || incoming.phase === 'ended') {
      return false
    }
    this.incomingQueue.markConnected(callIdOrUid, Date.now(), { focus: false })
    this.sessionStore.upsert({
      uid: incoming.uid || incoming.callId,
      peerNumber: incoming.peerNumber || incoming.target.number,
      displayName: incoming.target.displayName,
      status: 'accepted',
      isHold: false,
      mode: incoming.mode,
      target: incoming.target
    })
    this.emitState()
    return true
  }

  async holdCall(command?: RtcCallControlCommand): Promise<void> {
    if (!this.session.active) {
      return
    }
    this.session.hostPhase = RtcHostPhase.MEDIA_ACTIVE
    this.session.isHold = 'true'
    this.viewState.phase = RtcCallViewPhase.HELD
    this.viewState.canAccept = false
    this.viewState.canHangup = true
    this.incomingQueue.markHold(this.session.uid || this.session.requestId || this.session.calleeNumber, true)
    this.sessionStore.markHold(this.session.uid || this.session.requestId || this.session.calleeNumber, true)
    this.emitState()
    await this.handlers?.onHoldCall?.(this.copySession(), command)
  }

  async resumeCall(command?: RtcCallControlCommand): Promise<void> {
    if (!this.session.active) {
      return
    }
    this.session.hostPhase = RtcHostPhase.MEDIA_ACTIVE
    this.session.isHold = 'false'
    this.viewState.phase = RtcCallViewPhase.CONNECTED
    this.viewState.canAccept = false
    this.viewState.canHangup = true
    this.incomingQueue.markHold(this.session.uid || this.session.requestId || this.session.calleeNumber, false)
    this.sessionStore.markHold(this.session.uid || this.session.requestId || this.session.calleeNumber, false)
    this.emitState()
    await this.handlers?.onResumeCall?.(this.copySession(), command)
  }

  async holdCallById(callIdOrUid: string, command?: RtcCallControlCommand): Promise<void> {
    if (this.isCurrentCall(callIdOrUid)) {
      await this.holdCall(command)
      return
    }
    const incoming = this.incomingQueue.getCall(callIdOrUid)
    if (!incoming || incoming.phase !== 'accepted') {
      return
    }
    this.incomingQueue.markHold(callIdOrUid, true)
    this.sessionStore.markHold(callIdOrUid, true)
    this.emitState()
    await this.handlers?.onHoldCall?.(this.toSessionFromRecord(incoming, true), command)
  }

  async resumeCallById(callIdOrUid: string, command?: RtcCallControlCommand): Promise<void> {
    if (this.isCurrentCall(callIdOrUid)) {
      await this.resumeCall(command)
      return
    }
    const incoming = this.incomingQueue.getCall(callIdOrUid)
    if (!incoming || incoming.phase !== 'accepted') {
      return
    }
    this.incomingQueue.markHold(callIdOrUid, false)
    this.sessionStore.markHold(callIdOrUid, false)
    this.emitState()
    await this.handlers?.onResumeCall?.(this.toSessionFromRecord(incoming, false), command)
  }

  applyHoldStateById(callIdOrUid: string, isHold: boolean): boolean {
    const incoming = this.incomingQueue.getCall(callIdOrUid)
    if (!incoming || incoming.phase === 'ended') {
      return false
    }
    if (incoming.phase === 'incoming') {
      this.incomingQueue.accept(callIdOrUid)
    }
    this.incomingQueue.markHold(callIdOrUid, isHold)
    this.sessionStore.upsert({
      uid: incoming.uid || incoming.callId,
      peerNumber: incoming.peerNumber || incoming.target.number,
      displayName: incoming.target.displayName,
      status: 'accepted',
      isHold,
      mode: incoming.mode,
      target: incoming.target
    })
    if (this.isCurrentCall(callIdOrUid) || this.isCurrentCall(incoming.callId) ||
      this.isCurrentCall(incoming.uid)) {
      this.session.state = RtcCallState.CONNECTED
      this.session.hostPhase = RtcHostPhase.MEDIA_ACTIVE
      this.session.isHold = isHold ? 'true' : 'false'
      this.session.pendingTrigger = false
      this.viewState.phase = isHold ? RtcCallViewPhase.HELD : RtcCallViewPhase.CONNECTED
      this.viewState.canAccept = false
      this.viewState.canHangup = true
    }
    this.emitState()
    return true
  }

  async terminateCall(reason: string = 'terminate'): Promise<void> {
    if (!this.session.active && this.viewState.phase === RtcCallViewPhase.HIDDEN) {
      return
    }
    const previousSession = this.copySession()
    if (previousSession.requestId) {
      this.incomingQueue.end(previousSession.requestId, reason)
    }
    if (previousSession.uid) {
      this.sessionStore.removeUid(previousSession.uid)
    } else if (previousSession.calleeNumber) {
      this.sessionStore.removePeer(previousSession.calleeNumber)
    }
    this.session.state = RtcCallState.ENDED
    this.session.hostPhase = RtcHostPhase.TEARING_DOWN
    this.session.active = false
    this.session.pendingTrigger = false
    this.session.visible = false
    this.viewState.visible = false
    this.viewState.phase = RtcCallViewPhase.ENDED
    this.viewState.canAccept = false
    this.viewState.canHangup = false
    this.emitState()
    await this.handlers?.onTerminateCall?.(previousSession, reason)
    this.session.hostPhase = RtcHostPhase.IDLE
    this.viewState.phase = RtcCallViewPhase.HIDDEN
    this.viewState.direction = RtcCallDirection.NONE
    this.emitState()
  }

  async terminateCallById(callIdOrUid: string, reason: string = 'terminate'): Promise<void> {
    if (this.isCurrentCall(callIdOrUid)) {
      await this.terminateCurrentCallAndSelectNext(reason)
      return
    }
    const incoming = this.incomingQueue.getCall(callIdOrUid)
    if (!incoming) {
      return
    }
    this.incomingQueue.end(callIdOrUid, reason)
    if (incoming.uid) {
      this.sessionStore.removeUid(incoming.uid)
    } else if (incoming.peerNumber || incoming.target.number) {
      this.sessionStore.removePeer(incoming.peerNumber || incoming.target.number)
    }
    this.emitState()
    await this.handlers?.onTerminateCall?.(this.toSessionFromRecord(incoming, incoming.isHold), reason)
  }

  async terminateAllCalls(reason: string = 'terminate all'): Promise<void> {
    const snapshot = this.incomingQueue.getSnapshot()
    const sessions: RtcCallSession[] = []
    snapshot.calls
      .filter((record: RtcIncomingCallRecord) => record.phase !== 'ended')
      .forEach((record: RtcIncomingCallRecord) => {
        sessions.push(this.toSessionFromRecord(record, record.isHold))
      })
    if (this.session.active && !snapshot.calls.some((record: RtcIncomingCallRecord) => this.isCurrentCall(record.callId))) {
      sessions.push(this.copySession())
    }
    this.incomingQueue.clear()
    this.sessionStore.clear()
    this.session.state = RtcCallState.ENDED
    this.session.hostPhase = RtcHostPhase.IDLE
    this.session.active = false
    this.session.pendingTrigger = false
    this.session.visible = false
    this.viewState.visible = false
    this.viewState.phase = RtcCallViewPhase.HIDDEN
    this.viewState.direction = RtcCallDirection.NONE
    this.viewState.canAccept = false
    this.viewState.canHangup = false
    this.emitState()
    await this.handlers?.onTerminateAllCalls?.(sessions, reason)
  }

  failCall(message: string): void {
    if (this.session.requestId) {
      this.incomingQueue.end(this.session.requestId, message)
    }
    this.session.state = RtcCallState.FAILED
    this.session.hostPhase = RtcHostPhase.TEARING_DOWN
    this.session.active = false
    this.session.pendingTrigger = false
    this.session.visible = false
    this.session.errorMessage = message
    this.viewState.visible = false
    this.viewState.phase = RtcCallViewPhase.ERROR
    this.viewState.errorMessage = message
    this.viewState.canAccept = false
    this.viewState.canHangup = false
    this.emitState()
  }

  async refreshConfig(config: RtcCallRuntimeConfig, options: RtcCallRefreshOptions): Promise<RtcCallPrepareResult> {
    this.configure(config)
    return this.prepare(options.reason)
  }

  async handleControlCommand(value: string): Promise<RtcCallCommandResult> {
    const command = RtcCallControlCommandCodec.parse(value)
    return this.dispatchControlCommand(command)
  }

  async dispatchControlCommand(command: RtcCallControlCommand): Promise<RtcCallCommandResult> {
    const action = command.action
    if (action === RTC_CALL_CONTROL_ACTION_ACCEPT || action === RTC_CALL_CONTROL_ACTION_ANSWER) {
      await this.acceptCall(command)
      return { handled: true, reason: 'accepted', command }
    }
    if (action === RTC_CALL_CONTROL_ACTION_HANGUP || action === RTC_CALL_CONTROL_ACTION_TERMINATE) {
      await this.terminateCall('command:' + action)
      return { handled: true, reason: 'terminated', command }
    }
    if (action === RTC_CALL_CONTROL_ACTION_HOLD) {
      await this.holdCall(command)
      return { handled: true, reason: 'held', command }
    }
    if (action === RTC_CALL_CONTROL_ACTION_RESUME) {
      await this.resumeCall(command)
      return { handled: true, reason: 'resumed', command }
    }
    if (action === RTC_CALL_CONTROL_ACTION_TOGGLE_HOLD) {
      if (this.viewState.phase === RtcCallViewPhase.HELD) {
        await this.resumeCall(command)
        return { handled: true, reason: 'resumed', command }
      }
      await this.holdCall(command)
      return { handled: true, reason: 'held', command }
    }
    return { handled: false, reason: 'unsupported action', command }
  }

  getSession(): RtcCallSession {
    return this.copySession()
  }

  getSessionById(callIdOrUid: string): RtcCallSession | undefined {
    if (this.isCurrentCall(callIdOrUid)) {
      return this.copySession()
    }
    const incoming = this.incomingQueue.getCall(callIdOrUid)
    return incoming ? this.toSessionFromRecord(incoming, incoming.isHold) : undefined
  }

  getViewState(): RtcCallViewState {
    return this.copyViewState()
  }

  getIncomingCalls(): RtcIncomingCallQueueSnapshot {
    return this.incomingQueue.getSnapshot()
  }

  getCallSessions(): RtcCallSessionStoreSnapshot {
    return this.sessionStore.snapshot()
  }

  selectCall(callIdOrUid: string): boolean {
    const selected = this.incomingQueue.select(callIdOrUid)
    if (!selected) {
      return false
    }
    this.emitState()
    return true
  }

  getCallListItems(): RtcCallListItem[] {
    const snapshot = this.incomingQueue.getSnapshot()
    return snapshot.calls.map((record: RtcIncomingCallRecord) => this.toCallListItem(record, snapshot))
  }

  onIncomingCallsChange(listener: RtcIncomingCallQueueListener): RtcCallUnsubscribe {
    return this.incomingQueue.onChange(listener)
  }

  onViewStateChange(listener: RtcCallViewStateListener): RtcCallUnsubscribe {
    this.listeners.push(listener)
    listener(this.copyViewState())
    return () => {
      this.listeners = this.listeners.filter((item: RtcCallViewStateListener) => item !== listener)
    }
  }

  dispose(): void {
    this.listeners = []
    this.config = undefined
    this.route = undefined
  }

  private ensureRoute(): RtcCallRoute {
    if (this.route) {
      return this.route
    }
    if (!this.config) {
      throw new Error('RtcDefaultCallService is not configured')
    }
    this.route = RtcCallRouteResolver.resolve(this.config)
    return this.route
  }

  private resetForNewCall(callId: string, target: RtcCallTarget, mode: RtcCallMode): void {
    this.session = new RtcCallSession()
    this.session.requestId = callId
    this.session.uid = callId
    this.session.mode = mode
    this.session.localNumber = this.config?.local.number || ''
    this.session.calleeNumber = target.number
    this.session.displayName = target.displayName || ''
    this.session.clientType = target.clientType || ''
    this.session.ip = target.ip || target.deviceIp || ''
    this.session.identity = target.identity || ''
    this.session.locId = target.locId || ''
    this.session.hospitalId = target.hospitalId || ''
    this.session.isAutoAnswer = this.config?.autoAnswer === true ? 'true' : 'false'
    this.viewState.callId = callId
    this.viewState.uid = this.session.uid
    this.viewState.mode = mode
    this.viewState.local = this.config ? RtcDefaultCallService.toViewPeerFromIdentity(this.config.local) :
      RtcDefaultCallService.emptyViewPeer()
    this.viewState.remote = RtcDefaultCallService.toViewPeerFromTarget(target)
    this.viewState.errorMessage = ''
  }

  private activateIncomingCall(incoming: RtcIncomingCallRecord): void {
    this.resetForNewCall(incoming.callId, incoming.target, incoming.mode)
    this.session.uid = incoming.uid || incoming.callId
    this.session.state = RtcCallState.RINGING
    this.session.hostPhase = RtcHostPhase.INCOMING_READY
    this.session.active = true
    this.session.visible = true
    this.session.pendingTrigger = false
    this.viewState.visible = true
    this.viewState.phase = RtcCallViewPhase.INCOMING
    this.viewState.direction = RtcCallDirection.INCOMING
    this.viewState.canAccept = true
    this.viewState.canHangup = true
    this.viewState.uid = this.session.uid
  }

  private isCurrentCall(callIdOrUid: string): boolean {
    const key = (callIdOrUid || '').trim()
    if (!key) {
      return false
    }
    return this.session.requestId === key ||
      this.session.uid === key ||
      this.session.calleeNumber === key
  }

  private toCallListItem(record: RtcIncomingCallRecord, snapshot: RtcIncomingCallQueueSnapshot): RtcCallListItem {
    const session = record.uid ? this.sessionStore.findByUid(record.uid) :
      this.sessionStore.findByPeer(record.peerNumber || record.target.number)
    const isCurrent = this.isCurrentCall(record.callId) || this.isCurrentCall(record.uid)
    const isHold = session?.isHold === true || record.isHold === true || (isCurrent && this.session.isHold === 'true')
    const phase = RtcDefaultCallService.resolveListItemPhase(record, isHold, isCurrent ? this.viewState.phase : undefined)
    const item = new RtcCallListItem()
    item.key = record.uid || record.callId || record.key
    item.callId = record.callId
    item.uid = record.uid
    item.sessionKey = record.sessionKey || record.uid || record.callId
    item.peerNumber = record.peerNumber || record.target.number
    item.displayName = record.target.displayName || session?.displayName || item.peerNumber
    item.direction = record.direction
    item.phase = phase
    item.status = session?.status || record.status
    item.isHold = isHold
    item.isActive = snapshot.activeCallId === record.callId || (this.session.active && isCurrent)
    item.isSelected = snapshot.selectedCallId === record.callId
    item.canAccept = record.phase === 'incoming'
    item.canHold = record.phase === 'accepted' && !isHold
    item.canResume = record.phase === 'accepted' && isHold
    item.canHangup = record.phase !== 'ended'
    item.mode = record.mode
    item.receivedAt = record.receivedAt
    item.connectedAt = record.connectedAt
    item.target = RtcDefaultCallService.copyTarget(record.target)
    return item
  }

  private async terminateCurrentCallAndSelectNext(reason: string): Promise<void> {
    const previousSession = this.copySession()
    if (previousSession.requestId) {
      this.incomingQueue.end(previousSession.requestId, reason)
    }
    if (previousSession.uid) {
      this.sessionStore.removeUid(previousSession.uid)
    } else if (previousSession.calleeNumber) {
      this.sessionStore.removePeer(previousSession.calleeNumber)
    }
    await this.handlers?.onTerminateCall?.(previousSession, reason)
    const next = this.findNextVisibleCall(previousSession.requestId)
    if (next) {
      this.activateIncomingCall(next)
      if (next.phase === 'accepted') {
        this.session.state = RtcCallState.CONNECTED
        this.session.hostPhase = RtcHostPhase.MEDIA_ACTIVE
        this.session.isHold = next.isHold ? 'true' : 'false'
        this.viewState.phase = next.isHold ? RtcCallViewPhase.HELD : RtcCallViewPhase.CONNECTED
        this.viewState.canAccept = false
        this.viewState.canHangup = true
      }
      this.emitState()
      return
    }
    this.session.state = RtcCallState.ENDED
    this.session.hostPhase = RtcHostPhase.IDLE
    this.session.active = false
    this.session.pendingTrigger = false
    this.session.visible = false
    this.viewState.visible = false
    this.viewState.phase = RtcCallViewPhase.HIDDEN
    this.viewState.direction = RtcCallDirection.NONE
    this.viewState.canAccept = false
    this.viewState.canHangup = false
    this.emitState()
  }

  private findNextVisibleCall(excludeCallId: string): RtcIncomingCallRecord | undefined {
    const snapshot = this.incomingQueue.getSnapshot()
    return snapshot.calls.find((record: RtcIncomingCallRecord) =>
      record.callId !== excludeCallId && record.visible && record.phase !== 'ended')
  }

  private toSessionFromRecord(record: RtcIncomingCallRecord, isHold: boolean): RtcCallSession {
    const session = new RtcCallSession()
    session.requestId = record.callId
    session.uid = record.uid || record.callId
    session.mode = record.mode
    session.state = record.phase === 'incoming' ? RtcCallState.RINGING : RtcCallState.CONNECTED
    session.hostPhase = record.phase === 'incoming' ? RtcHostPhase.INCOMING_READY : RtcHostPhase.MEDIA_ACTIVE
    session.active = record.phase !== 'ended'
    session.visible = record.visible
    session.localNumber = this.config?.local.number || ''
    session.calleeNumber = record.peerNumber || record.target.number
    session.displayName = record.target.displayName || ''
    session.clientType = record.target.clientType || ''
    session.ip = record.target.ip || record.target.deviceIp || ''
    session.identity = record.target.identity || ''
    session.locId = record.target.locId || ''
    session.hospitalId = record.target.hospitalId || ''
    session.isAutoAnswer = record.autoAnswer ? 'true' : 'false'
    session.isHold = isHold ? 'true' : 'false'
    return session
  }

  private emitState(): void {
    const snapshot = this.copyViewState()
    this.handlers?.onStateChange?.(this.copySession(), snapshot)
    this.listeners.forEach((listener: RtcCallViewStateListener) => {
      listener(this.copyViewState())
    })
  }

  private copySession(): RtcCallSession {
    const copy = new RtcCallSession()
    copy.requestId = this.session.requestId
    copy.uid = this.session.uid
    copy.mode = this.session.mode
    copy.state = this.session.state
    copy.hostPhase = this.session.hostPhase
    copy.active = this.session.active
    copy.pendingTrigger = this.session.pendingTrigger
    copy.visible = this.session.visible
    copy.callUrl = this.session.callUrl
    copy.localNumber = this.session.localNumber
    copy.calleeNumber = this.session.calleeNumber
    copy.displayName = this.session.displayName
    copy.locId = this.session.locId
    copy.hospitalId = this.session.hospitalId
    copy.clientType = this.session.clientType
    copy.ip = this.session.ip
    copy.identity = this.session.identity
    copy.isAutoAnswer = this.session.isAutoAnswer
    copy.isHold = this.session.isHold
    copy.triggerScript = this.session.triggerScript
    copy.readyCheckScript = this.session.readyCheckScript
    copy.timeoutMs = this.session.timeoutMs
    copy.errorMessage = this.session.errorMessage
    return copy
  }

  private copyViewState(): RtcCallViewState {
    const copy = new RtcCallViewState()
    copy.visible = this.viewState.visible
    copy.phase = this.viewState.phase
    copy.protocol = this.viewState.protocol
    copy.direction = this.viewState.direction
    copy.mode = this.viewState.mode
    copy.callId = this.viewState.callId
    copy.uid = this.viewState.uid
    copy.local = RtcDefaultCallService.copyViewPeer(this.viewState.local)
    copy.remote = RtcDefaultCallService.copyViewPeer(this.viewState.remote)
    copy.autoAnswer = this.viewState.autoAnswer
    copy.registered = this.viewState.registered
    copy.canAccept = this.viewState.canAccept
    copy.canHangup = this.viewState.canHangup
    copy.errorMessage = this.viewState.errorMessage
    copy.registrationErrorMessage = this.viewState.registrationErrorMessage
    copy.volume = {
      enabled: this.viewState.volume.enabled,
      percent: this.viewState.volume.percent,
      updatedAt: this.viewState.volume.updatedAt
    }
    return copy
  }

  private static emptyViewPeer(): RtcCallViewPeer {
    const peer: RtcCallViewPeer = { number: '' }
    return peer
  }

  private static toViewPeerFromIdentity(identity: RtcPeerIdentity): RtcCallViewPeer {
    const peer: RtcCallViewPeer = { number: identity.number }
    peer.displayName = identity.displayName
    peer.uid = identity.uid
    peer.clientType = identity.clientType
    peer.locId = identity.locId
    return peer
  }

  private static toViewPeerFromTarget(target: RtcCallTarget): RtcCallViewPeer {
    const peer: RtcCallViewPeer = { number: target.number }
    peer.uid = target.uid
    peer.displayName = target.displayName
    peer.deviceIp = target.deviceIp
    peer.clientType = target.clientType
    peer.locId = target.locId
    return peer
  }

  private static toTargetFromSession(session: RtcCallSession): RtcCallTarget {
    return {
      number: session.calleeNumber,
      uid: session.uid,
      displayName: session.displayName,
      clientType: session.clientType,
      identity: session.identity,
      ip: session.ip,
      locId: session.locId,
      hospitalId: session.hospitalId,
      deviceIp: session.ip
    }
  }

  private static copyTarget(target: RtcCallTarget): RtcCallTarget {
    return {
      number: target.number,
      uid: target.uid,
      displayName: target.displayName,
      clientType: target.clientType,
      identity: target.identity,
      ip: target.ip,
      locId: target.locId,
      hospitalId: target.hospitalId,
      deviceIp: target.deviceIp
    }
  }

  private static resolveListItemPhase(
    record: RtcIncomingCallRecord,
    isHold: boolean,
    currentPhase?: RtcCallViewPhase
  ): RtcCallViewPhase {
    if (record.phase === 'incoming') {
      return RtcCallViewPhase.INCOMING
    }
    if (record.phase === 'outgoing') {
      return RtcCallViewPhase.OUTGOING
    }
    if (record.phase === 'ended') {
      return RtcCallViewPhase.ENDED
    }
    if (isHold) {
      return RtcCallViewPhase.HELD
    }
    if (!record.connectedAt) {
      return RtcCallViewPhase.CONNECTING
    }
    if (currentPhase === RtcCallViewPhase.CONNECTING) {
      return RtcCallViewPhase.CONNECTING
    }
    return RtcCallViewPhase.CONNECTED
  }

  private static copyViewPeer(peer: RtcCallViewPeer): RtcCallViewPeer {
    return {
      number: peer.number,
      uid: peer.uid,
      displayName: peer.displayName,
      deviceIp: peer.deviceIp,
      clientType: peer.clientType,
      locId: peer.locId
    }
  }
}
