import { RtcCallMode, RtcPeerIdentity } from '../model/RtcCallConfig'
import {
  RtcApplySignalData,
  RtcBroadcastSignalData,
  RtcCandidateSignalData,
  RtcCommonRequest,
  RtcHoldSwitchNotice,
  RtcSdpSignalData,
  RtcServerInfo,
  RtcSignalMessage,
  RtcSignalPayload
} from '../model/RtcSignalTypes'
import {
  RtcWebRtcSignalConnectOptions,
  RtcWebRtcSignalMessage,
  RtcWebRtcSignalSession
} from '../signaling/RtcWebRtcSignalSession'
import {
  RTC_WEBRTC_PEER_ROLE_PUBLISH,
  RtcWebRtcSignalContext,
  RtcWebRtcSignalStateMachine
} from '../signaling/RtcWebRtcSignalStateMachine'
import { RtcWebRtcMediaController, RtcWebRtcMediaSessionOptions } from './RtcWebRtcMediaController'
import { RtcWebRtcTrackIdentityCodec } from './RtcWebRtcTrackIdentity'

export interface RtcWebRtcCallControllerConfig extends RtcWebRtcSignalConnectOptions {
  local: RtcPeerIdentity
}

export interface RtcWebRtcCallSessionInfo {
  sessionKey: string
  sessionId: string
  uid: string
  targetNumber: string
  targetName: string
  remoteClientType: string
  mode: RtcCallMode
  incoming: boolean
  commonRequest: RtcCommonRequest
}

export interface RtcWebRtcCallControllerListener {
  onRegistered?: (server: RtcServerInfo) => void
  onIncoming?: (session: RtcWebRtcCallSessionInfo) => void
  onPublishReady?: (sessionKey: string, session?: RtcWebRtcCallSessionInfo) => void
  onAnswerNotice?: (session: RtcWebRtcCallSessionInfo) => void
  onHangup?: (sessionKey: string, all: boolean) => void
  onHoldChange?: (sessionKey: string, isHold: boolean) => void
  onBroadcast?: (message: RtcWebRtcSignalMessage) => void
  onError?: (message: string) => void
  onLog?: (message: string) => void
}

interface RtcRecentLocalSingleHangup {
  sessionKey: string
  sessionId: string
  targetNumber: string
  at: number
}

export class RtcWebRtcCallController {
  private signalSession: RtcWebRtcSignalSession
  private signalStateMachine: RtcWebRtcSignalStateMachine
  private mediaController: RtcWebRtcMediaController
  private listener: RtcWebRtcCallControllerListener
  private config?: RtcWebRtcCallControllerConfig
  private server: RtcServerInfo = {
    serveNumber: '',
    serveIp: '',
    serveDisplayName: ''
  }
  private sessions: Map<string, RtcWebRtcCallSessionInfo> = new Map()
  private sessionIds: Map<string, string> = new Map()
  private pendingStartSessionKeys: string[] = []
  private recentLocalSingleHangup?: RtcRecentLocalSingleHangup
  private localSingleHangupEchoGuardMs: number = 5000

  constructor(
    mediaController: RtcWebRtcMediaController,
    listener: RtcWebRtcCallControllerListener = {},
    signalSession?: RtcWebRtcSignalSession
  ) {
    this.mediaController = mediaController
    this.listener = listener
    this.signalSession = signalSession || new RtcWebRtcSignalSession()
    this.signalStateMachine = new RtcWebRtcSignalStateMachine({
      adapter: mediaController,
      logger: {
        info: (message: string) => this.listener.onLog?.(message),
        warn: (message: string) => this.listener.onLog?.('warn: ' + message),
        error: (message: string) => this.listener.onError?.(message)
      }
    })
    this.mediaController.setSignalSender((message: RtcSignalMessage, context: RtcWebRtcSignalContext) => {
      this.sendSignal(message, context)
    })
    this.bindSignalSession()
  }

  start(config: RtcWebRtcCallControllerConfig): void {
    this.config = config
    this.signalSession.connect({
      serverUrl: config.serverUrl,
      identity: config.identity,
      appVersion: config.appVersion,
      systemType: config.systemType
    })
  }

  registerOutgoingSession(
    sessionId: string,
    target: RtcPeerIdentity,
    mode: RtcCallMode
  ): RtcWebRtcCallSessionInfo {
    const commonRequest = this.buildApplyCommonRequest(sessionId, target, mode)
    const session = this.upsertSession(commonRequest, false)
    this.signalStateMachine.registerSession(sessionId)
    return session
  }

  startCall(sessionKey: string): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    if (!this.server.serveNumber) {
      if (this.pendingStartSessionKeys.indexOf(session.sessionKey) < 0) {
        this.pendingStartSessionKeys.push(session.sessionKey)
      }
      return true
    }
    this.sendApply(1, session, false)
    return true
  }

  accept(sessionKey: string): boolean {
    const session = this.findSession(sessionKey)
    if (!session || !this.server.serveNumber) {
      return false
    }
    this.sendApply(2, session, false)
    return true
  }

  hangup(sessionKey: string): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    if (this.server.serveNumber) {
      this.sendApply(3, session, false)
    }
    this.rememberLocalSingleHangup(session)
    this.removeSession(session.sessionKey)
    return true
  }

  hangupAll(): void {
    this.recentLocalSingleHangup = undefined
    const first = this.sessions.values().next()
    if (!first.done && this.server.serveNumber) {
      this.sendApply(3, first.value, true)
    }
    const keys: string[] = []
    this.sessions.forEach((session: RtcWebRtcCallSessionInfo) => keys.push(session.sessionKey))
    keys.forEach((key: string) => this.removeSession(key))
    this.mediaController.closeAll('hangup all')
    this.signalStateMachine.resetSession()
  }

  select(sessionKey: string): boolean {
    return this.mediaController.selectSession(sessionKey)
  }

  hold(sessionKey: string): boolean {
    return this.sendHoldSwitchNotice(sessionKey, true)
  }

  resume(sessionKey: string): boolean {
    return this.sendHoldSwitchNotice(sessionKey, false)
  }

  getSession(sessionKey: string): RtcWebRtcCallSessionInfo | undefined {
    const session = this.findSession(sessionKey)
    return session ? this.copySession(session) : undefined
  }

  stop(): void {
    this.hangupAll()
    this.signalSession.close()
  }

  dispose(): void {
    this.stop()
    this.mediaController.dispose()
    this.sessions.clear()
    this.sessionIds.clear()
    this.config = undefined
  }

  private bindSignalSession(): void {
    this.signalSession.setListener({
      onMessage: (message: RtcWebRtcSignalMessage) => {
        this.handleMessage(message)
      },
      onRegister: (message: RtcWebRtcSignalMessage, server?: RtcServerInfo) => {
        if (message.status !== 200 || !server) {
          this.listener.onError?.(message.result || 'register failed')
          return
        }
        this.server = server
        if (server.iceConf) {
          try {
            this.mediaController.setIceServers(JSON.parse(server.iceConf))
          } catch (error) {
            this.listener.onError?.('invalid ice config: ' + JSON.stringify(error))
          }
        }
        this.listener.onRegistered?.(server)
        const pending = this.pendingStartSessionKeys.slice()
        this.pendingStartSessionKeys = []
        pending.forEach((sessionKey: string) => {
          this.startCall(sessionKey)
        })
      },
      onError: (message: string) => this.listener.onError?.(message)
    })
  }

  private handleMessage(message: RtcWebRtcSignalMessage): void {
    if (message.eventName === 'c__register') {
      return
    }
    if (message.eventName === 'c__invite') {
      const payload = this.parsePayload(message.data)
      if (!payload) {
        return
      }
      const session = this.upsertSession(payload.commonRequest, true)
      this.registerSignalAliases(payload.commonRequest)
      this.listener.onIncoming?.(this.copySession(session))
      return
    }
    if (message.eventName === 'c__sdp') {
      const payload = this.parsePayload(message.data)
      if (!payload) {
        return
      }
      const session = this.upsertSession(payload.commonRequest, true, payload.rtcUid)
      this.registerSignalAliases(payload.commonRequest, payload.rtcUid)
      const sdpData: RtcSdpSignalData = {
        commonRequest: payload.commonRequest,
        sdp: payload.sdp || '',
        sdpType: payload.sdpType || '',
        rtcUid: payload.rtcUid || ''
      }
      this.signalStateMachine.handleSdp(sdpData, {
        local: this.config?.local,
        remote: {
          number: session.targetNumber,
          displayName: session.targetName,
          clientType: session.remoteClientType
        },
        mode: session.mode,
        decodeSdp: (value: string) => this.decodeSdp(value),
        encodeSdp: (value: string) => this.encodeSdp(value),
        buildAnswerCommonRequest: (inbound: RtcCommonRequest, context: RtcWebRtcSignalContext) =>
          this.buildAnswerCommonRequest(inbound, context, session)
      }).then((result) => {
        this.listener.onLog?.(`rtc_route_sdp channelType=${result.role}` +
          ` sdpType=${payload.sdpType || ''}` +
          ` handled=${result.handled} reason=${result.reason}`)
        if (result.handled && result.role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
          this.listener.onPublishReady?.(session.sessionKey, this.copySession(session))
        }
      }).catch((error: Error) => {
          this.listener.onError?.('handle sdp failed: ' + JSON.stringify(error))
        })
      return
    }
    if (message.eventName === 'c__candidate') {
      const payload = this.parsePayload(message.data)
      if (!payload) {
        return
      }
      const session = this.upsertSession(payload.commonRequest, true, payload.rtcUid)
      this.registerSignalAliases(payload.commonRequest, payload.rtcUid)
      const candidateData: RtcCandidateSignalData = {
        commonRequest: payload.commonRequest,
        candidateType: 'candidate',
        candidate: payload.candidate || '',
        sdpMLineIndex: payload.sdpMLineIndex,
        sdpMid: payload.sdpMid,
        rtcUid: payload.rtcUid || ''
      }
      this.signalStateMachine.handleCandidate(candidateData)
        .then((result) => {
          this.listener.onLog?.(`rtc_route_candidate channelType=${result.role}` +
            ` handled=${result.handled} reason=${result.reason}`)
        })
        .catch((error: Error) => {
          this.listener.onError?.('handle candidate failed: ' + JSON.stringify(error))
        })
      return
    }
    if (message.eventName === 'c__answer') {
      const payload = this.parsePayload(message.data)
      const session = payload ? this.upsertSession(payload.commonRequest, true, payload.rtcUid) : undefined
      if (session) {
        const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(payload?.rtcUid || '')
        this.listener.onLog?.(`rtc_answer_state channelType=${scope.channelType} state=notice`)
        this.listener.onAnswerNotice?.(this.copySession(session))
      }
      return
    }
    if (message.eventName === 'c__hangup' || message.eventName === 'c__offline') {
      const payload = this.parsePayload(message.data)
      const session = payload ? this.resolvePayloadSession(payload) : undefined
      if (this.shouldIgnoreTerminalEchoAfterLocalSingleHangup(payload, session)) {
        this.listener.onLog?.('ignore terminal echo after local single hangup')
      } else if (session) {
        const key = session.sessionKey
        this.removeSession(key)
        this.listener.onHangup?.(key, false)
      } else if (payload?.isAll === true) {
        this.hangupAll()
        this.listener.onHangup?.('', true)
      } else if (!payload || !this.hasPayloadSessionIdentity(payload)) {
        if (this.sessions.size <= 1) {
          this.hangupAll()
          this.listener.onHangup?.('', true)
        } else {
          this.listener.onLog?.('ignore terminal signal without target in multi-call')
        }
      } else {
        this.listener.onLog?.('ignore terminal signal for unknown session')
      }
      return
    }
    if (message.eventName === 'c__broadcast') {
      const holdNotice = this.parseHoldSwitchNotice(message.data)
      if (holdNotice) {
        const session = this.findSession(holdNotice.info)
        if (session) {
          this.listener.onHoldChange?.(session.sessionKey, holdNotice.type === 'hold')
          return
        }
        this.listener.onLog?.('ignore hold broadcast for unknown session=' + holdNotice.info)
      }
      this.listener.onBroadcast?.(message)
    }
  }

  private upsertSession(
    commonRequest: RtcCommonRequest,
    incoming: boolean,
    rawRtcUid: string = ''
  ): RtcWebRtcCallSessionInfo {
    const sessionId = this.normalizeSessionId(commonRequest.uuid)
    const localNumber = this.config?.local.number || this.config?.identity.number || ''
    const targetNumber = this.resolveRemoteNumber(commonRequest, localNumber)
    const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(rawRtcUid)
    const rtcSessionId = this.normalizeSessionId(scope.rtcUid)
    const existingKey = this.sessionIds.get(sessionId) ||
      this.sessionIds.get(rtcSessionId) ||
      this.findUniqueSessionKeyByTarget(targetNumber, incoming)
    const sessionKey = existingKey || sessionId
    let session = this.sessions.get(sessionKey)
    if (!session) {
      session = {
        sessionKey,
        sessionId,
        uid: sessionId,
        targetNumber,
        targetName: this.resolveRemoteName(commonRequest, targetNumber),
        remoteClientType: commonRequest.clientType || '',
        mode: commonRequest.isVideo === true ? RtcCallMode.VIDEO : RtcCallMode.AUDIO,
        incoming,
        commonRequest
      }
      this.sessions.set(sessionKey, session)
    } else {
      session.targetNumber = targetNumber || session.targetNumber
      session.targetName = this.resolveRemoteName(commonRequest, session.targetNumber) || session.targetName
      session.remoteClientType = commonRequest.clientType || session.remoteClientType
      session.mode = commonRequest.isVideo === true ? RtcCallMode.VIDEO : session.mode
      session.commonRequest = commonRequest
    }
    this.sessionIds.set(sessionId, sessionKey)
    if (rtcSessionId) {
      this.sessionIds.set(rtcSessionId, sessionKey)
    }
    const mediaOptions: RtcWebRtcMediaSessionOptions = {
      sessionKey: session.sessionKey,
      sessionId,
      uid: session.uid,
      targetNumber: session.targetNumber,
      targetName: session.targetName,
      remoteClientType: session.remoteClientType,
      rtcUid: scope.rtcUid,
      mode: session.mode
    }
    this.mediaController.registerSession(mediaOptions)
    return session
  }

  private removeSession(sessionKey: string): void {
    const session = this.findSession(sessionKey)
    if (!session) {
      return
    }
    const preservePublish = true
    this.mediaController.closeSession(session.sessionKey, 'signal session ended', { preservePublish })
    const sessionIdRemovals: string[] = []
    this.sessionIds.forEach((mappedKey: string, sessionId: string) => {
      if (mappedKey === session.sessionKey) {
        sessionIdRemovals.push(sessionId)
      }
    })
    sessionIdRemovals.forEach((sessionId: string) => {
      this.signalStateMachine.unregisterSession(sessionId, { preservePublish })
      this.sessionIds.delete(sessionId)
    })
    this.sessions.delete(session.sessionKey)
    this.pendingStartSessionKeys =
      this.pendingStartSessionKeys.filter((item: string) => item !== session.sessionKey)
    if (this.sessions.size === 0) {
      this.signalStateMachine.resetSession()
    }
  }

  private rememberLocalSingleHangup(session: RtcWebRtcCallSessionInfo): void {
    this.recentLocalSingleHangup = {
      sessionKey: session.sessionKey,
      sessionId: session.sessionId,
      targetNumber: session.targetNumber,
      at: Date.now()
    }
  }

  private getRecentLocalSingleHangup(): RtcRecentLocalSingleHangup | undefined {
    const recent = this.recentLocalSingleHangup
    if (!recent) {
      return undefined
    }
    if (Date.now() - recent.at > this.localSingleHangupEchoGuardMs) {
      this.recentLocalSingleHangup = undefined
      return undefined
    }
    return recent
  }

  private shouldIgnoreTerminalEchoAfterLocalSingleHangup(
    payload?: RtcSignalPayload,
    resolvedSession?: RtcWebRtcCallSessionInfo
  ): boolean {
    const recent = this.getRecentLocalSingleHangup()
    if (!recent || this.sessions.size === 0) {
      return false
    }
    if (!payload) {
      return true
    }
    if (!this.hasPayloadSessionIdentity(payload)) {
      return true
    }
    if (payload.isAll === true && !this.payloadMatchesRecentLocalSingleHangup(payload, recent)) {
      return true
    }
    if (this.payloadMatchesRecentLocalSingleHangup(payload, recent)) {
      return true
    }
    return !!resolvedSession && resolvedSession.sessionKey !== recent.sessionKey
  }

  private payloadMatchesRecentLocalSingleHangup(
    payload: RtcSignalPayload,
    recent: RtcRecentLocalSingleHangup
  ): boolean {
    const commonRequest = payload.commonRequest
    const payloadSessionId = this.normalizeSessionId(commonRequest.uuid || '')
    if (payloadSessionId && (payloadSessionId === recent.sessionKey || payloadSessionId === recent.sessionId)) {
      return true
    }
    const rtcSessionId = this.normalizeSessionId(payload.rtcUid || '')
    if (rtcSessionId && (rtcSessionId === recent.sessionKey || rtcSessionId === recent.sessionId)) {
      return true
    }
    const localNumber = this.config?.local.number || this.config?.identity.number || ''
    const targetNumber = this.resolveRemoteNumber(commonRequest, localNumber)
    return !!targetNumber && targetNumber === recent.targetNumber
  }

  private sendApply(applyType: number, session: RtcWebRtcCallSessionInfo, isAll: boolean): void {
    const data: RtcApplySignalData = {
      applyType,
      toIp: this.server.serveIp,
      isAll,
      commonRequest: this.buildApplyCommonRequest(
        session.sessionId,
        {
          number: session.targetNumber,
          displayName: session.targetName,
          clientType: session.remoteClientType
        },
        session.mode
      )
    }
    this.signalSession.sendSignal(this.wrapSignal('s__apply', data))
  }

  private sendHoldSwitchNotice(sessionKey: string, isHold: boolean): boolean {
    const session = this.findSession(sessionKey)
    if (!session || !this.server.serveNumber) {
      return false
    }
    const notice: RtcHoldSwitchNotice = {
      type: isHold ? 'hold' : 'resume',
      info: session.sessionId
    }
    const broadcast: RtcBroadcastSignalData = {
      data: JSON.stringify(notice)
    }
    this.signalSession.sendSignal(this.wrapSignal('s__broadcast', broadcast))
    return true
  }

  private sendSignal(message: RtcSignalMessage, _context: RtcWebRtcSignalContext): void {
    this.signalSession.sendSignal({
      eventName: message.eventName,
      number: this.server.serveNumber,
      clientType: 'serve_node',
      displayName: this.server.serveDisplayName,
      data: message.data
    })
  }

  private wrapSignal(
    eventName: string,
    data: RtcApplySignalData | RtcBroadcastSignalData
  ): RtcSignalMessage {
    return {
      eventName,
      number: this.server.serveNumber,
      clientType: 'serve_node',
      displayName: this.server.serveDisplayName,
      data: JSON.stringify(data)
    }
  }

  private buildApplyCommonRequest(
    sessionId: string,
    target: RtcPeerIdentity,
    mode: RtcCallMode
  ): RtcCommonRequest {
    const local = this.config?.local || this.config?.identity || { number: '' }
    return {
      uuid: this.normalizeSessionId(sessionId),
      locId: local.locId || '',
      hospitalId: local.hospitalId || '',
      number: local.number,
      displayName: local.displayName || local.number,
      clientType: local.clientType || '',
      identity: local.identity || '',
      to: target.number,
      toName: target.displayName || target.number,
      from: local.number,
      fromName: local.displayName || local.number,
      grpcFrom: local.number,
      grpcTo: this.server.serveNumber,
      isVideo: mode === RtcCallMode.VIDEO
    }
  }

  private buildAnswerCommonRequest(
    inbound: RtcCommonRequest,
    context: RtcWebRtcSignalContext,
    session: RtcWebRtcCallSessionInfo
  ): RtcCommonRequest {
    const local = this.config?.local || this.config?.identity || { number: '' }
    const grpcFrom = (inbound.grpcFrom || '').trim()
    return {
      uuid: context.sessionId,
      locId: local.locId || inbound.locId || '',
      hospitalId: local.hospitalId || inbound.hospitalId || '',
      number: local.number,
      displayName: local.displayName || local.number,
      clientType: local.clientType || '',
      identity: local.identity || inbound.identity || '',
      to: local.number,
      toName: local.displayName || local.number,
      from: local.number,
      fromName: local.displayName || local.number,
      grpcFrom: local.number,
      grpcTo: (grpcFrom && grpcFrom !== local.number ? grpcFrom : '') || this.server.serveNumber,
      isVideo: session.mode === RtcCallMode.VIDEO
    }
  }

  private resolveRemoteNumber(commonRequest: RtcCommonRequest, localNumber: string): string {
    const candidates = [
      commonRequest.from || '',
      commonRequest.to || '',
      commonRequest.number || '',
      commonRequest.grpcFrom || '',
      commonRequest.grpcTo || ''
    ]
    for (let i = 0; i < candidates.length; i += 1) {
      const value = candidates[i].trim()
      if (value && value !== localNumber) {
        return value
      }
    }
    return ''
  }

  private resolveRemoteName(commonRequest: RtcCommonRequest, remoteNumber: string): string {
    if (remoteNumber === (commonRequest.from || '').trim()) {
      return commonRequest.fromName || remoteNumber
    }
    if (remoteNumber === (commonRequest.to || '').trim()) {
      return commonRequest.toName || remoteNumber
    }
    return commonRequest.displayName || remoteNumber
  }

  private findSession(keyOrId: string): RtcWebRtcCallSessionInfo | undefined {
    const value = (keyOrId || '').trim()
    const direct = this.sessions.get(value)
    if (direct) {
      return direct
    }
    const key = this.sessionIds.get(this.normalizeSessionId(value))
    return key ? this.sessions.get(key) : undefined
  }

  private findUniqueSessionKeyByTarget(targetNumber: string, incoming: boolean): string {
    const target = (targetNumber || '').trim()
    if (!target) {
      return ''
    }
    const matches: RtcWebRtcCallSessionInfo[] = []
    this.sessions.forEach((session: RtcWebRtcCallSessionInfo) => {
      if (session.targetNumber === target && session.incoming === incoming) {
        matches.push(session)
      }
    })
    return matches.length === 1 ? matches[0].sessionKey : ''
  }

  private findUniqueSessionByTarget(targetNumber: string): RtcWebRtcCallSessionInfo | undefined {
    const target = (targetNumber || '').trim()
    if (!target) {
      return undefined
    }
    const matches: RtcWebRtcCallSessionInfo[] = []
    this.sessions.forEach((session: RtcWebRtcCallSessionInfo) => {
      if (session.targetNumber === target) {
        matches.push(session)
      }
    })
    return matches.length === 1 ? matches[0] : undefined
  }

  private resolvePayloadSession(payload: RtcSignalPayload): RtcWebRtcCallSessionInfo | undefined {
    const session = this.findSession(payload.commonRequest.uuid || '') ||
      this.findSession(payload.rtcUid || '')
    if (session) {
      return session
    }
    const localNumber = this.config?.local.number || this.config?.identity.number || ''
    const targetNumber = this.resolveRemoteNumber(payload.commonRequest, localNumber)
    return this.findUniqueSessionByTarget(targetNumber)
  }

  private hasPayloadSessionIdentity(payload: RtcSignalPayload): boolean {
    const localNumber = this.config?.local.number || this.config?.identity.number || ''
    return !!((payload.commonRequest.uuid || '').trim() ||
      (payload.rtcUid || '').trim() ||
      this.resolveRemoteNumber(payload.commonRequest, localNumber))
  }

  private registerSignalAliases(commonRequest: RtcCommonRequest, rawRtcUid: string = ''): void {
    const sessionId = this.normalizeSessionId(commonRequest.uuid)
    if (sessionId) {
      this.signalStateMachine.registerSession(sessionId)
    }
    const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(rawRtcUid)
    const rtcSessionId = this.normalizeSessionId(scope.rtcUid)
    if (rtcSessionId && rtcSessionId !== sessionId) {
      this.signalStateMachine.registerSession(rtcSessionId)
    }
  }

  private parsePayload(data: string): RtcSignalPayload | undefined {
    if (!data) {
      return undefined
    }
    try {
      return JSON.parse(data) as RtcSignalPayload
    } catch (error) {
      this.listener.onError?.('invalid signal payload: ' + JSON.stringify(error))
      return undefined
    }
  }

  private parseHoldSwitchNotice(data: string): RtcHoldSwitchNotice | undefined {
    if (!data) {
      return undefined
    }
    try {
      const wrapper = JSON.parse(data) as RtcBroadcastSignalData | RtcHoldSwitchNotice
      const nested = (wrapper as RtcBroadcastSignalData).data
      const notice = nested ?
        JSON.parse(nested) as RtcHoldSwitchNotice :
        wrapper as RtcHoldSwitchNotice
      if (notice.type !== 'hold' && notice.type !== 'resume') {
        return undefined
      }
      return {
        type: notice.type,
        info: this.normalizeSessionId(notice.info || '')
      }
    } catch (_error) {
      return undefined
    }
  }

  private encodeSdp(sdp: string): string {
    return RtcWebRtcTrackIdentityCodec.encodeLatin1(JSON.stringify({ data: sdp }))
  }

  private decodeSdp(raw: string): string {
    if (!raw) {
      return ''
    }
    try {
      const wrapper = JSON.parse(RtcWebRtcTrackIdentityCodec.decodeLatin1(raw)) as Record<string, string>
      return wrapper.data || raw
    } catch (_error) {
      return raw
    }
  }

  private normalizeSessionId(value: string): string {
    return (value || '').split(',')[0].trim()
  }

  private copySession(session: RtcWebRtcCallSessionInfo): RtcWebRtcCallSessionInfo {
    return {
      sessionKey: session.sessionKey,
      sessionId: session.sessionId,
      uid: session.uid,
      targetNumber: session.targetNumber,
      targetName: session.targetName,
      remoteClientType: session.remoteClientType,
      mode: session.mode,
      incoming: session.incoming,
      commonRequest: session.commonRequest
    }
  }
}
