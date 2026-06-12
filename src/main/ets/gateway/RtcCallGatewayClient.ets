import { RtcCallMode, RtcPeerIdentity } from '../model/RtcCallConfig'
import {
  RtcCandidateSignalData,
  RtcCommonRequest,
  RtcSignalMessage,
  RtcSdpSignalData
} from '../model/RtcSignalTypes'
import {
  RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE,
  RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP,
  RtcWebRtcIceCandidate,
  RtcWebRtcPeerConnectionAdapter,
  RtcWebRtcPeerRole,
  RtcWebRtcSessionDescription,
  RtcWebRtcSignalContext,
  RtcWebRtcSignalStateMachine
} from '../signaling/RtcWebRtcSignalStateMachine'
import { RtcCallTarget } from '../core/RtcCallService'
import { RtcCallGatewaySessionStore } from './RtcCallGatewaySessionStore'
import {
  RtcCallGatewayAdapter,
  RtcCallGatewayCandidateOptions,
  RtcCallGatewayChannelType,
  RtcCallGatewayClientOptions,
  RtcCallGatewayHangupOptions,
  RtcCallGatewayOpenActivityOptions,
  RtcCallGatewayOperationResult,
  RtcCallGatewaySdpOptions,
  RtcCallGatewaySignalResult,
  RtcCallGatewaySnapshot
} from './RtcCallGatewayTypes'

class RtcCallGatewayPeerAdapterBridge implements RtcWebRtcPeerConnectionAdapter {
  private delegate: RtcWebRtcPeerConnectionAdapter
  private gatewayAdapter: RtcCallGatewayAdapter

  constructor(delegate: RtcWebRtcPeerConnectionAdapter, gatewayAdapter: RtcCallGatewayAdapter) {
    this.delegate = delegate
    this.gatewayAdapter = gatewayAdapter
  }

  async ensurePeerConnection(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): Promise<void> {
    await this.delegate.ensurePeerConnection(role, context)
  }

  hasPeerConnection(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean {
    if (!this.delegate.hasPeerConnection) {
      return true
    }
    return this.delegate.hasPeerConnection(role, context)
  }

  isPeerConnectionCurrent(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean {
    if (!this.delegate.isPeerConnectionCurrent) {
      return true
    }
    return this.delegate.isPeerConnectionCurrent(role, context)
  }

  async setRemoteDescription(
    role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    await this.delegate.setRemoteDescription(role, description, context)
  }

  async addIceCandidate(
    role: RtcWebRtcPeerRole,
    candidate: RtcWebRtcIceCandidate,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    await this.delegate.addIceCandidate(role, candidate, context)
  }

  async createAnswer(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext):
    Promise<RtcWebRtcSessionDescription> {
    if (!this.delegate.createAnswer) {
      throw new Error('call-gateway peer adapter missing createAnswer')
    }
    return this.delegate.createAnswer(role, context)
  }

  async setLocalDescription(
    role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    await this.delegate.setLocalDescription?.(role, description, context)
  }

  async getLocalDescription(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext):
    Promise<RtcWebRtcSessionDescription | undefined> {
    if (!this.delegate.getLocalDescription) {
      return undefined
    }
    return this.delegate.getLocalDescription(role, context)
  }

  async sendSignal(message: RtcSignalMessage, context: RtcWebRtcSignalContext): Promise<void> {
    if (message.eventName === RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE) {
      const data = RtcWebRtcSignalStateMachine.parseCandidateData(message)
      if (!data) {
        return
      }
      const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(data.rtcUid)
      await this.gatewayAdapter.sendCandidate(
        data.commonRequest.uuid || context.sessionId,
        scope.rtcUid,
        RtcCallGatewaySessionStore.normalizeChannelType(scope.channelType),
        data.sdpMid || '',
        data.candidate || '',
        data.sdpMLineIndex || 0
      )
      return
    }

    if (message.eventName === RTC_WEBRTC_SIGNAL_EVENT_SEND_SDP) {
      const data = RtcWebRtcSignalStateMachine.parseSdpData(message)
      if (!data) {
        return
      }
      const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(data.rtcUid)
      await this.gatewayAdapter.sendSdp(
        data.commonRequest.uuid || context.sessionId,
        scope.rtcUid,
        RtcCallGatewaySessionStore.normalizeChannelType(scope.channelType),
        data.sdp || '',
        data.sdpType || '',
        0
      )
    }
  }
}

export class RtcCallGatewayClient {
  private adapter: RtcCallGatewayAdapter
  private local: RtcPeerIdentity
  private allowSingleCallNumberFallback: boolean
  private store: RtcCallGatewaySessionStore = new RtcCallGatewaySessionStore()
  private signalMachine?: RtcWebRtcSignalStateMachine
  private onStateChange?: (snapshot: RtcCallGatewaySnapshot) => void
  private onError?: (message: string) => void
  private onLog?: (message: string) => void

  constructor(options: RtcCallGatewayClientOptions) {
    this.adapter = options.adapter
    this.local = options.local
    this.allowSingleCallNumberFallback = options.allowSingleCallNumberFallback === true
    this.onStateChange = options.onStateChange
    this.onError = options.onError
    this.onLog = options.onLog
    if (options.peerAdapter) {
      this.signalMachine = new RtcWebRtcSignalStateMachine({
        adapter: new RtcCallGatewayPeerAdapterBridge(options.peerAdapter, options.adapter)
      })
    }
  }

  async start(): Promise<void> {
    await this.adapter.start?.()
  }

  async stop(): Promise<void> {
    await this.adapter.stop?.()
    this.store.clear()
    this.signalMachine?.resetSession()
    this.emitState()
  }

  async invite(target: RtcCallTarget, mode: RtcCallMode = RtcCallMode.AUDIO): Promise<RtcCallGatewayOperationResult> {
    await this.adapter.callInvite(target.number, mode === RtcCallMode.VIDEO)
    if (target.uid) {
      this.store.upsertOpenActivity({
        num: target.number,
        name: target.displayName,
        uid: target.uid,
        isOut: true,
        isVideo: mode === RtcCallMode.VIDEO
      })
      this.signalMachine?.registerSession(target.uid)
      this.emitState()
    }
    return { handled: true, reason: 'invite sent', uid: target.uid || '' }
  }

  async answer(uid: string): Promise<RtcCallGatewayOperationResult> {
    const resolved = this.store.resolveUid(uid, 'answer', this.allowSingleCallNumberFallback)
    if (!resolved.handled) {
      return this.reject(resolved)
    }
    this.store.markPhase(resolved.uid, 'answering', true)
    this.emitState()
    await this.adapter.callAnswer(resolved.uid)
    this.store.markPhase(resolved.uid, 'answered', false)
    this.emitState()
    return { handled: true, reason: 'answer accepted by gateway', uid: resolved.uid }
  }

  async switchCall(uid: string): Promise<RtcCallGatewayOperationResult> {
    const resolved = this.store.resolveUid(uid, 'switch', this.allowSingleCallNumberFallback)
    if (!resolved.handled) {
      return this.reject(resolved)
    }
    await this.adapter.callSwitch(resolved.uid)
    this.store.select(resolved.uid)
    this.emitState()
    return { handled: true, reason: 'switch sent', uid: resolved.uid }
  }

  async hangUp(uid: string, d: number = 0): Promise<RtcCallGatewayOperationResult> {
    const resolved = this.store.resolveUid(uid, 'hangup', this.allowSingleCallNumberFallback)
    if (!resolved.handled) {
      return this.reject(resolved)
    }
    await this.adapter.callHangUp(resolved.uid, d)
    this.removeSession(resolved.uid)
    return { handled: true, reason: 'hangup sent', uid: resolved.uid }
  }

  handleOpenActivity(num: string, name: string, uid: string, isOut: boolean):
    RtcCallGatewayOperationResult {
    return this.handleActivity({ num, name, uid, isOut, multi: false })
  }

  handleOpenMultiActivity(num: string, name: string, uid: string, isOut: boolean):
    RtcCallGatewayOperationResult {
    return this.handleActivity({ num, name, uid, isOut, multi: true })
  }

  async handleReceiverSdp(options: RtcCallGatewaySdpOptions): Promise<RtcCallGatewaySignalResult> {
    const prepared = this.prepareGatewaySignal(options.uid, options.rtcUID, options.channelType, options.from, options.to)
    if (!prepared.handled) {
      return this.rejectSignal(prepared)
    }
    if (!this.signalMachine) {
      return this.rejectSignal({ handled: false, reason: 'missing peer adapter', uid: prepared.uid })
    }

    const mode = options.isVideo === true ? RtcCallMode.VIDEO : (this.store.get(prepared.uid)?.mode || RtcCallMode.AUDIO)
    const data: RtcSdpSignalData = {
      sdp: options.sdp,
      sdpType: options.sdpType,
      rtcUid: RtcWebRtcSignalStateMachine.encodeRtcScope(options.rtcUID, options.channelType),
      commonRequest: this.buildCommonRequest(prepared.uid, options.from, options.to, mode)
    }
    const result = await this.signalMachine.handleSdp(data, {
      local: this.local,
      remote: this.buildRemotePeer(options.from, options.to),
      mode
    })
    return { handled: result.handled, reason: result.reason, uid: prepared.uid, signal: result }
  }

  async handleReceiverIceCandidate(options: RtcCallGatewayCandidateOptions):
    Promise<RtcCallGatewaySignalResult> {
    const prepared = this.prepareGatewaySignal(options.uid, options.rtcUID, options.channelType, options.from, options.to)
    if (!prepared.handled) {
      return this.rejectSignal(prepared)
    }
    if (!this.signalMachine) {
      return this.rejectSignal({ handled: false, reason: 'missing peer adapter', uid: prepared.uid })
    }

    const data: RtcCandidateSignalData = {
      candidateType: options.channelType,
      candidate: options.candidate,
      sdpMLineIndex: options.sdpMLineIndex,
      sdpMid: options.sdpMid,
      rtcUid: RtcWebRtcSignalStateMachine.encodeRtcScope(options.rtcUID, options.channelType),
      commonRequest: this.buildCommonRequest(
        prepared.uid,
        options.from,
        options.to,
        this.store.get(prepared.uid)?.mode || RtcCallMode.AUDIO
      )
    }
    const result = await this.signalMachine.handleCandidate(data)
    return { handled: result.handled, reason: result.reason, uid: prepared.uid, signal: result }
  }

  async sendLocalCandidate(options: RtcCallGatewayCandidateOptions): Promise<RtcCallGatewayOperationResult> {
    const prepared = this.prepareGatewaySignal(options.uid, options.rtcUID, options.channelType, options.from, options.to)
    if (!prepared.handled) {
      return this.reject(prepared)
    }
    await this.adapter.sendCandidate(
      prepared.uid,
      options.rtcUID,
      options.channelType,
      options.sdpMid || '',
      options.candidate,
      options.sdpMLineIndex || 0
    )
    return { handled: true, reason: 'candidate sent', uid: prepared.uid }
  }

  async handleHangUp(options: RtcCallGatewayHangupOptions): Promise<RtcCallGatewayOperationResult> {
    const resolved = this.store.resolveUid(options.uid, 'remote hangup', false)
    if (!resolved.handled) {
      return this.reject(resolved)
    }
    this.removeSession(resolved.uid)
    return { handled: true, reason: 'remote hangup', uid: resolved.uid }
  }

  async handleCloseWithId(options: RtcCallGatewayHangupOptions): Promise<RtcCallGatewayOperationResult> {
    const resolved = this.store.resolveUid(options.uid, 'remote close', false)
    if (!resolved.handled) {
      return this.reject(resolved)
    }
    this.removeSession(resolved.uid)
    return { handled: true, reason: 'remote close', uid: resolved.uid }
  }

  getSnapshot(): RtcCallGatewaySnapshot {
    return this.store.snapshot()
  }

  private handleActivity(options: RtcCallGatewayOpenActivityOptions): RtcCallGatewayOperationResult {
    if (!options.uid) {
      return this.reject({ handled: false, reason: 'missing uid', uid: '' })
    }
    const session = this.store.upsertOpenActivity(options)
    if (!session) {
      return this.reject({ handled: false, reason: 'missing uid', uid: '' })
    }
    this.signalMachine?.registerSession(session.uid)
    this.emitState()
    return { handled: true, reason: options.multi === true ? 'multi activity opened' : 'activity opened', uid: session.uid }
  }

  private prepareGatewaySignal(
    uid: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    from: string,
    to: string
  ): RtcCallGatewayOperationResult {
    const signalUid = (uid || '').trim()
    if (!signalUid) {
      return { handled: false, reason: 'missing uid', uid: '' }
    }
    if (!rtcUID) {
      return { handled: false, reason: 'missing rtcUID', uid: signalUid }
    }
    if (!this.store.get(signalUid)) {
      const remoteNumber = from === this.local.number ? to : from
      this.store.upsertOpenActivity({
        num: remoteNumber,
        uid: signalUid,
        isOut: from === this.local.number
      })
    }
    this.store.upsertPeer(signalUid, rtcUID, channelType, from, to)
    this.signalMachine?.registerSession(signalUid)
    this.emitState()
    return { handled: true, reason: 'signal ready', uid: signalUid }
  }

  private removeSession(uid: string): void {
    this.store.remove(uid)
    this.signalMachine?.unregisterSession(uid)
    this.emitState()
  }

  private buildCommonRequest(uid: string, from: string, to: string, mode: RtcCallMode): RtcCommonRequest {
    return {
      uuid: uid,
      locId: this.local.locId,
      hospitalId: this.local.hospitalId,
      number: this.local.number,
      displayName: this.local.displayName,
      clientType: this.local.clientType,
      identity: this.local.identity,
      to,
      from,
      grpcFrom: this.local.number,
      grpcTo: from,
      isVideo: mode === RtcCallMode.VIDEO
    }
  }

  private buildRemotePeer(from: string, to: string): RtcPeerIdentity {
    const localNumber = this.local.number
    return {
      number: from === localNumber ? to : from
    }
  }

  private reject(result: RtcCallGatewayOperationResult): RtcCallGatewayOperationResult {
    this.onError?.(result.reason)
    return result
  }

  private rejectSignal(result: RtcCallGatewayOperationResult): RtcCallGatewaySignalResult {
    this.onError?.(result.reason)
    return {
      handled: false,
      reason: result.reason,
      uid: result.uid
    }
  }

  private emitState(): void {
    const snapshot = this.store.snapshot()
    this.onLog?.('call-gateway state calls=' + snapshot.calls.length + ' peers=' + snapshot.peers.length)
    this.onStateChange?.(snapshot)
  }
}
