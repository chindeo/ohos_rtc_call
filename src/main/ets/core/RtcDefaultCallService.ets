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

export interface RtcCallCommandResult {
  handled: boolean
  reason: string
  command: RtcCallControlCommand
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
      status: options.status || 'incoming'
    })
    const mediaBusy = this.session.active && this.session.hostPhase === RtcHostPhase.MEDIA_ACTIVE
    if (mediaBusy && options.autoAnswer !== true && !this.viewState.autoAnswer) {
      this.emitState()
      return
    }
    this.activateIncomingCall(incoming)
    this.emitState()
    if (options.autoAnswer === true || this.viewState.autoAnswer) {
      await this.acceptCall()
    }
  }

  async acceptIncomingCall(callIdOrUid: string, command?: RtcCallControlCommand): Promise<void> {
    const incoming = this.incomingQueue.accept(callIdOrUid)
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
    this.sessionStore.markHold(this.session.uid || this.session.requestId || this.session.calleeNumber, false)
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
    this.viewState.phase = RtcCallViewPhase.CONNECTED
    this.viewState.canAccept = false
    this.viewState.canHangup = true
    this.emitState()
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
    this.sessionStore.markHold(this.session.uid || this.session.requestId || this.session.calleeNumber, false)
    this.emitState()
    await this.handlers?.onResumeCall?.(this.copySession(), command)
  }

  async holdCallById(callIdOrUid: string, command?: RtcCallControlCommand): Promise<void> {
    if (this.session.requestId !== callIdOrUid && this.session.uid !== callIdOrUid) {
      const incoming = this.incomingQueue.accept(callIdOrUid)
      if (incoming) {
        this.activateIncomingCall(incoming)
      }
    }
    await this.holdCall(command)
    this.sessionStore.markHold(callIdOrUid, true)
  }

  async resumeCallById(callIdOrUid: string, command?: RtcCallControlCommand): Promise<void> {
    if (this.session.requestId !== callIdOrUid && this.session.uid !== callIdOrUid) {
      const incoming = this.incomingQueue.accept(callIdOrUid)
      if (incoming) {
        this.activateIncomingCall(incoming)
      }
    }
    await this.resumeCall(command)
    this.sessionStore.markHold(callIdOrUid, false)
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

  getViewState(): RtcCallViewState {
    return this.copyViewState()
  }

  getIncomingCalls(): RtcIncomingCallQueueSnapshot {
    return this.incomingQueue.getSnapshot()
  }

  getCallSessions(): RtcCallSessionStoreSnapshot {
    return this.sessionStore.snapshot()
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
    this.session.uid = target.uid || target.identity || callId
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
