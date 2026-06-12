import { RtcCallMode, RtcPeerIdentity } from '../model/RtcCallConfig'
import {
  RtcCandidateSignalData,
  RtcCommonRequest,
  RtcSignalMessage,
  RtcSdpSignalData
} from '../model/RtcSignalTypes'
import { RtcLocalSdpResult, RtcSdpUtils } from '../core/RtcSdpUtils'

export const RTC_WEBRTC_SIGNAL_EVENT_SDP = 'c__sdp'
export const RTC_WEBRTC_SIGNAL_EVENT_CANDIDATE = 'c__candidate'
export const RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP = 's__sdp'
export const RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE = 's__candidate'
export const RTC_WEBRTC_PEER_ROLE_PUBLISH = 'publish'
export const RTC_WEBRTC_PEER_ROLE_SUBSCRIBE = 'subscribe'

export type RtcWebRtcPeerRole = 'publish' | 'subscribe'

export interface RtcWebRtcRtcScope {
  rtcUid: string
  channelType: RtcWebRtcPeerRole
}

export interface RtcWebRtcSessionDescription {
  type: string
  sdp: string
}

export interface RtcWebRtcIceCandidate {
  candidate: string
  sdpMLineIndex?: number
  sdpMid?: string
}

export interface RtcWebRtcIceStats {
  iceConnectionState?: string
  selectedCandidatePair?: string
  audioLevel?: number
  jitter?: number
  packetsLost?: number
  bytesSent?: number
  bytesReceived?: number
}

export interface RtcWebRtcIceCandidateStats {
  receivedCount: number
  queuedCount: number
  addAttemptCount: number
  addSuccessCount: number
  addFailureCount: number
  flushCount: number
  endOfCandidatesCount: number
  lastCandidateAt: number
  lastAddFailure: string
}

export interface RtcWebRtcSignalContext {
  role: RtcWebRtcPeerRole
  uuid: string
  sessionId: string
  rtcUid: string
  scopedRtcUid: string
  reason: string
}

export interface RtcWebRtcPeerConnectionAdapter {
  ensurePeerConnection(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): Promise<void>
  hasPeerConnection?(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean
  isPeerConnectionCurrent?(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean
  setRemoteDescription(
    role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    context: RtcWebRtcSignalContext
  ): Promise<void>
  addIceCandidate(
    role: RtcWebRtcPeerRole,
    candidate: RtcWebRtcIceCandidate,
    context: RtcWebRtcSignalContext
  ): Promise<void>
  createAnswer?(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): Promise<RtcWebRtcSessionDescription>
  setLocalDescription?(
    role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    context: RtcWebRtcSignalContext
  ): Promise<void>
  getLocalDescription?(
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext
  ): Promise<RtcWebRtcSessionDescription | undefined>
  getIceStats?(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): Promise<RtcWebRtcIceStats | undefined>
  sendSignal?(message: RtcSignalMessage, context: RtcWebRtcSignalContext): void | Promise<void>
}

export interface RtcWebRtcSignalLogger {
  info?(message: string): void
  warn?(message: string): void
  error?(message: string): void
}

export interface RtcWebRtcSignalStateMachineOptions {
  adapter: RtcWebRtcPeerConnectionAdapter
  logger?: RtcWebRtcSignalLogger
  answerEventName?: string
  candidateEventName?: string
  answerWaitMs?: number
  answerWaitAttempts?: number
  requireIceParamsForRemoteSdp?: boolean
  requireIceParamsForLocalAnswer?: boolean
}

export interface RtcWebRtcSignalRouteOptions {
  uuid: string
  local: RtcPeerIdentity
  remote: RtcPeerIdentity
  mode?: RtcCallMode
  rtcUid?: string
}

export interface RtcWebRtcBuildSdpSignalOptions extends RtcWebRtcSignalRouteOptions {
  eventName?: string
  sdp: string
  sdpType: string
  commonRequest?: RtcCommonRequest
}

export interface RtcWebRtcBuildCandidateSignalOptions extends RtcWebRtcSignalRouteOptions {
  eventName?: string
  candidateType?: string
  candidate: string
  sdpMLineIndex?: number
  sdpMid?: string
  commonRequest?: RtcCommonRequest
}

export interface RtcWebRtcHandleSdpOptions {
  role?: RtcWebRtcPeerRole
  local?: RtcPeerIdentity
  remote?: RtcPeerIdentity
  mode?: RtcCallMode
  autoCreateAnswer?: boolean
  sendAnswer?: boolean
  optimizeAnswerSdp?: boolean
  decodeSdp?: (value: string) => string
  encodeSdp?: (value: string) => string
  buildAnswerCommonRequest?: (
    inbound: RtcCommonRequest,
    context: RtcWebRtcSignalContext,
    options?: RtcWebRtcHandleSdpOptions
  ) => RtcCommonRequest
}

export interface RtcWebRtcHandleCandidateOptions {
  role?: RtcWebRtcPeerRole
}

export interface RtcWebRtcSignalHandleResult {
  handled: boolean
  skipped: boolean
  reason: string
  role: RtcWebRtcPeerRole
  uuid: string
  rtcUid: string
  scopedRtcUid: string
  sdpType?: string
  answerSignal?: RtcSignalMessage
}

export interface RtcWebRtcPeerSessionState {
  key: string
  role: RtcWebRtcPeerRole
  sessionId: string
  rtcUid: string
  remoteDescReady: boolean
  localDescReady: boolean
  pendingCandidates: RtcWebRtcIceCandidate[]
  iceStats: RtcWebRtcIceCandidateStats
  lastSdpType: string
  lastUpdatedAt: number
}

export interface RtcWebRtcSignalMachineState {
  activeUuid: string
  activeRtcUid: string
  publish: RtcWebRtcPeerSessionState
  publishes: RtcWebRtcPeerSessionState[]
  subscribes: RtcWebRtcPeerSessionState[]
}

function createIceCandidateStats(): RtcWebRtcIceCandidateStats {
  return {
    receivedCount: 0,
    queuedCount: 0,
    addAttemptCount: 0,
    addSuccessCount: 0,
    addFailureCount: 0,
    flushCount: 0,
    endOfCandidatesCount: 0,
    lastCandidateAt: 0,
    lastAddFailure: ''
  }
}

function createPeerState(role: RtcWebRtcPeerRole, sessionId: string = '', rtcUid: string = ''):
  RtcWebRtcPeerSessionState {
  return {
    key: role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE ?
      RtcWebRtcSignalStateMachine.getSubscribeKey(sessionId, rtcUid) : RTC_WEBRTC_PEER_ROLE_PUBLISH,
    role,
    sessionId,
    rtcUid,
    remoteDescReady: false,
    localDescReady: false,
    pendingCandidates: [],
    iceStats: createIceCandidateStats(),
    lastSdpType: '',
    lastUpdatedAt: 0
  }
}

export class RtcWebRtcSignalStateMachine {
  private adapter: RtcWebRtcPeerConnectionAdapter
  private logger?: RtcWebRtcSignalLogger
  private answerEventName: string
  private candidateEventName: string
  private answerWaitMs: number
  private answerWaitAttempts: number
  private requireIceParamsForRemoteSdp: boolean
  private requireIceParamsForLocalAnswer: boolean
  private activeUuid: string = ''
  private activeRtcUid: string = ''
  private publishStates: Map<string, RtcWebRtcPeerSessionState> = new Map()
  private subscribeStates: Map<string, RtcWebRtcPeerSessionState> = new Map()
  private endedSessionIds: string[] = []
  private registeredSessionIds: string[] = []

  constructor(options: RtcWebRtcSignalStateMachineOptions) {
    this.adapter = options.adapter
    this.logger = options.logger
    this.answerEventName = options.answerEventName || RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP
    this.candidateEventName = options.candidateEventName || RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE
    this.answerWaitMs = options.answerWaitMs || 120
    this.answerWaitAttempts = options.answerWaitAttempts || 10
    this.requireIceParamsForRemoteSdp = options.requireIceParamsForRemoteSdp !== false
    this.requireIceParamsForLocalAnswer = options.requireIceParamsForLocalAnswer !== false
  }

  getState(): RtcWebRtcSignalMachineState {
    const publishes: RtcWebRtcPeerSessionState[] = []
    const subscribes: RtcWebRtcPeerSessionState[] = []
    this.publishStates.forEach((state: RtcWebRtcPeerSessionState) => {
      publishes.push(this.copyPeerState(state))
    })
    this.subscribeStates.forEach((state: RtcWebRtcPeerSessionState) => {
      subscribes.push(this.copyPeerState(state))
    })
    const activePublish = this.getPublishState(this.activeUuid) || publishes[0] ||
      createPeerState(RTC_WEBRTC_PEER_ROLE_PUBLISH)
    return {
      activeUuid: this.activeUuid,
      activeRtcUid: this.activeRtcUid,
      publish: this.copyPeerState(activePublish),
      publishes,
      subscribes
    }
  }

  startSession(uuid: string, rtcUid: string = ''): void {
    this.activeUuid = RtcWebRtcSignalStateMachine.normalizeSignalSessionId(uuid)
    this.activeRtcUid = (rtcUid || '').trim()
    this.publishStates.clear()
    if (this.activeUuid) {
      this.publishStates.set(
        this.activeUuid,
        createPeerState(RTC_WEBRTC_PEER_ROLE_PUBLISH, this.activeUuid, this.activeRtcUid)
      )
    }
    this.subscribeStates.clear()
    this.registeredSessionIds = this.activeUuid ? [this.activeUuid] : []
    this.forgetEndedSession(this.activeUuid)
  }

  registerSession(uuid: string): void {
    const id = RtcWebRtcSignalStateMachine.normalizeSignalSessionId(uuid)
    if (!id) {
      return
    }
    if (this.registeredSessionIds.indexOf(id) < 0) {
      this.registeredSessionIds.push(id)
    }
    if (!this.activeUuid) {
      this.activeUuid = id
    }
    this.forgetEndedSession(id)
  }

  unregisterSession(uuid: string): void {
    const id = RtcWebRtcSignalStateMachine.normalizeSignalSessionId(uuid)
    if (!id) {
      return
    }
    this.registeredSessionIds = this.registeredSessionIds.filter((item: string) => item !== id)
    this.rememberEndedSession(id)
    const removals: string[] = []
    this.subscribeStates.forEach((state: RtcWebRtcPeerSessionState, key: string) => {
      if (state.sessionId === id) {
        removals.push(key)
      }
    })
    removals.forEach((key: string) => this.subscribeStates.delete(key))
    this.publishStates.delete(id)
    if (this.activeUuid === id) {
      this.activeUuid = this.registeredSessionIds.length > 0 ? this.registeredSessionIds[0] : ''
    }
  }

  resetSession(): void {
    this.activeUuid = ''
    this.activeRtcUid = ''
    this.publishStates.clear()
    this.subscribeStates.clear()
    this.registeredSessionIds = []
  }

  rememberEndedSession(sessionId: string): void {
    const id = RtcWebRtcSignalStateMachine.normalizeSignalSessionId(sessionId)
    if (!id || this.endedSessionIds.indexOf(id) >= 0) {
      return
    }
    this.endedSessionIds.push(id)
    if (this.endedSessionIds.length > 20) {
      this.endedSessionIds.shift()
    }
  }

  async handleSdp(data: RtcSdpSignalData, options?: RtcWebRtcHandleSdpOptions): Promise<RtcWebRtcSignalHandleResult> {
    const sessionId = RtcWebRtcSignalStateMachine.getSignalSessionId(data, this.activeUuid)
    const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(data.rtcUid)
    const sdpType = (data.sdpType || '').toLowerCase()
    const remoteSdp = options?.decodeSdp ? options.decodeSdp(data.sdp || '') : (data.sdp || '')
    let role = options?.role || scope.channelType
    const staleContext = this.createContext(role, sessionId, scope.rtcUid, 'handle sdp')
    if (this.isStaleSession(sessionId)) {
      this.warn(`skip stale sdp session=${sessionId} rtcUid=${scope.rtcUid}`)
      return this.createResult(false, true, 'stale session', staleContext, sdpType)
    }
    if (sdpType === 'offer' && role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE &&
      RtcWebRtcSignalStateMachine.isPublishOfferSdp(remoteSdp)) {
      this.rebindSubscribeToPublish(sessionId, scope.rtcUid)
      role = RTC_WEBRTC_PEER_ROLE_PUBLISH
    }
    const context = this.createContext(role, sessionId, scope.rtcUid, 'handle sdp')
    const state = sdpType === 'offer' ?
      this.beginSignalSession(sessionId, role, scope.rtcUid) : this.getExistingPeerState(sessionId, role, scope.rtcUid)
    if (!state) {
      return this.createResult(false, true, 'missing peer state', context, sdpType)
    }
    if (!data.sdp || !sdpType) {
      return this.createResult(false, true, 'empty sdp', context, sdpType)
    }
    if (!this.validateSessionDescriptionSdp(remoteSdp, 'remote', context, this.requireIceParamsForRemoteSdp)) {
      return this.createResult(false, true, 'invalid remote sdp', context, sdpType)
    }

    this.activateFromSignal(sessionId, scope.rtcUid)
    await this.adapter.ensurePeerConnection(role, context)
    await this.adapter.setRemoteDescription(role, { type: sdpType, sdp: remoteSdp }, context)
    if (!this.isPeerCurrent(role, context)) {
      return this.createResult(false, true, 'stale peer after remote description', context, sdpType)
    }
    this.markRemoteDescReady(state, sdpType)

    if (sdpType !== 'offer') {
      this.markLocalDescReady(state)
      await this.flushPendingIceCandidates(state, context)
      await this.logIceStats(role, context, 'sdp applied')
      return this.createResult(true, false, 'sdp applied', context, sdpType)
    }
    if (options?.autoCreateAnswer === false || !this.adapter.createAnswer) {
      await this.logIceStats(role, context, 'offer applied')
      return this.createResult(true, false, 'offer applied', context, sdpType)
    }

    let answer = await this.adapter.createAnswer(role, context)
    if (!this.isPeerCurrent(role, context)) {
      return this.createResult(false, true, 'stale peer after create answer', context, sdpType)
    }
    if (options?.optimizeAnswerSdp !== false) {
      answer = {
        type: answer.type,
        sdp: RtcSdpUtils.optimizeOpusForLowLatencyAudio(answer.sdp)
      }
    }
    await this.adapter.setLocalDescription?.(role, answer, context)
    if (!this.isPeerCurrent(role, context)) {
      return this.createResult(false, true, 'stale peer after local description', context, sdpType)
    }
    const localAnswer = await this.waitForLocalAnswerSdp(role, context, answer.sdp)
    if (!this.validateSessionDescriptionSdp(localAnswer.sdp, 'local', context, this.requireIceParamsForLocalAnswer)) {
      return this.createResult(false, true, 'invalid local answer sdp', context, sdpType)
    }
    this.markLocalDescReady(state)
    await this.flushPendingIceCandidates(state, context)
    const answerSignal = this.buildAnswerSignal(data, context, localAnswer.sdp, options)
    if (options?.sendAnswer !== false && this.adapter.sendSignal) {
      await this.adapter.sendSignal(answerSignal, context)
    }
    await this.logIceStats(role, context, `answer ready from ${localAnswer.source}`)
    return {
      handled: true,
      skipped: false,
      reason: 'answer ready',
      role,
      uuid: context.uuid,
      rtcUid: context.rtcUid,
      scopedRtcUid: context.scopedRtcUid,
      sdpType,
      answerSignal
    }
  }

  async handleCandidate(
    data: RtcCandidateSignalData,
    options?: RtcWebRtcHandleCandidateOptions
  ): Promise<RtcWebRtcSignalHandleResult> {
    const sessionId = RtcWebRtcSignalStateMachine.getSignalSessionId(data, this.activeUuid)
    const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(data.rtcUid)
    const role = options?.role || scope.channelType
    const context = this.createContext(role, sessionId, scope.rtcUid, 'handle candidate')
    if (this.isStaleSession(sessionId)) {
      this.warn(`skip stale candidate session=${sessionId} rtcUid=${scope.rtcUid}`)
      return this.createResult(false, true, 'stale session', context)
    }
    const state = this.getOrCreatePeerState(sessionId, role, scope.rtcUid)
    if (!data.candidate) {
      state.iceStats.endOfCandidatesCount += 1
      return this.createResult(false, true, 'empty candidate', context)
    }
    const candidate: RtcWebRtcIceCandidate = {
      candidate: data.candidate,
      sdpMLineIndex: data.sdpMLineIndex,
      sdpMid: data.sdpMid
    }
    state.iceStats.receivedCount += 1
    state.iceStats.lastCandidateAt = Date.now()
    this.activateFromSignal(sessionId, scope.rtcUid)
    if (!this.canApplyCandidate(state, context)) {
      this.queueCandidate(state, candidate)
      this.info(`queue candidate role=${role} session=${sessionId} rtcUid=${scope.rtcUid} pending=${state.pendingCandidates.length}`)
      return this.createResult(true, false, 'candidate queued', context)
    }
    await this.addIceCandidateWithStats(state, candidate, context, 'direct')
    await this.logIceStats(role, context, 'candidate applied')
    return this.createResult(true, false, 'candidate applied', context)
  }

  async handleSdpMessage(
    message: RtcSignalMessage,
    options?: RtcWebRtcHandleSdpOptions
  ): Promise<RtcWebRtcSignalHandleResult> {
    const data = RtcWebRtcSignalStateMachine.parseSdpData(message)
    if (!data) {
      return this.createResult(false, true, 'invalid sdp message', this.createEmptyContext())
    }
    return this.handleSdp(data, options)
  }

  async handleCandidateMessage(
    message: RtcSignalMessage,
    options?: RtcWebRtcHandleCandidateOptions
  ): Promise<RtcWebRtcSignalHandleResult> {
    const data = RtcWebRtcSignalStateMachine.parseCandidateData(message)
    if (!data) {
      return this.createResult(false, true, 'invalid candidate message', this.createEmptyContext())
    }
    return this.handleCandidate(data, options)
  }

  async waitForLocalAnswerSdp(
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext,
    fallbackSdp: string = ''
  ): Promise<RtcLocalSdpResult> {
    if (!this.adapter.getLocalDescription) {
      return {
        sdp: fallbackSdp,
        source: fallbackSdp ? 'fallback' : 'unavailable'
      }
    }
    for (let i = 0; i < this.answerWaitAttempts; i += 1) {
      const description = await this.adapter.getLocalDescription(role, context)
      const sdp = description?.sdp || ''
      if (this.isUsableLocalAnswerSdp(sdp)) {
        return {
          sdp,
          source: 'localDescription'
        }
      }
      await this.sleep(this.answerWaitMs)
    }
    return {
      sdp: fallbackSdp,
      source: fallbackSdp ? 'fallback' : 'timeout'
    }
  }

  async logIceStats(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext, reason: string): Promise<void> {
    if (!this.adapter.getIceStats || !this.logger?.info) {
      return
    }
    const stats = await this.adapter.getIceStats(role, context)
    if (!stats) {
      return
    }
    this.logger.info(
      `webrtc ice ${role} ${reason}` +
        ` session=${context.sessionId}` +
        ` rtcUid=${context.rtcUid}` +
        ` state=${stats.iceConnectionState || ''}` +
        ` pair=${stats.selectedCandidatePair || ''}` +
        ` audioLevel=${stats.audioLevel ?? ''}` +
        ` jitter=${stats.jitter ?? ''}` +
        ` packetsLost=${stats.packetsLost ?? ''}` +
        ` bytesSent=${stats.bytesSent ?? ''}` +
        ` bytesReceived=${stats.bytesReceived ?? ''}`
    )
  }

  static parseSdpData(message: RtcSignalMessage): RtcSdpSignalData | undefined {
    if (!message?.data) {
      return undefined
    }
    try {
      const data = JSON.parse(message.data) as RtcSdpSignalData
      if (!data.commonRequest || !data.sdpType) {
        return undefined
      }
      return data
    } catch (_error) {
      return undefined
    }
  }

  static parseCandidateData(message: RtcSignalMessage): RtcCandidateSignalData | undefined {
    if (!message?.data) {
      return undefined
    }
    try {
      const data = JSON.parse(message.data) as RtcCandidateSignalData
      if (!data.commonRequest) {
        return undefined
      }
      return data
    } catch (_error) {
      return undefined
    }
  }

  static buildCommonRequest(options: RtcWebRtcSignalRouteOptions): RtcCommonRequest {
    const local = options.local
    const remote = options.remote
    return {
      uuid: options.uuid,
      locId: local.locId,
      hospitalId: local.hospitalId,
      number: local.number,
      displayName: local.displayName,
      clientType: local.clientType,
      identity: local.identity,
      to: remote.number,
      toName: remote.displayName,
      from: local.number,
      fromName: local.displayName,
      grpcFrom: local.number,
      grpcTo: remote.number,
      isVideo: options.mode === RtcCallMode.VIDEO
    }
  }

  static buildAnswerCommonRequest(
    inbound: RtcCommonRequest,
    local?: RtcPeerIdentity,
    remote?: RtcPeerIdentity,
    mode?: RtcCallMode
  ): RtcCommonRequest {
    if (!local) {
      return {
        uuid: inbound.uuid,
        locId: inbound.locId,
        hospitalId: inbound.hospitalId,
        number: inbound.to || inbound.grpcTo || inbound.number,
        displayName: inbound.toName || inbound.displayName,
        clientType: inbound.clientType,
        identity: inbound.identity,
        to: inbound.to,
        toName: inbound.toName,
        from: inbound.from,
        fromName: inbound.fromName,
        grpcFrom: inbound.grpcTo,
        grpcTo: inbound.grpcFrom,
        isVideo: inbound.isVideo
      }
    }
    return {
      uuid: inbound.uuid,
      locId: local.locId || inbound.locId,
      hospitalId: local.hospitalId || inbound.hospitalId,
      number: local.number,
      displayName: local.displayName,
      clientType: local.clientType || inbound.clientType,
      identity: local.identity || inbound.identity,
      to: local.number,
      toName: local.displayName,
      from: local.number,
      fromName: local.displayName,
      grpcFrom: local.number,
      grpcTo: remote?.number || inbound.grpcFrom || inbound.from || '',
      isVideo: mode ? mode === RtcCallMode.VIDEO : inbound.isVideo
    }
  }

  static buildSdpSignal(options: RtcWebRtcBuildSdpSignalOptions): RtcSignalMessage {
    const data: RtcSdpSignalData = {
      sdp: options.sdp,
      sdpType: options.sdpType,
      rtcUid: options.rtcUid || '',
      commonRequest: options.commonRequest || RtcWebRtcSignalStateMachine.buildCommonRequest(options)
    }
    return {
      eventName: options.eventName || RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP,
      number: options.local.number,
      clientType: options.local.clientType,
      displayName: options.local.displayName,
      data: JSON.stringify(data)
    }
  }

  static buildCandidateSignal(options: RtcWebRtcBuildCandidateSignalOptions): RtcSignalMessage {
    const data: RtcCandidateSignalData = {
      candidateType: options.candidateType || RTC_WEBRTC_PEER_ROLE_PUBLISH,
      candidate: options.candidate,
      sdpMLineIndex: options.sdpMLineIndex,
      sdpMid: options.sdpMid,
      rtcUid: options.rtcUid || '',
      commonRequest: options.commonRequest || RtcWebRtcSignalStateMachine.buildCommonRequest(options)
    }
    return {
      eventName: options.eventName || RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE,
      number: options.local.number,
      clientType: options.local.clientType,
      displayName: options.local.displayName,
      data: JSON.stringify(data)
    }
  }

  static encodeRtcScope(rtcUid: string, channelType: string): string {
    const uid = (rtcUid || '').trim()
    const channel = RtcWebRtcSignalStateMachine.normalizeRtcChannelType(channelType)
    if (!uid && !channel) {
      return ''
    }
    if (!channel) {
      return uid
    }
    if (!uid) {
      return channel
    }
    return channel + '|' + uid
  }

  static decodeRtcScope(raw?: string): RtcWebRtcRtcScope {
    const value = (raw || '').trim()
    if (!value) {
      return { rtcUid: '', channelType: RTC_WEBRTC_PEER_ROLE_PUBLISH }
    }
    if (value.indexOf('|') >= 0) {
      const parts = value.split('|')
      return {
        channelType: RtcWebRtcSignalStateMachine.normalizeRtcChannelType(parts[0]),
        rtcUid: parts[1] || ''
      }
    }
    if (value === RTC_WEBRTC_PEER_ROLE_PUBLISH || value === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE) {
      return {
        channelType: value,
        rtcUid: ''
      }
    }
    return {
      channelType: RTC_WEBRTC_PEER_ROLE_SUBSCRIBE,
      rtcUid: value
    }
  }

  static normalizeRtcChannelType(channelType?: string): RtcWebRtcPeerRole {
    return channelType === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE ?
      RTC_WEBRTC_PEER_ROLE_SUBSCRIBE : RTC_WEBRTC_PEER_ROLE_PUBLISH
  }

  static getSubscribeKey(sessionId: string, rtcUid: string): string {
    return RTC_WEBRTC_PEER_ROLE_SUBSCRIBE + ':' + ((rtcUid || '').trim() ||
      RtcWebRtcSignalStateMachine.normalizeSignalSessionId(sessionId))
  }

  static normalizeSignalSessionId(uid: string | undefined): string {
    if (!uid) {
      return ''
    }
    return uid.toString().split(',')[0]
  }

  static getSignalSessionId(payload: RtcSdpSignalData | RtcCandidateSignalData, fallback: string = ''): string {
    if (payload?.commonRequest?.uuid) {
      return RtcWebRtcSignalStateMachine.normalizeSignalSessionId(payload.commonRequest.uuid)
    }
    return RtcWebRtcSignalStateMachine.normalizeSignalSessionId(fallback)
  }

  static hasDirectionalAttribute(sdp: string, attr: string): boolean {
    const normalized = ('\n' + (sdp || '').replace(/\r\n/g, '\n')).toLowerCase()
    return normalized.indexOf('\na=' + attr) >= 0
  }

  static isPublishOfferSdp(sdp: string): boolean {
    return RtcWebRtcSignalStateMachine.hasDirectionalAttribute(sdp, 'recvonly') &&
      !RtcWebRtcSignalStateMachine.hasDirectionalAttribute(sdp, 'sendonly')
  }

  private getExistingPeerState(
    sessionId: string,
    role: RtcWebRtcPeerRole,
    rtcUid: string
  ): RtcWebRtcPeerSessionState | undefined {
    if (role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE) {
      return this.subscribeStates.get(RtcWebRtcSignalStateMachine.getSubscribeKey(sessionId, rtcUid))
    }
    return this.getPublishState(sessionId)
  }

  private getOrCreatePeerState(
    sessionId: string,
    role: RtcWebRtcPeerRole,
    rtcUid: string
  ): RtcWebRtcPeerSessionState {
    if (role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE) {
      const key = RtcWebRtcSignalStateMachine.getSubscribeKey(sessionId, rtcUid)
      let state = this.subscribeStates.get(key)
      if (!state) {
        state = createPeerState(role, sessionId, rtcUid)
        this.subscribeStates.set(key, state)
      }
      return state
    }
    const id = RtcWebRtcSignalStateMachine.normalizeSignalSessionId(sessionId)
    let state = this.publishStates.get(id)
    if (!state) {
      state = createPeerState(RTC_WEBRTC_PEER_ROLE_PUBLISH, id, rtcUid)
      this.publishStates.set(id, state)
    } else if (!state.rtcUid && rtcUid) {
      state.rtcUid = rtcUid
    }
    return state
  }

  private beginSignalSession(
    sessionId: string,
    role: RtcWebRtcPeerRole,
    rtcUid: string
  ): RtcWebRtcPeerSessionState {
    const state = this.getOrCreatePeerState(sessionId, role, rtcUid)
    state.remoteDescReady = false
    state.localDescReady = false
    state.pendingCandidates = []
    state.iceStats = createIceCandidateStats()
    state.lastUpdatedAt = Date.now()
    return state
  }

  private rebindSubscribeToPublish(sessionId: string, rtcUid: string): void {
    const key = RtcWebRtcSignalStateMachine.getSubscribeKey(sessionId, rtcUid)
    const subscribeState = this.subscribeStates.get(key)
    if (!subscribeState) {
      return
    }
    const publishState = this.getOrCreatePeerState(sessionId, RTC_WEBRTC_PEER_ROLE_PUBLISH, rtcUid)
    subscribeState.pendingCandidates.forEach((candidate: RtcWebRtcIceCandidate) => {
      publishState.pendingCandidates.push(candidate)
    })
    this.mergeIceCandidateStats(publishState.iceStats, subscribeState.iceStats)
    this.subscribeStates.delete(key)
    this.info(`rebind signal state raw=subscribe resolved=publish session=${sessionId} rtcUid=${rtcUid}`)
  }

  private createContext(
    role: RtcWebRtcPeerRole,
    sessionId: string,
    rtcUid: string = '',
    reason: string = ''
  ): RtcWebRtcSignalContext {
    return {
      role,
      uuid: sessionId,
      sessionId,
      rtcUid,
      scopedRtcUid: RtcWebRtcSignalStateMachine.encodeRtcScope(rtcUid, role),
      reason
    }
  }

  private createEmptyContext(): RtcWebRtcSignalContext {
    return this.createContext(RTC_WEBRTC_PEER_ROLE_PUBLISH, this.activeUuid, this.activeRtcUid)
  }

  private createResult(
    handled: boolean,
    skipped: boolean,
    reason: string,
    context: RtcWebRtcSignalContext,
    sdpType: string = ''
  ): RtcWebRtcSignalHandleResult {
    return {
      handled,
      skipped,
      reason,
      role: context.role,
      uuid: context.uuid,
      rtcUid: context.rtcUid,
      scopedRtcUid: context.scopedRtcUid,
      sdpType
    }
  }

  private buildAnswerSignal(
    data: RtcSdpSignalData,
    context: RtcWebRtcSignalContext,
    answerSdp: string,
    options?: RtcWebRtcHandleSdpOptions
  ): RtcSignalMessage {
    const commonRequest = options?.buildAnswerCommonRequest ?
      options.buildAnswerCommonRequest(data.commonRequest, context, options) :
      RtcWebRtcSignalStateMachine.buildAnswerCommonRequest(
        data.commonRequest,
        options?.local,
        options?.remote,
        options?.mode
      )
    const local = options?.local || RtcWebRtcSignalStateMachine.getLocalPeer(commonRequest)
    const remote = options?.remote || RtcWebRtcSignalStateMachine.getRemotePeer(commonRequest)
    const encodedSdp = options?.encodeSdp ? options.encodeSdp(answerSdp) : answerSdp
    return RtcWebRtcSignalStateMachine.buildSdpSignal({
      eventName: this.answerEventName,
      uuid: context.sessionId,
      rtcUid: context.scopedRtcUid,
      local,
      remote,
      mode: options?.mode || (data.commonRequest.isVideo ? RtcCallMode.VIDEO : RtcCallMode.AUDIO),
      sdp: encodedSdp,
      sdpType: 'answer',
      commonRequest
    })
  }

  private static getLocalPeer(commonRequest: RtcCommonRequest): RtcPeerIdentity {
    return {
      number: commonRequest.number || commonRequest.from || commonRequest.grpcFrom || '',
      displayName: commonRequest.displayName || commonRequest.fromName,
      clientType: commonRequest.clientType,
      identity: commonRequest.identity,
      locId: commonRequest.locId,
      hospitalId: commonRequest.hospitalId
    }
  }

  private static getRemotePeer(commonRequest: RtcCommonRequest): RtcPeerIdentity {
    return {
      number: commonRequest.grpcTo || commonRequest.to || '',
      displayName: commonRequest.toName,
      clientType: commonRequest.clientType,
      locId: commonRequest.locId,
      hospitalId: commonRequest.hospitalId
    }
  }

  private isStaleSession(sessionId: string): boolean {
    if (!sessionId) {
      return true
    }
    if (this.endedSessionIds.indexOf(sessionId) >= 0) {
      return true
    }
    if (this.registeredSessionIds.indexOf(sessionId) >= 0) {
      return false
    }
    if (!this.activeUuid || this.activeUuid === sessionId) {
      return false
    }
    if (this.publishStates.has(sessionId)) {
      return false
    }
    let found = false
    this.subscribeStates.forEach((state: RtcWebRtcPeerSessionState) => {
      if (state.sessionId === sessionId) {
        found = true
      }
    })
    return !found
  }

  private activateFromSignal(sessionId: string, rtcUid: string = ''): void {
    if (!this.activeUuid && sessionId) {
      this.activeUuid = sessionId
    }
    if (!this.activeRtcUid && rtcUid) {
      this.activeRtcUid = rtcUid
    }
    this.forgetEndedSession(sessionId)
  }

  private getPublishState(sessionId: string): RtcWebRtcPeerSessionState | undefined {
    const id = RtcWebRtcSignalStateMachine.normalizeSignalSessionId(sessionId)
    if (!id) {
      return undefined
    }
    return this.publishStates.get(id)
  }

  private forgetEndedSession(sessionId: string): void {
    if (!sessionId) {
      return
    }
    this.endedSessionIds = this.endedSessionIds.filter((item: string) => item !== sessionId)
  }

  private markRemoteDescReady(state: RtcWebRtcPeerSessionState, sdpType: string): void {
    state.remoteDescReady = true
    state.lastSdpType = sdpType
    state.lastUpdatedAt = Date.now()
  }

  private markLocalDescReady(state: RtcWebRtcPeerSessionState): void {
    state.localDescReady = true
    state.lastUpdatedAt = Date.now()
  }

  private canApplyCandidate(state: RtcWebRtcPeerSessionState, context: RtcWebRtcSignalContext): boolean {
    if (!state.remoteDescReady || !state.localDescReady) {
      return false
    }
    if (this.adapter.hasPeerConnection) {
      return this.adapter.hasPeerConnection(state.role, context)
    }
    return true
  }

  private queueCandidate(state: RtcWebRtcPeerSessionState, candidate: RtcWebRtcIceCandidate): void {
    state.pendingCandidates.push(candidate)
    state.iceStats.queuedCount += 1
    state.lastUpdatedAt = Date.now()
  }

  private async flushPendingIceCandidates(
    state: RtcWebRtcPeerSessionState,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    if (!state.remoteDescReady || !state.localDescReady || state.pendingCandidates.length === 0) {
      return
    }
    if (!this.canApplyCandidate(state, context)) {
      return
    }
    const pending = state.pendingCandidates
    state.pendingCandidates = []
    state.iceStats.flushCount += 1
    for (let i = 0; i < pending.length; i += 1) {
      if (!this.isPeerCurrent(state.role, context)) {
        this.queueCandidate(state, pending[i])
        return
      }
      await this.addIceCandidateWithStats(state, pending[i], context, `flush#${i + 1}/${pending.length}`)
    }
  }

  private async addIceCandidateWithStats(
    state: RtcWebRtcPeerSessionState,
    candidate: RtcWebRtcIceCandidate,
    context: RtcWebRtcSignalContext,
    source: string
  ): Promise<boolean> {
    state.iceStats.addAttemptCount += 1
    const startedAt = Date.now()
    try {
      await this.adapter.addIceCandidate(state.role, candidate, context)
      state.iceStats.addSuccessCount += 1
      this.info(`addIceCandidate ok source=${source} elapsed=${Date.now() - startedAt}ms role=${state.role}` +
        ` session=${state.sessionId} rtcUid=${state.rtcUid} ${this.getIceStatsText(state)}`)
      return true
    } catch (error) {
      state.iceStats.addFailureCount += 1
      state.iceStats.lastAddFailure = JSON.stringify(error)
      this.error(`addIceCandidate failed source=${source} elapsed=${Date.now() - startedAt}ms role=${state.role}` +
        ` session=${state.sessionId} rtcUid=${state.rtcUid} ${this.getIceStatsText(state)} error=${JSON.stringify(error)}`)
      return false
    }
  }

  private mergeIceCandidateStats(target: RtcWebRtcIceCandidateStats, source: RtcWebRtcIceCandidateStats): void {
    target.receivedCount += source.receivedCount
    target.queuedCount += source.queuedCount
    target.addAttemptCount += source.addAttemptCount
    target.addSuccessCount += source.addSuccessCount
    target.addFailureCount += source.addFailureCount
    target.flushCount += source.flushCount
    target.endOfCandidatesCount += source.endOfCandidatesCount
    target.lastCandidateAt = Math.max(target.lastCandidateAt, source.lastCandidateAt)
    if (source.lastAddFailure) {
      target.lastAddFailure = source.lastAddFailure
    }
  }

  private getIceStatsText(state: RtcWebRtcPeerSessionState): string {
    const stats = state.iceStats
    return `iceStats(received=${stats.receivedCount},queued=${stats.queuedCount},attempt=${stats.addAttemptCount},` +
      `success=${stats.addSuccessCount},failed=${stats.addFailureCount},flush=${stats.flushCount},` +
      `eoc=${stats.endOfCandidatesCount},pending=${state.pendingCandidates.length},lastAt=${stats.lastCandidateAt},` +
      `lastError=${stats.lastAddFailure})`
  }

  private validateSessionDescriptionSdp(
    sdp: string,
    phase: string,
    context: RtcWebRtcSignalContext,
    requireIce: boolean
  ): boolean {
    const basic = RtcSdpUtils.validateBasicSdp(sdp)
    const hasIce = RtcSdpUtils.hasIceParams(sdp)
    if (basic && (!requireIce || hasIce)) {
      return true
    }
    this.error(`invalid ${phase} SDP role=${context.role} session=${context.sessionId} rtcUid=${context.rtcUid}` +
      ` basic=${basic} hasIce=${hasIce}`)
    return false
  }

  private isPeerCurrent(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean {
    if (!this.adapter.isPeerConnectionCurrent) {
      return true
    }
    return this.adapter.isPeerConnectionCurrent(role, context)
  }

  private copyPeerState(state: RtcWebRtcPeerSessionState): RtcWebRtcPeerSessionState {
    return {
      key: state.key,
      role: state.role,
      sessionId: state.sessionId,
      rtcUid: state.rtcUid,
      remoteDescReady: state.remoteDescReady,
      localDescReady: state.localDescReady,
      pendingCandidates: state.pendingCandidates.slice(),
      iceStats: {
        receivedCount: state.iceStats.receivedCount,
        queuedCount: state.iceStats.queuedCount,
        addAttemptCount: state.iceStats.addAttemptCount,
        addSuccessCount: state.iceStats.addSuccessCount,
        addFailureCount: state.iceStats.addFailureCount,
        flushCount: state.iceStats.flushCount,
        endOfCandidatesCount: state.iceStats.endOfCandidatesCount,
        lastCandidateAt: state.iceStats.lastCandidateAt,
        lastAddFailure: state.iceStats.lastAddFailure
      },
      lastSdpType: state.lastSdpType,
      lastUpdatedAt: state.lastUpdatedAt
    }
  }

  private isUsableLocalAnswerSdp(sdp: string): boolean {
    if (!RtcSdpUtils.validateBasicSdp(sdp)) {
      return false
    }
    return !this.requireIceParamsForLocalAnswer || RtcSdpUtils.hasIceParams(sdp)
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }

  private info(message: string): void {
    this.logger?.info?.(message)
  }

  private warn(message: string): void {
    this.logger?.warn?.(message)
  }

  private error(message: string): void {
    this.logger?.error?.(message)
  }
}
