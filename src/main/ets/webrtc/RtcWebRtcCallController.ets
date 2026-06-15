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
  RtcWebRtcRtcScope,
  RtcWebRtcSignalContext,
  RtcWebRtcSignalStateMachine
} from '../signaling/RtcWebRtcSignalStateMachine'
import { RtcWebRtcMediaController, RtcWebRtcMediaSessionOptions } from './RtcWebRtcMediaController'
import { RtcWebRtcTrackIdentityCodec } from './RtcWebRtcTrackIdentity'
import { RtcCallLifecycleStore } from '../core/RtcCallLifecycleStore'

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

interface RtcParsedHoldChange {
  sessionId: string
  isHold: boolean
}

const RTC_APPLY_INVITE: number = 1
const RTC_APPLY_ANSWER: number = 2
const RTC_APPLY_HANGUP: number = 3
const RTC_APPLY_SWITCH: number = 4

export class RtcWebRtcCallController {
  private signalSession: RtcWebRtcSignalSession
  private signalStateMachine: RtcWebRtcSignalStateMachine
  private mediaController: RtcWebRtcMediaController
  private lifecycle: RtcCallLifecycleStore = new RtcCallLifecycleStore()
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
    this.sendApply(RTC_APPLY_INVITE, session, false)
    return true
  }

  accept(sessionKey: string): boolean {
    const session = this.findSession(sessionKey)
    if (!session || !this.server.serveNumber) {
      return false
    }
    this.sendApply(RTC_APPLY_ANSWER, session, false)
    return true
  }

  hangup(sessionKey: string): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    if (this.server.serveNumber) {
      this.sendApply(RTC_APPLY_HANGUP, session, false)
    }
    this.rememberLocalSingleHangup(session)
    this.removeSession(session.sessionKey, true)
    return true
  }

  hangupAll(): void {
    this.recentLocalSingleHangup = undefined
    const first = this.sessions.values().next()
    if (!first.done && this.server.serveNumber) {
      this.sendApply(RTC_APPLY_HANGUP, first.value, true)
    }
    this.closeAllLocalSessions('hangup all')
  }

  select(sessionKey: string): boolean {
    return this.mediaController.selectSession(sessionKey)
  }

  hold(sessionKey: string): boolean {
    return this.sendHoldSwitchApply(sessionKey, 'hold')
  }

  resume(sessionKey: string): boolean {
    return this.sendHoldSwitchApply(sessionKey, 'resume')
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
        this.lifecycle.markPhase(session.uid || session.sessionId || session.sessionKey, 'answered', false)
        this.listener.onLog?.(`rtc_answer_state channelType=${scope.channelType} state=notice`)
        this.listener.onAnswerNotice?.(this.copySession(session))
      }
      return
    }
    if (message.eventName === 'c__hangup' || message.eventName === 'c__offline') {
      const payload = this.parsePayload(message.data)
      const session = payload ? this.resolvePayloadSession(payload) : undefined
      const keepAlive = this.shouldKeepAliveAfterRemoteHangup(message.eventName, payload)
      const useHangupTerminalPolicy = message.eventName === 'c__hangup' && !keepAlive
      if (!useHangupTerminalPolicy && this.shouldIgnoreTerminalEchoAfterLocalSingleHangup(payload, session)) {
        this.listener.onLog?.('ignore terminal echo after local single hangup')
      } else if (session) {
        const key = session.sessionKey
        const preservePublish = keepAlive || this.sessions.size > 1
        if (keepAlive) {
          this.removeSession(key, true)
          this.listener.onHangup?.(key, false)
        } else if (message.eventName === 'c__hangup') {
          this.removeSession(key, preservePublish)
          this.recentLocalSingleHangup = undefined
          this.listener.onHangup?.(key, false)
        } else {
          this.removeSession(key, this.sessions.size > 1)
          this.listener.onHangup?.(key, false)
        }
      } else if (keepAlive) {
        this.listener.onLog?.('keep call page after remote hangup because other calls remain')
      } else if (message.eventName === 'c__hangup') {
        this.closeAllLocalSessions('remote hangup complete')
        this.listener.onHangup?.('', true)
      } else if (payload?.isAll === true) {
        this.closeAllLocalSessions('remote terminal all')
        this.listener.onHangup?.('', true)
      } else if (!payload || !this.hasPayloadSessionIdentity(payload)) {
        if (this.sessions.size <= 1) {
          this.closeAllLocalSessions('remote terminal last')
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
      const holdChanges = this.parseHoldSwitchNotice(message.data)
      if (holdChanges.length > 0) {
        let handled = false
        holdChanges.forEach((holdChange: RtcParsedHoldChange) => {
          const session = this.resolveHoldChangeSession(holdChange.sessionId)
          if (session) {
            handled = true
            this.listener.onHoldChange?.(session.sessionKey, holdChange.isHold)
          } else {
            this.listener.onLog?.('ignore hold broadcast for unknown session=' + holdChange.sessionId)
          }
        })
        if (handled) {
          return
        }
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
    const isCallout = this.isLocalCallout(commonRequest, localNumber)
    const sessionIncoming = incoming && !isCallout
    const scope = RtcWebRtcSignalStateMachine.decodeRtcScope(rawRtcUid)
    const rtcSessionId = this.normalizeSessionId(scope.rtcUid)
    const existingKey = this.sessionIds.get(sessionId) ||
      this.sessionIds.get(rtcSessionId) ||
      this.findUniqueSessionKeyByTarget(targetNumber)
    const sessionKey = this.resolveSessionKeyForUpsert(existingKey, sessionId)
    let session = this.sessions.get(sessionKey)
    if (!session) {
      session = existingKey ? this.sessions.get(existingKey) : undefined
    }
    if (session && existingKey && sessionKey !== existingKey) {
      this.migrateSessionKey(existingKey, sessionKey, session)
    }
    if (!session) {
      session = {
        sessionKey,
        sessionId,
        uid: sessionId,
        targetNumber,
        targetName: this.resolveRemoteName(commonRequest, targetNumber),
        remoteClientType: commonRequest.clientType || '',
        mode: commonRequest.isVideo === true ? RtcCallMode.VIDEO : RtcCallMode.AUDIO,
        incoming: sessionIncoming,
        commonRequest
      }
      this.sessions.set(sessionKey, session)
    } else {
      const oldSessionId = session.sessionId
      session.targetNumber = targetNumber || session.targetNumber
      session.targetName = this.resolveRemoteName(commonRequest, session.targetNumber) || session.targetName
      session.remoteClientType = commonRequest.clientType || session.remoteClientType
      session.mode = commonRequest.isVideo === true ? RtcCallMode.VIDEO : session.mode
      session.sessionId = sessionId || session.sessionId
      session.uid = session.sessionId || session.uid
      session.incoming = sessionIncoming
      session.commonRequest = commonRequest
      if (oldSessionId && oldSessionId !== session.sessionId) {
        this.sessionIds.set(oldSessionId, session.sessionKey)
      }
    }
    if (sessionId) {
      this.sessionIds.set(sessionId, sessionKey)
    }
    if (rtcSessionId) {
      this.sessionIds.set(rtcSessionId, sessionKey)
    }
    this.upsertLifecycleSession(session, commonRequest, sessionIncoming, scope)
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

  private removeSession(sessionKey: string, preservePublish: boolean): void {
    const session = this.findSession(sessionKey)
    if (!session) {
      return
    }
    this.mediaController.closeSession(session.sessionKey, 'signal session ended', { preservePublish })
    this.lifecycle.remove(session.uid || session.sessionId || session.sessionKey)
    if (session.sessionKey !== session.uid && session.sessionKey !== session.sessionId) {
      this.lifecycle.remove(session.sessionKey)
    }
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

  private closeAllLocalSessions(reason: string): void {
    this.recentLocalSingleHangup = undefined
    this.mediaController.closeAll(reason)
    this.sessions.clear()
    this.sessionIds.clear()
    this.lifecycle.clear()
    this.pendingStartSessionKeys = []
    this.signalStateMachine.resetSession()
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

  private shouldKeepAliveAfterRemoteHangup(eventName: string, payload?: RtcSignalPayload): boolean {
    return eventName === 'c__hangup' && payload?.isHangUp === false
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

  private sendHoldSwitchApply(sessionKey: string, action: string): boolean {
    const session = this.resolveHoldSwitchSession(sessionKey)
    if (!session) {
      this.logHoldSwitchSend(action, sessionKey, '', false, this.server.serveNumber.length > 0, false,
        'session not found')
      return false
    }
    if (!this.server.serveNumber) {
      this.logHoldSwitchSend(action, sessionKey, session.sessionKey, true, false, false, 'server not registered')
      return false
    }
    this.sendApply(RTC_APPLY_SWITCH, session, false)
    this.logHoldSwitchSend(action, sessionKey, session.sessionKey, true, true, true, 'sent')
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

  private resolveSessionKeyForUpsert(existingKey: string, sessionId: string): string {
    if (!existingKey) {
      return sessionId
    }
    if (!sessionId || existingKey === sessionId) {
      return existingKey
    }
    const existing = this.sessions.get(existingKey)
    if (!existing) {
      return sessionId
    }
    return sessionId
  }

  private migrateSessionKey(
    oldKey: string,
    newKey: string,
    session: RtcWebRtcCallSessionInfo
  ): void {
    if (!oldKey || !newKey || oldKey === newKey) {
      return
    }
    this.sessions.delete(oldKey)
    session.sessionKey = newKey
    this.sessions.set(newKey, session)
    this.sessionIds.forEach((mappedKey: string, sessionId: string) => {
      if (mappedKey === oldKey) {
        this.sessionIds.set(sessionId, newKey)
      }
    })
    this.sessionIds.set(oldKey, newKey)
    this.pendingStartSessionKeys = this.pendingStartSessionKeys.map((item: string) =>
      item === oldKey ? newKey : item)
    this.lifecycle.remove(oldKey)
    this.mediaController.rekeySession(oldKey, newKey)
  }

  private isLocalCallout(commonRequest: RtcCommonRequest, localNumber: string): boolean {
    const local = (localNumber || '').trim()
    if (!local) {
      return false
    }
    return RtcWebRtcCallController.splitNumbers(commonRequest.from || '').indexOf(local) >= 0
  }

  private findUniqueSessionKeyByTarget(targetNumber: string): string {
    const target = (targetNumber || '').trim()
    if (!target) {
      return ''
    }
    const matches: RtcWebRtcCallSessionInfo[] = []
    this.sessions.forEach((session: RtcWebRtcCallSessionInfo) => {
      if (session.targetNumber === target) {
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

  private resolveHoldChangeSession(sessionIdOrNumber: string): RtcWebRtcCallSessionInfo | undefined {
    const session = this.findSession(sessionIdOrNumber)
    if (session) {
      return session
    }
    return this.findUniqueSessionByTarget(sessionIdOrNumber)
  }

  private resolveHoldSwitchSession(sessionIdOrNumber: string): RtcWebRtcCallSessionInfo | undefined {
    return this.resolveHoldChangeSession(sessionIdOrNumber)
  }

  private resolvePayloadSession(payload: RtcSignalPayload): RtcWebRtcCallSessionInfo | undefined {
    const localNumber = this.config?.local.number || this.config?.identity.number || ''
    const targetNumber = this.resolveRemoteNumber(payload.commonRequest, localNumber)
    const resolved = this.lifecycle.resolveUidOrUniqueNumber(
      payload.commonRequest.uuid || '',
      targetNumber,
      'resolve signal target',
      true
    )
    const lifecycleSession = resolved.handled ? this.findSession(resolved.uid) : undefined
    if (lifecycleSession) {
      return lifecycleSession
    }
    const session = this.findSession(payload.commonRequest.uuid || '') ||
      this.findSession(payload.rtcUid || '')
    if (session) {
      return session
    }
    return this.findUniqueSessionByTarget(targetNumber)
  }

  private upsertLifecycleSession(
    session: RtcWebRtcCallSessionInfo,
    commonRequest: RtcCommonRequest,
    incoming: boolean,
    scope: RtcWebRtcRtcScope
  ): void {
    const uid = session.uid || session.sessionId || session.sessionKey
    if (!uid) {
      return
    }
    this.lifecycle.upsertCall({
      uid,
      number: session.targetNumber,
      name: session.targetName,
      direction: incoming ? 'incoming' : 'outgoing',
      phase: incoming ? 'incoming' : 'outgoing',
      mode: session.mode,
      from: commonRequest.from || '',
      to: commonRequest.to || '',
      fromName: commonRequest.fromName || '',
      toName: commonRequest.toName || '',
      clientType: commonRequest.clientType || '',
      locId: commonRequest.locId || '',
      hospitalId: commonRequest.hospitalId || '',
      isCalling: !incoming
    })
    if (scope.rtcUid) {
      this.lifecycle.upsertPeer(
        uid,
        scope.rtcUid,
        scope.channelType,
        commonRequest.from || '',
        commonRequest.to || ''
      )
    }
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

  private parseHoldSwitchNotice(data: string): RtcParsedHoldChange[] {
    if (!data) {
      return []
    }
    try {
      const wrapper = JSON.parse(data) as RtcBroadcastSignalData | RtcHoldSwitchNotice
      const nested = (wrapper as RtcBroadcastSignalData).data
      const notice = nested ?
        JSON.parse(nested) as RtcHoldSwitchNotice :
        wrapper as RtcHoldSwitchNotice
      return this.toHoldChanges(notice)
    } catch (_error) {
      return []
    }
  }

  private toHoldChanges(notice: RtcHoldSwitchNotice): RtcParsedHoldChange[] {
    const changes: RtcParsedHoldChange[] = []
    const info = notice.info
    if (typeof info === 'string') {
      const sessionId = this.normalizeSessionId(info)
      const isHold = this.resolveHoldState(notice)
      if (sessionId && isHold !== undefined) {
        changes.push({ sessionId, isHold })
      }
      return changes
    }
    if (info) {
      Object.keys(info).forEach((sessionId: string) => {
        const normalized = this.normalizeSessionId(sessionId)
        if (normalized) {
          changes.push({ sessionId: normalized, isHold: info[sessionId] === true })
        }
      })
      return changes
    }
    const uid = this.normalizeSessionId(notice.uid || '')
    const isHold = this.resolveHoldState(notice)
    if (uid && isHold !== undefined) {
      changes.push({ sessionId: uid, isHold })
    }
    return changes
  }

  private resolveHoldState(notice: RtcHoldSwitchNotice): boolean | undefined {
    if (notice.is_hold === true) {
      return true
    }
    if (notice.is_hold === false) {
      return false
    }
    if (notice.isHold === true) {
      return true
    }
    if (notice.isHold === false) {
      return false
    }
    const type = (notice.type || '').trim()
    if (type === 'hold') {
      return true
    }
    if (type === 'resume' || type === 'answer' || type === 'answered') {
      return false
    }
    const status = (notice.status || '').trim()
    if (status === 'hold') {
      return true
    }
    if (status === 'resume' || status === 'answer' || status === 'answered') {
      return false
    }
    return undefined
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

  private getSessionHash(sessionKey: string): string {
    const key = (sessionKey || '').trim()
    let hash = 0
    for (let i = 0; i < key.length; i += 1) {
      hash = (hash * 33 + key.charCodeAt(i)) % 60466176
    }
    let text = hash.toString(36)
    while (text.length < 6) {
      text = '0' + text
    }
    return text
  }

  private logHoldSwitchSend(
    action: string,
    targetKey: string,
    resolvedKey: string,
    hasSession: boolean,
    hasServer: boolean,
    sent: boolean,
    reason: string
  ): void {
    this.listener.onLog?.('rtc_hold_switch_send action=' + action +
      '|targetHash=' + this.getSessionHash(targetKey) +
      '|resolvedHash=' + this.getSessionHash(resolvedKey) +
      '|hasSession=' + hasSession +
      '|hasServer=' + hasServer +
      '|sent=' + sent +
      '|reason=' + reason)
  }

  private static splitNumbers(value: string): string[] {
    return (value || '').split(',').map((item: string) => item.trim()).filter((item: string) => item.length > 0)
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
