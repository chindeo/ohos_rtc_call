import webrtc, { ScalingMode, VideoRenderController } from './OhosWebRtc'
import { RtcAudioController, RtcVideoRendererAdapter } from '../audio/RtcAudioController'
import {
  RTC_PEER_SESSION_CHANNEL_SUBSCRIBE,
  RtcPeerSessionRegistry
} from '../core/RtcPeerSessionRegistry'
import { RtcCallMode, RtcPeerIdentity } from '../model/RtcCallConfig'
import { RtcCommonRequest, RtcSignalMessage } from '../model/RtcSignalTypes'
import {
  RTC_WEBRTC_PEER_ROLE_PUBLISH,
  RTC_WEBRTC_PEER_ROLE_SUBSCRIBE,
  RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE,
  RtcWebRtcIceCandidate,
  RtcWebRtcIceStats,
  RtcWebRtcPeerConnectionAdapter,
  RtcWebRtcPeerRole,
  RtcWebRtcSessionDescription,
  RtcWebRtcSignalContext,
  RtcWebRtcSignalStateMachine
} from '../signaling/RtcWebRtcSignalStateMachine'
import { RtcWebRtcVideoSourceOptions } from './RtcWebRtcConfig'
import {
  RtcWebRtcTrackIdentity,
  RtcWebRtcTrackIdentityCodec
} from './RtcWebRtcTrackIdentity'

export interface RtcWebRtcMediaSessionOptions {
  sessionKey: string
  sessionId: string
  uid?: string
  targetNumber: string
  targetName?: string
  remoteClientType?: string
  rtcUid?: string
  mode?: RtcCallMode
}

export interface RtcWebRtcMediaState {
  sessionKey: string
  sessionId: string
  uid?: string
  targetNumber: string
  rtcUid?: string
  channelType?: string
  mode: RtcCallMode
  localVideoReady?: boolean
  hasRemoteAudio: boolean
  hasRemoteVideo: boolean
  mediaConnected: boolean
}

export interface RtcWebRtcMediaControllerOptions {
  local: RtcPeerIdentity
  appVersion: string
  localVideoEnabled?: boolean
  audioController?: RtcAudioController
  peerRegistry?: RtcPeerSessionRegistry
  iceServers?: webrtc.RTCIceServer[]
  videoSource?: RtcWebRtcVideoSourceOptions
  onSendSignal?: (message: RtcSignalMessage, context: RtcWebRtcSignalContext) => void | Promise<void>
  onMediaStateChange?: (state: RtcWebRtcMediaState) => void
  onLog?: (message: string) => void
  onError?: (message: string) => void
}

export interface RtcWebRtcCloseSessionOptions {
  preservePublish?: boolean
}

export class RtcVideoSurfaceController implements RtcVideoRendererAdapter {
  private controller: VideoRenderController = new VideoRenderController()

  constructor() {
    this.controller.setScalingMode(ScalingMode.AspectFit)
  }

  getController(): VideoRenderController {
    return this.controller
  }

  setVideoTrack(videoTrack: webrtc.MediaStreamTrack | null): void {
    this.controller.setVideoTrack(videoTrack)
  }
}

class RtcWebRtcMediaSession {
  sessionKey: string = ''
  sessionId: string = ''
  uid: string = ''
  targetNumber: string = ''
  targetName: string = ''
  remoteClientType: string = ''
  rtcUid: string = ''
  mode: RtcCallMode = RtcCallMode.AUDIO
  hasRemoteAudio: boolean = false
  hasRemoteVideo: boolean = false
  mediaConnected: boolean = false
  remoteAudioTrack?: webrtc.MediaStreamTrack
  remoteVideoTrack?: webrtc.MediaStreamTrack
}

class RtcWebRtcPeerRecord {
  key: string
  role: RtcWebRtcPeerRole
  context: RtcWebRtcSignalContext
  pc: webrtc.RTCPeerConnection
  session?: RtcWebRtcMediaSession
  localCandidateCount: number = 0
  iceCheckingTimer?: number
  iceCheckingStartedAt: number = 0

  constructor(
    key: string,
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext,
    pc: webrtc.RTCPeerConnection,
    session?: RtcWebRtcMediaSession
  ) {
    this.key = key
    this.role = role
    this.context = context
    this.pc = pc
    this.session = session
  }
}

export class RtcWebRtcMediaController implements RtcWebRtcPeerConnectionAdapter {
  private local: RtcPeerIdentity
  private appVersion: string
  private localVideoEnabled: boolean
  private audioController: RtcAudioController
  private peerRegistry: RtcPeerSessionRegistry
  private pcConfig: webrtc.RTCConfiguration
  private videoSource: RtcWebRtcVideoSourceOptions
  private sessions: Map<string, RtcWebRtcMediaSession> = new Map()
  private sessionIds: Map<string, string> = new Map()
  private peers: Map<string, RtcWebRtcPeerRecord> = new Map()
  private activeSessionKey: string = ''
  private userMuted: boolean = false
  private heldSessionKeys: Map<string, boolean> = new Map()
  private sessionRemoteVideoRenderers: Map<string, RtcVideoRendererAdapter> = new Map()
  private onSendSignal?: (message: RtcSignalMessage, context: RtcWebRtcSignalContext) => void | Promise<void>
  private onMediaStateChange?: (state: RtcWebRtcMediaState) => void
  private onLog?: (message: string) => void
  private onError?: (message: string) => void
  private iceCheckingWarnMs: number = 10000

  constructor(options: RtcWebRtcMediaControllerOptions) {
    this.local = options.local
    this.appVersion = options.appVersion
    this.localVideoEnabled = options.localVideoEnabled === true
    this.audioController = options.audioController || new RtcAudioController()
    this.peerRegistry = options.peerRegistry || new RtcPeerSessionRegistry()
    this.pcConfig = { iceServers: options.iceServers || [] }
    this.videoSource = options.videoSource || {
      width: 640,
      height: 480,
      frameRate: 15,
      facingMode: 'user'
    }
    this.onSendSignal = options.onSendSignal
    this.onMediaStateChange = options.onMediaStateChange
    this.onLog = options.onLog
    this.onError = options.onError
  }

  setSignalSender(sender: (message: RtcSignalMessage, context: RtcWebRtcSignalContext) =>
    void | Promise<void>): void {
    this.onSendSignal = sender
  }

  setIceServers(iceServers: webrtc.RTCIceServer[]): void {
    this.pcConfig = { iceServers }
  }

  registerSession(options: RtcWebRtcMediaSessionOptions): void {
    const key = (options.sessionKey || options.uid || options.sessionId).trim()
    if (!key || !options.sessionId) {
      return
    }
    let session = this.sessions.get(key)
    if (!session) {
      session = new RtcWebRtcMediaSession()
      session.sessionKey = key
      this.sessions.set(key, session)
    }
    if (!session.sessionId) {
      session.sessionId = options.sessionId
    }
    session.uid = options.uid || session.uid
    session.targetNumber = options.targetNumber || session.targetNumber
    session.targetName = options.targetName || session.targetName
    session.remoteClientType = options.remoteClientType || session.remoteClientType
    session.rtcUid = options.rtcUid || session.rtcUid
    session.mode = options.mode || session.mode
    this.sessionIds.set(options.sessionId, key)
    if (!this.activeSessionKey) {
      this.selectSession(key)
    }
  }

  rekeySession(oldKey: string, newKey: string): boolean {
    const previous = (oldKey || '').trim()
    const next = (newKey || '').trim()
    if (!previous || !next || previous === next) {
      return false
    }
    const session = this.sessions.get(previous)
    if (!session || this.sessions.get(next)) {
      return false
    }
    this.sessions.delete(previous)
    session.sessionKey = next
    session.uid = next
    this.sessions.set(next, session)
    this.sessionIds.forEach((mappedKey: string, sessionId: string) => {
      if (mappedKey === previous) {
        this.sessionIds.set(sessionId, next)
      }
    })
    this.sessionIds.set(previous, next)
    if (this.activeSessionKey === previous) {
      this.activeSessionKey = next
    }
    const held = this.heldSessionKeys.get(previous)
    if (held !== undefined) {
      this.heldSessionKeys.delete(previous)
      this.heldSessionKeys.set(next, held)
    }
    const renderer = this.sessionRemoteVideoRenderers.get(previous)
    if (renderer) {
      this.sessionRemoteVideoRenderers.delete(previous)
      this.sessionRemoteVideoRenderers.set(next, renderer)
    }
    return true
  }

  selectSession(sessionKey: string): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    this.activeSessionKey = session.sessionKey
    this.audioController.setRemoteAudioTrack(session.remoteAudioTrack)
    this.audioController.setRemoteVideoTrack(session.remoteVideoTrack)
    this.applyLocalAudioState()
    return true
  }

  bindLocalVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    this.audioController.bindLocalVideoRenderer(renderer)
  }

  bindRemoteVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    this.audioController.bindRemoteVideoRenderer(renderer)
    if (this.activeSessionKey) {
      this.selectSession(this.activeSessionKey)
    }
  }

  bindSessionRemoteVideoRenderer(sessionKey: string, renderer?: RtcVideoRendererAdapter): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    const current = this.sessionRemoteVideoRenderers.get(session.sessionKey)
    if (current && current !== renderer) {
      this.clearRenderer(current)
    }
    if (!renderer) {
      this.sessionRemoteVideoRenderers.delete(session.sessionKey)
      return true
    }
    this.sessionRemoteVideoRenderers.set(session.sessionKey, renderer)
    this.setRendererTrack(renderer, session.remoteVideoTrack)
    return true
  }

  setMuted(muted: boolean): void {
    this.userMuted = muted
    this.applyLocalAudioState()
  }

  setHeld(sessionKey: string, isHold: boolean): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    if (isHold) {
      this.heldSessionKeys.set(session.sessionKey, true)
    } else {
      this.heldSessionKeys.delete(session.sessionKey)
    }
    if (this.activeSessionKey === session.sessionKey) {
      this.applyLocalAudioState()
    }
    return true
  }

  getMediaState(sessionKey: string): RtcWebRtcMediaState | undefined {
    const session = this.findSession(sessionKey)
    return session ? this.copyMediaState(session) : undefined
  }

  async ensurePeerConnection(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): Promise<void> {
    const key = this.getPeerKey(role, context)
    const current = this.peers.get(key)
    if (current && current.pc.signalingState !== 'closed') {
      return
    }
    const session = this.findSession(context.sessionId)
    if (role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE && !session) {
      throw new Error('subscribe session not registered: ' + context.sessionId)
    }
    if (!this.audioController.ensureReady()) {
      throw new Error('PeerConnectionFactory unavailable')
    }
    if (role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
      this.prepareLocalMedia(this.localVideoEnabled && session?.mode === RtcCallMode.VIDEO)
      if (session) {
        this.emitMediaState(session)
      }
    }
    const pcf = this.audioController.getPeerConnectionFactory()
    const pc = pcf?.createPeerConnection(this.pcConfig)
    if (!pc) {
      throw new Error('create PeerConnection failed')
    }
    const record = new RtcWebRtcPeerRecord(key, role, context, pc, session)
    this.peers.set(key, record)
    if (role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
      this.audioController.addLocalTracks(pc)
    } else if (session) {
      this.peerRegistry.routeSubscribeOffer(session.uid, session.targetNumber, context.rtcUid)
    }
    this.bindPeerEvents(record)
  }

  hasPeerConnection(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean {
    const record = this.peers.get(this.getPeerKey(role, context))
    return !!record && record.pc.signalingState !== 'closed'
  }

  isPeerConnectionCurrent(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): boolean {
    return this.hasPeerConnection(role, context)
  }

  async setRemoteDescription(
    role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    const record = this.requirePeer(role, context)
    await record.pc.setRemoteDescription({
      type: description.type as webrtc.RTCSdpType,
      sdp: description.sdp
    })
    if (record.session && role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE) {
      this.peerRegistry.markRemoteDescriptionApplied(
        record.session.uid,
        record.session.targetNumber,
        context.rtcUid
      )
    }
  }

  async addIceCandidate(
    role: RtcWebRtcPeerRole,
    candidate: RtcWebRtcIceCandidate,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    const record = this.requirePeer(role, context)
    const nativeCandidate: webrtc.RTCIceCandidateInit = {
      candidate: candidate.candidate
    }
    if (typeof candidate.sdpMLineIndex === 'number') {
      nativeCandidate.sdpMLineIndex = candidate.sdpMLineIndex
    }
    if (candidate.sdpMid) {
      nativeCandidate.sdpMid = candidate.sdpMid
    }
    await record.pc.addIceCandidate(nativeCandidate)
  }

  async createAnswer(
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext
  ): Promise<RtcWebRtcSessionDescription> {
    const answer = await this.requirePeer(role, context).pc.createAnswer()
    return { type: answer.type, sdp: answer.sdp || '' }
  }

  async setLocalDescription(
    role: RtcWebRtcPeerRole,
    description: RtcWebRtcSessionDescription,
    context: RtcWebRtcSignalContext
  ): Promise<void> {
    await this.requirePeer(role, context).pc.setLocalDescription({
      type: description.type as webrtc.RTCSdpType,
      sdp: description.sdp
    })
  }

  async getLocalDescription(
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext
  ): Promise<RtcWebRtcSessionDescription | undefined> {
    const local = this.requirePeer(role, context).pc.localDescription
    return local ? { type: local.type, sdp: local.sdp } : undefined
  }

  async getIceStats(
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext
  ): Promise<RtcWebRtcIceStats | undefined> {
    const pc = this.requirePeer(role, context).pc
    return {
      iceConnectionState: pc.iceConnectionState,
      bytesSent: 0,
      bytesReceived: 0
    }
  }

  async sendSignal(message: RtcSignalMessage, context: RtcWebRtcSignalContext): Promise<void> {
    await this.onSendSignal?.(message, context)
  }

  closeSession(
    sessionKey: string,
    reason: string = 'close session',
    options?: RtcWebRtcCloseSessionOptions
  ): boolean {
    const session = this.findSession(sessionKey)
    if (!session) {
      return false
    }
    const isLastSession = this.sessions.size === 1
    const preservePublish = options?.preservePublish === true
    const removals: string[] = []
    this.peers.forEach((record: RtcWebRtcPeerRecord, key: string) => {
      if (isLastSession || record.session?.sessionKey === session.sessionKey) {
        if (preservePublish && record.role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
          this.log(`preserve publish peer reason=${reason}`)
          return
        }
        this.closePeer(record, reason)
        removals.push(key)
      }
    })
    removals.forEach((key: string) => this.peers.delete(key))
    this.peerRegistry.removeByTargetOrUid(session.uid || session.targetNumber)
    const sessionIdRemovals: string[] = []
    this.sessionIds.forEach((mappedKey: string, sessionId: string) => {
      if (mappedKey === session.sessionKey) {
        sessionIdRemovals.push(sessionId)
      }
    })
    sessionIdRemovals.forEach((sessionId: string) => this.sessionIds.delete(sessionId))
    this.sessions.delete(session.sessionKey)
    this.heldSessionKeys.delete(session.sessionKey)
    this.clearSessionRemoteVideoRenderer(session.sessionKey)
    if (isLastSession) {
      this.resetMediaState(session)
      this.audioController.releaseLocalVideo()
      this.emitMediaState(session)
    }
    if (this.activeSessionKey === session.sessionKey) {
      const next = this.sessions.values().next()
      this.activeSessionKey = next.done ? '' : next.value.sessionKey
      if (this.activeSessionKey) {
        this.selectSession(this.activeSessionKey)
      } else {
        this.audioController.clearRemoteMedia()
      }
    }
    return true
  }

  closeAll(reason: string = 'close all'): void {
    this.peers.forEach((record: RtcWebRtcPeerRecord) => this.closePeer(record, reason))
    this.peers.clear()
    this.audioController.releaseLocalVideo()
    this.sessions.forEach((session: RtcWebRtcMediaSession) => {
      this.resetMediaState(session)
      this.emitMediaState(session)
    })
    this.sessions.clear()
    this.sessionIds.clear()
    this.heldSessionKeys.clear()
    this.sessionRemoteVideoRenderers.forEach((renderer: RtcVideoRendererAdapter) => {
      this.clearRenderer(renderer)
    })
    this.sessionRemoteVideoRenderers.clear()
    this.activeSessionKey = ''
    this.audioController.cleanupRtcCallResources(reason)
  }

  dispose(): void {
    this.closeAll('dispose')
  }

  static isMediaConnected(
    mode: RtcCallMode,
    remoteClientType: string,
    hasRemoteAudio: boolean,
    hasRemoteVideo: boolean
  ): boolean {
    if (mode === RtcCallMode.AUDIO || RtcWebRtcMediaController.isAudioOnlyDevice(remoteClientType)) {
      return hasRemoteAudio
    }
    return hasRemoteVideo
  }

  static isLocalVideoReady(readyState?: string): boolean {
    return readyState === 'live'
  }

  private prepareLocalMedia(videoRequested: boolean): void {
    const audioTrack = this.audioController.getLocalAudioTrack()
    if (!audioTrack || audioTrack.readyState !== 'live') {
      const nextAudioTrack = this.audioController.prepareLocalAudio({
        trackId: RtcWebRtcTrackIdentityCodec.buildTrackId(this.local, this.appVersion)
      })
      this.log('local_audio_track readyState=' + (nextAudioTrack?.readyState || '') +
        ' enabled=' + (nextAudioTrack?.enabled === true))
    }
    if (videoRequested) {
      const videoTrack = this.audioController.getLocalVideoTrack()
      if (!videoTrack || videoTrack.readyState !== 'live') {
        const nextVideoTrack = this.audioController.prepareLocalVideo({
          trackId: RtcWebRtcTrackIdentityCodec.buildTrackId(this.local, this.appVersion),
          width: this.videoSource.width,
          height: this.videoSource.height,
          frameRate: this.videoSource.frameRate,
          facingMode: this.videoSource.facingMode
        })
        this.log('local_video_track requested=true readyState=' + (nextVideoTrack?.readyState || '') +
          ' enabled=' + (nextVideoTrack?.enabled === true) +
          ' width=' + this.videoSource.width +
          ' height=' + this.videoSource.height +
          ' frameRate=' + this.videoSource.frameRate +
          ' facingMode=' + this.videoSource.facingMode)
      }
    } else {
      this.log('local_video_track requested=false')
    }
  }

  private applyLocalAudioState(): void {
    const activeHeld = !!this.activeSessionKey && this.heldSessionKeys.get(this.activeSessionKey) === true
    this.audioController.setMuted(this.userMuted || activeHeld)
  }

  private bindPeerEvents(record: RtcWebRtcPeerRecord): void {
    const pc = record.pc
    pc.onicecandidate = (event: webrtc.RTCPeerConnectionIceEvent) => {
      if (this.peers.get(record.key)?.pc !== pc) {
        return
      }
      if (!event.candidate) {
        this.logPeerState(record, 'ice_gathering_complete')
        return
      }
      this.sendLocalIceCandidate(record, event.candidate)
    }
    pc.onicecandidateerror = (event: webrtc.RTCPeerConnectionIceErrorEvent) => {
      if (this.peers.get(record.key)?.pc !== pc) {
        return
      }
      this.error('ice_candidate_error role=' + record.role +
        ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
        ' rtcUid=' + record.context.rtcUid +
        ' url=' + (event.url || '') +
        ' code=' + (event.errorCode ?? '') +
        ' text=' + (event.errorText || ''))
    }
    pc.oniceconnectionstatechange = () => {
      if (this.peers.get(record.key)?.pc !== pc) {
        return
      }
      this.handleIceConnectionState(record)
      this.logPeerState(record, 'ice_state')
    }
    pc.onicegatheringstatechange = () => {
      if (this.peers.get(record.key)?.pc !== pc) {
        return
      }
      this.logPeerState(record, 'ice_gathering_state')
    }
    pc.onsignalingstatechange = () => {
      if (this.peers.get(record.key)?.pc !== pc) {
        return
      }
      this.logPeerState(record, 'signaling_state')
    }
    pc.onconnectionstatechange = () => {
      if (this.peers.get(record.key)?.pc !== pc) {
        return
      }
      const connected = pc.connectionState === 'connected'
      if (record.role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
        this.peerRegistry.markPublishState(connected, pc.getSenders().length)
      } else if (record.session) {
        this.peerRegistry.markSubscribeState(
          record.session.uid,
          record.session.targetNumber,
          record.context.rtcUid,
          connected,
          pc.getReceivers().length
        )
      }
      this.logPeerState(record, 'peer_state')
    }
    pc.ontrack = (event: webrtc.RTCTrackEvent) => {
      this.handleRemoteTrack(record, event)
    }
  }

  private handleRemoteTrack(record: RtcWebRtcPeerRecord, event: webrtc.RTCTrackEvent): void {
    const session = record.session
    if (record.role !== RTC_WEBRTC_PEER_ROLE_SUBSCRIBE || !session) {
      return
    }
    const identity = this.resolveTrackIdentity(event)
    let matchedBySessionFallback = false
    if (!identity || !identity.number) {
      if (!this.canUseVideoSessionFallback(record, event)) {
        this.log(`rtc_ontrack channelType=${record.role} kind=${event.track.kind}` +
          ` matched=false reason=missing_identity`)
        this.error(`ignore unmatched track kind=${event.track.kind}`)
        return
      }
      matchedBySessionFallback = true
      this.log(`rtc_ontrack channelType=${record.role} kind=${event.track.kind}` +
        ` matched=true reason=session_fallback sessionHash=${this.getSessionHash(session.sessionKey)}`)
    } else if (identity.number === this.local.number || identity.number !== session.targetNumber) {
      this.log(`rtc_ontrack channelType=${record.role} kind=${event.track.kind}` +
        ` matched=false reason=identity_mismatch`)
      this.error(`ignore mismatched track kind=${event.track.kind}`)
      return
    }
    if (event.track.kind === 'audio') {
      session.remoteAudioTrack = event.track
      session.hasRemoteAudio = true
      this.peerRegistry.markAnsweredAudio(
        session.uid || session.targetNumber,
        this.peerRegistry.sessionKey(
          session.uid,
          session.targetNumber,
          record.context.rtcUid,
          RTC_PEER_SESSION_CHANNEL_SUBSCRIBE
        )
      )
    } else if (event.track.kind === 'video') {
      session.remoteVideoTrack = event.track
      session.hasRemoteVideo = true
      const renderer = this.sessionRemoteVideoRenderers.get(session.sessionKey)
      if (renderer) {
        this.setRendererTrack(renderer, event.track)
      }
    } else {
      return
    }
    session.mediaConnected = this.isMediaConnected(session)
    this.log(`rtc_ontrack channelType=${record.role} kind=${event.track.kind}` +
      ` matched=true mediaConnected=${session.mediaConnected}` +
      `${matchedBySessionFallback ? ' reason=session_fallback' : ''}`)
    if (this.activeSessionKey === session.sessionKey) {
      this.selectSession(session.sessionKey)
    }
    this.emitMediaState(session)
  }

  private canUseVideoSessionFallback(record: RtcWebRtcPeerRecord, event: webrtc.RTCTrackEvent): boolean {
    const session = record.session
    return record.role === RTC_WEBRTC_PEER_ROLE_SUBSCRIBE &&
      !!session &&
      event.track.kind === 'video' &&
      session.mode === RtcCallMode.VIDEO &&
      !!session.sessionKey
  }

  private resolveTrackIdentity(event: webrtc.RTCTrackEvent): RtcWebRtcTrackIdentity | undefined {
    const byTrack = RtcWebRtcTrackIdentityCodec.parse(event.track.id)
    if (byTrack) {
      return byTrack
    }
    for (let i = 0; i < event.streams.length; i += 1) {
      const byStream = RtcWebRtcTrackIdentityCodec.parse(event.streams[i].id)
      if (byStream) {
        return byStream
      }
    }
    return undefined
  }

  private isMediaConnected(session: RtcWebRtcMediaSession): boolean {
    return RtcWebRtcMediaController.isMediaConnected(
      session.mode,
      session.remoteClientType,
      session.hasRemoteAudio,
      session.hasRemoteVideo
    )
  }

  private clearSessionRemoteVideoRenderer(sessionKey: string): void {
    const renderer = this.sessionRemoteVideoRenderers.get(sessionKey)
    if (!renderer) {
      return
    }
    this.clearRenderer(renderer)
    this.sessionRemoteVideoRenderers.delete(sessionKey)
  }

  private clearRenderer(renderer: RtcVideoRendererAdapter): void {
    this.setRendererTrack(renderer, undefined)
  }

  private setRendererTrack(
    renderer: RtcVideoRendererAdapter,
    track?: webrtc.MediaStreamTrack
  ): void {
    try {
      renderer.setVideoTrack(track || null)
    } catch (error) {
      this.error('bind session remote video renderer error: ' + JSON.stringify(error))
    }
  }

  private static isAudioOnlyDevice(clientType: string): boolean {
    const value = (clientType || '').trim().toLowerCase()
    return value.indexOf('watch') >= 0 || value.indexOf('wrist') >= 0
  }

  private getPeerKey(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): string {
    return role === RTC_WEBRTC_PEER_ROLE_PUBLISH ?
      RTC_WEBRTC_PEER_ROLE_PUBLISH + '|' + context.sessionId + '|' + context.rtcUid :
      RTC_WEBRTC_PEER_ROLE_SUBSCRIBE + '|' + context.sessionId + '|' + context.rtcUid
  }

  private findSession(keyOrId: string): RtcWebRtcMediaSession | undefined {
    const value = (keyOrId || '').trim()
    if (!value) {
      return undefined
    }
    const direct = this.sessions.get(value)
    if (direct) {
      return direct
    }
    const key = this.sessionIds.get(value)
    return key ? this.sessions.get(key) : undefined
  }

  private requirePeer(role: RtcWebRtcPeerRole, context: RtcWebRtcSignalContext): RtcWebRtcPeerRecord {
    const record = this.peers.get(this.getPeerKey(role, context))
    if (!record) {
      throw new Error('PeerConnection missing: ' + role + ' ' + context.sessionId)
    }
    return record
  }

  private closePeer(record: RtcWebRtcPeerRecord, reason: string): void {
    this.clearIceCheckingTimer(record)
    try {
      record.pc.close()
    } catch (_error) {
    }
    this.log(`close peer reason=${reason} role=${record.role} session=${record.context.sessionId}`)
  }

  private copyMediaState(session: RtcWebRtcMediaSession): RtcWebRtcMediaState {
    return {
      sessionKey: session.sessionKey,
      sessionId: session.sessionId,
      uid: session.uid || session.sessionKey,
      targetNumber: session.targetNumber,
      rtcUid: session.rtcUid,
      channelType: RTC_PEER_SESSION_CHANNEL_SUBSCRIBE,
      mode: session.mode,
      localVideoReady: RtcWebRtcMediaController.isLocalVideoReady(
        this.audioController.getLocalVideoTrack()?.readyState
      ),
      hasRemoteAudio: session.hasRemoteAudio,
      hasRemoteVideo: session.hasRemoteVideo,
      mediaConnected: session.mediaConnected
    }
  }

  private emitMediaState(session: RtcWebRtcMediaSession): void {
    this.onMediaStateChange?.(this.copyMediaState(session))
  }

  private resetMediaState(session: RtcWebRtcMediaSession): void {
    session.hasRemoteAudio = false
    session.hasRemoteVideo = false
    session.mediaConnected = false
    session.remoteAudioTrack = undefined
    session.remoteVideoTrack = undefined
  }

  private log(message: string): void {
    this.onLog?.(message)
  }

  private error(message: string): void {
    this.onError?.(message)
  }

  private sendLocalIceCandidate(record: RtcWebRtcPeerRecord, candidate: webrtc.RTCIceCandidate): void {
    const candidateInit = candidate.toJSON()
    const candidateText = candidateInit.candidate || ''
    if (!candidateText) {
      this.logPeerState(record, 'local_candidate_empty')
      return
    }
    const commonRequest = this.resolveCandidateCommonRequest(record)
    if (!commonRequest) {
      this.log('local_candidate_skip role=' + record.role +
        ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
        ' rtcUid=' + record.context.rtcUid +
        ' reason=missing_common_request')
      return
    }
    const message = RtcWebRtcSignalStateMachine.buildCandidateSignal({
      eventName: RTC_WEBRTC_SIGNAL_EVENT_SEND_CANDIDATE,
      uuid: record.context.sessionId,
      rtcUid: record.context.scopedRtcUid,
      local: this.local,
      remote: {
        number: record.session?.targetNumber || commonRequest.to || commonRequest.grpcTo || '',
        displayName: record.session?.targetName || commonRequest.toName || ''
      },
      mode: record.session?.mode || (commonRequest.isVideo ? RtcCallMode.VIDEO : RtcCallMode.AUDIO),
      candidateType: record.role,
      candidate: candidateText,
      sdpMLineIndex: candidateInit.sdpMLineIndex,
      sdpMid: candidateInit.sdpMid,
      commonRequest
    })
    record.localCandidateCount += 1
    this.log('local_candidate_send role=' + record.role +
      ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
      ' rtcUid=' + record.context.rtcUid +
      ' count=' + record.localCandidateCount +
      ' mid=' + (candidateInit.sdpMid || '') +
      ' mline=' + (candidateInit.sdpMLineIndex ?? '') +
      ' type=' + this.getCandidateType(candidateText) +
      ' signaling=' + record.pc.signalingState +
      ' ice=' + record.pc.iceConnectionState +
      ' gathering=' + record.pc.iceGatheringState)
    this.sendSignal(message, record.context).catch((error: Error) => {
      this.error('local_candidate_send_failed role=' + record.role +
        ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
        ' error=' + JSON.stringify(error))
    })
  }

  private resolveCandidateCommonRequest(record: RtcWebRtcPeerRecord): RtcCommonRequest | undefined {
    if (record.context.commonRequest) {
      return record.context.commonRequest
    }
    const session = record.session
    if (!session) {
      return undefined
    }
    return {
      uuid: record.context.sessionId,
      locId: this.local.locId || '',
      hospitalId: this.local.hospitalId || '',
      number: this.local.number,
      displayName: this.local.displayName || this.local.number,
      clientType: this.local.clientType || '',
      identity: this.local.identity || '',
      to: session.targetNumber,
      toName: session.targetName || session.targetNumber,
      from: this.local.number,
      fromName: this.local.displayName || this.local.number,
      grpcFrom: this.local.number,
      grpcTo: session.targetNumber,
      isVideo: session.mode === RtcCallMode.VIDEO
    }
  }

  private handleIceConnectionState(record: RtcWebRtcPeerRecord): void {
    const state = record.pc.iceConnectionState
    if (state === 'connected' || state === 'completed' || state === 'failed' || state === 'closed') {
      this.clearIceCheckingTimer(record)
      return
    }
    if (state !== 'checking') {
      return
    }
    if (record.iceCheckingTimer !== undefined) {
      return
    }
    record.iceCheckingStartedAt = Date.now()
    record.iceCheckingTimer = setTimeout(() => {
      if (this.peers.get(record.key)?.pc !== record.pc) {
        return
      }
      if (record.pc.iceConnectionState !== 'checking') {
        this.clearIceCheckingTimer(record)
        return
      }
      this.log('publish_connect_checking_timeout role=' + record.role +
        ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
        ' rtcUid=' + record.context.rtcUid +
        ' elapsedMs=' + (Date.now() - record.iceCheckingStartedAt) +
        ' localCandidates=' + record.localCandidateCount +
        ' signaling=' + record.pc.signalingState +
        ' connection=' + record.pc.connectionState +
        ' gathering=' + record.pc.iceGatheringState)
      this.clearIceCheckingTimer(record)
    }, this.iceCheckingWarnMs)
  }

  private clearIceCheckingTimer(record: RtcWebRtcPeerRecord): void {
    if (record.iceCheckingTimer !== undefined) {
      clearTimeout(record.iceCheckingTimer)
      record.iceCheckingTimer = undefined
    }
    record.iceCheckingStartedAt = 0
  }

  private logPeerState(record: RtcWebRtcPeerRecord, action: string): void {
    this.log(action +
      ' role=' + record.role +
      ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
      ' rtcUid=' + record.context.rtcUid +
      ' signaling=' + record.pc.signalingState +
      ' ice=' + record.pc.iceConnectionState +
      ' gathering=' + record.pc.iceGatheringState +
      ' connection=' + record.pc.connectionState +
      ' localCandidates=' + record.localCandidateCount)
  }

  private getCandidateType(candidate: string): string {
    const marker = ' typ '
    const index = candidate.indexOf(marker)
    if (index < 0) {
      return ''
    }
    const rest = candidate.substring(index + marker.length)
    return rest.split(' ')[0] || ''
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
}
