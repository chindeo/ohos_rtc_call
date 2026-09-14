import webrtc, { ScalingMode, VideoRenderController } from './OhosWebRtc'
import {
  RtcAudioController,
  RtcVideoCapturerFailure,
  RtcVideoRendererAdapter
} from '../audio/RtcAudioController'
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
  onExternalVideoCaptureStateChange?: (active: boolean) => void
  onSendSignal?: (message: RtcSignalMessage, context: RtcWebRtcSignalContext) => void | Promise<void>
  onMediaStateChange?: (state: RtcWebRtcMediaState) => void
  onLog?: (message: string) => void
  onError?: (message: string) => void
}

export interface RtcWebRtcCloseSessionOptions {
  preservePublish?: boolean
}

interface RtcWebRtcCodecStats extends webrtc.RTCStats {
  mimeType?: string
}

interface RtcWebRtcVideoRtpStats extends webrtc.RTCStats {
  kind?: string
  mediaType?: string
  codecId?: string
  frameWidth?: number
  frameHeight?: number
  framesPerSecond?: number
  framesEncoded?: number
  framesDecoded?: number
  bytesSent?: number
  bytesReceived?: number
  packetsLost?: number
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

  deactivate(): void {
    this.controller.deactivate()
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
  diagnosticId: number
  key: string
  role: RtcWebRtcPeerRole
  context: RtcWebRtcSignalContext
  pc: webrtc.RTCPeerConnection
  session?: RtcWebRtcMediaSession
  localCandidateCount: number = 0
  iceCheckingTimer?: number
  iceCheckingStartedAt: number = 0
  videoStatsTimer?: number
  videoStatsInFlight: boolean = false
  videoStatsErrorLogged: boolean = false
  videoStatsEmptyLogged: boolean = false

  constructor(
    diagnosticId: number,
    key: string,
    role: RtcWebRtcPeerRole,
    context: RtcWebRtcSignalContext,
    pc: webrtc.RTCPeerConnection,
    session?: RtcWebRtcMediaSession
  ) {
    this.diagnosticId = diagnosticId
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
  private onExternalVideoCaptureStateChange?: (active: boolean) => void
  private onLog?: (message: string) => void
  private onError?: (message: string) => void
  private iceCheckingWarnMs: number = 10000
  private videoStatsIntervalMs: number = 5000
  private nextPeerDiagnosticId: number = 1
  private resourceGeneration: number = 0
  private closedResourceGeneration: number = -1
  private closeAllInProgress: boolean = false
  private localVideoRecoveryInFlight: boolean = false
  private localVideoRecoveryAttempted: boolean = false
  private externalVideoCaptureActive: boolean = false

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
    this.onExternalVideoCaptureStateChange = options.onExternalVideoCaptureStateChange
    this.onLog = options.onLog
    this.onError = options.onError
    this.audioController.setLocalVideoCapturerFailureHandler((failure: RtcVideoCapturerFailure) => {
      this.handleLocalVideoCapturerFailure(failure)
    })
  }

  setSignalSender(sender: (message: RtcSignalMessage, context: RtcWebRtcSignalContext) =>
    void | Promise<void>): void {
    this.onSendSignal = sender
  }

  setIceServers(iceServers: webrtc.RTCIceServer[]): void {
    this.pcConfig = { iceServers }
  }

  pushLocalVideoNv21Frame(data: Uint8Array, width: number, height: number,
    timestampUs?: number, rotation?: 0 | 90 | 180 | 270): boolean {
    return this.audioController.pushLocalVideoNv21Frame(data, width, height, timestampUs, rotation)
  }

  registerSession(options: RtcWebRtcMediaSessionOptions): void {
    const key = (options.sessionKey || options.uid || options.sessionId).trim()
    if (!key || !options.sessionId) {
      return
    }
    let session = this.sessions.get(key)
    if (!session) {
      if (this.sessions.size === 0) {
        this.localVideoRecoveryAttempted = false
      }
      session = new RtcWebRtcMediaSession()
      session.sessionKey = key
      this.sessions.set(key, session)
      this.resourceGeneration += 1
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
      this.log(`peer reuse id=${current.diagnosticId} role=${role}` +
        ` session=${context.sessionId} rtcUid=${context.rtcUid}`)
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
    const record = new RtcWebRtcPeerRecord(this.nextPeerDiagnosticId, key, role, context, pc, session)
    this.nextPeerDiagnosticId += 1
    this.peers.set(key, record)
    if (role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
      const trackCount = this.audioController.addLocalTracks(pc)
      this.log(`peer tracks added id=${record.diagnosticId} count=${trackCount}` +
        ` localAudio=${this.audioController.getLocalAudioTrack()?.id || ''}` +
        ` localVideo=${this.audioController.getLocalVideoTrack()?.id || ''}`)
      await this.configurePublishVideoFrameRate(record, 'track_added')
    } else if (session) {
      this.peerRegistry.routeSubscribeOffer(session.uid, session.targetNumber, context.rtcUid)
    }
    this.bindPeerEvents(record)
    this.startVideoStats(record)
    this.log(`peer created id=${record.diagnosticId} role=${role}` +
      ` session=${context.sessionId} rtcUid=${context.rtcUid} ${this.getResourceSummary()}`)
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
    const isRemoteOffer = description.type.toLowerCase() === 'offer'
    if (isRemoteOffer) {
      this.configureVideoCodecPreferences(record, 'before_remote_offer')
    }
    await record.pc.setRemoteDescription({
      type: description.type as webrtc.RTCSdpType,
      sdp: description.sdp
    })
    if (isRemoteOffer) {
      this.configureVideoCodecPreferences(record, 'after_remote_offer')
    }
    this.logVideoCodecSummary(record, 'remote', description.sdp)
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
    const record = this.requirePeer(role, context)
    this.configureVideoCodecPreferences(record, 'before_create_answer')
    const answer = await record.pc.createAnswer()
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
    this.logVideoCodecSummary(this.requirePeer(role, context), 'local', description.sdp)
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
    let hasVideoSession = false
    this.sessions.forEach((remainingSession: RtcWebRtcMediaSession) => {
      if (remainingSession.mode === RtcCallMode.VIDEO) {
        hasVideoSession = true
      }
    })
    if (!hasVideoSession) {
      this.setExternalVideoCaptureActive(false)
      this.audioController.releaseLocalVideo()
      this.localVideoRecoveryAttempted = false
    }
    if (isLastSession) {
      this.resetMediaState(session)
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
    this.log(`session closed reason=${reason} session=${session.sessionId} ${this.getResourceSummary()}`)
    return true
  }

  closeAll(reason: string = 'close all'): void {
    if (this.closeAllInProgress || this.closedResourceGeneration === this.resourceGeneration) {
      this.log(`skip duplicate close all reason=${reason} generation=${this.resourceGeneration}`)
      return
    }
    this.closeAllInProgress = true
    this.log(`close all begin reason=${reason} ${this.getResourceSummary()}`)
    try {
      this.peers.forEach((record: RtcWebRtcPeerRecord) => this.closePeer(record, reason))
      this.peers.clear()
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
      this.localVideoRecoveryAttempted = false
      this.setExternalVideoCaptureActive(false)
      this.audioController.cleanupRtcCallResources(reason)
      this.closedResourceGeneration = this.resourceGeneration
      this.log(`close all complete reason=${reason} ${this.getResourceSummary()}`)
    } finally {
      this.closeAllInProgress = false
    }
  }

  dispose(): void {
    this.closeAll('dispose')
    this.audioController.setLocalVideoCapturerFailureHandler(undefined)
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

  static prioritizeVideoCodecs(codecs: webrtc.RTCRtpCodec[]): webrtc.RTCRtpCodec[] {
    const preferred: webrtc.RTCRtpCodec[] = []
    const fallback: webrtc.RTCRtpCodec[] = []
    codecs.forEach((codec: webrtc.RTCRtpCodec) => {
      const mimeType = (codec.mimeType || '').toLowerCase()
      const fmtp = (codec.sdpFmtpLine || '').toLowerCase()
      if (mimeType === 'video/h264' && fmtp.indexOf('packetization-mode=1') >= 0 &&
        fmtp.indexOf('profile-level-id=42e01f') >= 0) {
        preferred.push(codec)
      } else {
        fallback.push(codec)
      }
    })
    return preferred.concat(fallback)
  }

  static applyVideoMaxFrameRate(parameters: webrtc.RTCRtpSendParameters, maxFrameRate: number): number {
    if (!Number.isFinite(maxFrameRate) || maxFrameRate <= 0) {
      return 0
    }
    const value = Math.max(1, Math.floor(maxFrameRate))
    let updated = 0
    parameters.encodings.forEach((encoding: webrtc.RTCRtpEncodingParameters) => {
      encoding.maxFramerate = value
      updated += 1
    })
    return updated
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
          facingMode: this.videoSource.facingMode,
          deviceId: this.videoSource.deviceId,
          externalNv21: this.videoSource.externalNv21
        })
        if (nextVideoTrack && this.videoSource.externalNv21 === true) {
          this.setExternalVideoCaptureActive(true)
        }
        this.log('local_video_track requested=true readyState=' + (nextVideoTrack?.readyState || '') +
          ' enabled=' + (nextVideoTrack?.enabled === true) +
          ' width=' + this.videoSource.width +
          ' height=' + this.videoSource.height +
          ' frameRate=' + this.videoSource.frameRate +
          ' facingMode=' + this.videoSource.facingMode +
          ' deviceId=' + (this.videoSource.deviceId || ''))
      }
    } else {
      this.log('local_video_track requested=false')
    }
  }

  private configureVideoCodecPreferences(record: RtcWebRtcPeerRecord, phase: string): void {
    try {
      const capabilities = record.role === RTC_WEBRTC_PEER_ROLE_PUBLISH ?
        webrtc.RTCRtpSender.getCapabilities('video') : webrtc.RTCRtpReceiver.getCapabilities('video')
      if (!capabilities || capabilities.codecs.length === 0) {
        this.log('video_codec_preferences role=' + record.role +
          ' phase=' + phase +
          ' result=skip reason=no_capabilities')
        return
      }
      const codecs = RtcWebRtcMediaController.prioritizeVideoCodecs(capabilities.codecs)
      let applied = 0
      record.pc.getTransceivers().forEach((transceiver: webrtc.RTCRtpTransceiver) => {
        const senderKind = transceiver.sender.track?.kind || ''
        const receiverKind = transceiver.receiver.track?.kind || ''
        if (senderKind !== 'video' && receiverKind !== 'video') {
          return
        }
        transceiver.setCodecPreferences(codecs)
        applied += 1
      })
      this.log('video_codec_preferences role=' + record.role +
        ' phase=' + phase +
        ' result=' + (applied > 0 ? 'applied' : 'skip') +
        ' transceivers=' + applied +
        ' first=' + (codecs[0]?.mimeType || ''))
    } catch (error) {
      this.error('video codec preferences failed role=' + record.role +
        ' phase=' + phase +
        ' error=' + JSON.stringify(error))
    }
  }

  private async configurePublishVideoFrameRate(
    record: RtcWebRtcPeerRecord,
    phase: string
  ): Promise<void> {
    if (record.role !== RTC_WEBRTC_PEER_ROLE_PUBLISH) {
      return
    }
    let applied = 0
    const senders = record.pc.getSenders()
    for (const sender of senders) {
      if (sender.track?.kind !== 'video') {
        continue
      }
      try {
        const parameters = sender.getParameters()
        const updated = RtcWebRtcMediaController.applyVideoMaxFrameRate(
          parameters, this.videoSource.frameRate)
        if (updated === 0) {
          this.log('video_sender_frame_rate role=' + record.role +
            ' phase=' + phase + ' result=skip reason=no_encodings')
          continue
        }
        await sender.setParameters(parameters)
        applied += updated
      } catch (error) {
        this.error('video sender frame rate failed role=' + record.role +
          ' phase=' + phase + ' error=' + JSON.stringify(error))
      }
    }
    this.log('video_sender_frame_rate role=' + record.role +
      ' phase=' + phase +
      ' maxFramerate=' + Math.max(1, Math.floor(this.videoSource.frameRate)) +
      ' encodings=' + applied)
  }

  private handleLocalVideoCapturerFailure(failure: RtcVideoCapturerFailure): void {
    if (this.localVideoRecoveryInFlight || this.localVideoRecoveryAttempted ||
      this.closeAllInProgress || this.sessions.size === 0) {
      this.error('local video recovery skipped stage=' + failure.stage +
        ' inFlight=' + this.localVideoRecoveryInFlight +
        ' attempted=' + this.localVideoRecoveryAttempted +
        ' sessions=' + this.sessions.size)
      return
    }
    let hasVideoSession = false
    this.sessions.forEach((session: RtcWebRtcMediaSession) => {
      if (session.mode === RtcCallMode.VIDEO) {
        hasVideoSession = true
      }
    })
    if (!hasVideoSession) {
      return
    }
    this.localVideoRecoveryAttempted = true
    this.localVideoRecoveryInFlight = true
    this.recoverLocalVideoTrack(failure)
  }

  private async recoverLocalVideoTrack(failure: RtcVideoCapturerFailure): Promise<void> {
    const generation = this.resourceGeneration
    const previousTrack = this.audioController.getLocalVideoTrack()
    try {
      this.log('local video recovery begin stage=' + failure.stage +
        ' code=' + failure.code +
        ' generation=' + generation)
      this.audioController.releaseLocalVideo()
      if (this.closeAllInProgress || this.sessions.size === 0 ||
        this.resourceGeneration !== generation) {
        this.log('local video recovery cancelled generation=' + generation)
        return
      }
      const nextTrack = this.audioController.prepareLocalVideo({
        trackId: RtcWebRtcTrackIdentityCodec.buildTrackId(this.local, this.appVersion),
        width: this.videoSource.width,
        height: this.videoSource.height,
        frameRate: this.videoSource.frameRate,
        facingMode: this.videoSource.facingMode,
        deviceId: this.videoSource.deviceId,
        externalNv21: this.videoSource.externalNv21
      })
      if (!nextTrack || nextTrack.readyState !== 'live') {
        throw new Error('replacement local video track is not live')
      }
      let replaced = 0
      const records: RtcWebRtcPeerRecord[] = []
      this.peers.forEach((record: RtcWebRtcPeerRecord) => records.push(record))
      for (const record of records) {
        if (record.role !== RTC_WEBRTC_PEER_ROLE_PUBLISH ||
          record.pc.signalingState === 'closed') {
          continue
        }
        for (const sender of record.pc.getSenders()) {
          if (sender.track?.kind !== 'video' && sender.track !== previousTrack) {
            continue
          }
          await sender.replaceTrack(nextTrack)
          replaced += 1
        }
        await this.configurePublishVideoFrameRate(record, 'replace_track')
      }
      this.log('local video recovery complete generation=' + generation +
        ' replacedSenders=' + replaced)
    } catch (error) {
      this.error('local video recovery failed generation=' + generation +
        ' stage=' + failure.stage +
        ' error=' + JSON.stringify(error))
    } finally {
      this.localVideoRecoveryInFlight = false
    }
  }

  private setExternalVideoCaptureActive(active: boolean): void {
    if (this.videoSource.externalNv21 !== true || this.externalVideoCaptureActive === active) {
      return
    }
    this.externalVideoCaptureActive = active
    try {
      this.onExternalVideoCaptureStateChange?.(active)
    } catch (error) {
      this.error('external video capture state callback failed active=' + active +
        ' error=' + JSON.stringify(error))
    }
  }

  private logVideoCodecSummary(record: RtcWebRtcPeerRecord, direction: string, sdp: string): void {
    const codecs = RtcWebRtcMediaController.videoCodecSummary(sdp)
    if (!codecs) {
      return
    }
    this.log('video_codec_sdp role=' + record.role +
      ' direction=' + direction +
      ' codecs=' + codecs)
  }

  private static videoCodecSummary(sdp: string): string {
    const codecByPayload: Map<string, string> = new Map()
    let videoPayloads: string[] = []
    const lines = (sdp || '').replace(/\r\n/g, '\n').split('\n')
    lines.forEach((line: string) => {
      const value = line.trim()
      if (value.indexOf('m=video ') === 0) {
        videoPayloads = value.split(/\s+/).slice(3)
        return
      }
      if (value.indexOf('a=rtpmap:') !== 0) {
        return
      }
      const parts = value.substring('a=rtpmap:'.length).split(/\s+/, 2)
      if (parts.length !== 2) {
        return
      }
      codecByPayload.set(parts[0], parts[1].split('/', 1)[0])
    })
    const names: string[] = []
    videoPayloads.forEach((payload: string) => {
      const name = codecByPayload.get(payload)
      if (name && names.indexOf(name) < 0) {
        names.push(name)
      }
    })
    return names.join(',')
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
    try {
      renderer.deactivate?.()
    } catch (error) {
      this.error('deactivate session remote video renderer error: ' + JSON.stringify(error))
    }
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
    this.stopVideoStats(record)
    try {
      record.pc.close()
    } catch (_error) {
    }
    this.log(`close peer id=${record.diagnosticId} reason=${reason}` +
      ` role=${record.role} session=${record.context.sessionId} rtcUid=${record.context.rtcUid}`)
  }

  private startVideoStats(record: RtcWebRtcPeerRecord): void {
    if (record.videoStatsTimer !== undefined || record.session?.mode !== RtcCallMode.VIDEO) {
      return
    }
    record.videoStatsTimer = setInterval(() => {
      this.collectVideoStats(record)
    }, this.videoStatsIntervalMs)
    this.log('rtc_video_stats_start id=' + record.diagnosticId +
      ' role=' + record.role +
      ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
      ' intervalMs=' + this.videoStatsIntervalMs)
  }

  private stopVideoStats(record: RtcWebRtcPeerRecord): void {
    if (record.videoStatsTimer !== undefined) {
      clearInterval(record.videoStatsTimer)
      record.videoStatsTimer = undefined
    }
    record.videoStatsInFlight = false
  }

  private collectVideoStats(record: RtcWebRtcPeerRecord): void {
    if (record.videoStatsInFlight || this.peers.get(record.key)?.pc !== record.pc ||
      record.pc.signalingState === 'closed') {
      return
    }
    record.videoStatsInFlight = true
    record.pc.getStats().then((report: webrtc.RTCStatsReport) => {
      record.videoStatsInFlight = false
      if (this.peers.get(record.key)?.pc !== record.pc) {
        return
      }
      const codecById: Map<string, string> = new Map()
      report.stats.forEach((value: webrtc.RTCStats, id: string) => {
        if (value.type !== 'codec') {
          return
        }
        const codec = value as RtcWebRtcCodecStats
        codecById.set(id, codec.mimeType || '')
      })

      let videoRows = 0
      report.stats.forEach((value: webrtc.RTCStats) => {
        if (value.type !== 'inbound-rtp' && value.type !== 'outbound-rtp') {
          return
        }
        const stat = value as RtcWebRtcVideoRtpStats
        const codec = stat.codecId ? (codecById.get(stat.codecId) || '') : ''
        const kind = (stat.kind || stat.mediaType || '').toLowerCase()
        if (kind !== 'video' && codec.toLowerCase().indexOf('video/') !== 0) {
          return
        }
        videoRows += 1
        const outbound = value.type === 'outbound-rtp'
        const width = stat.frameWidth !== undefined ? stat.frameWidth.toString() : ''
        const height = stat.frameHeight !== undefined ? stat.frameHeight.toString() : ''
        const resolution = width && height ? width + 'x' + height : ''
        const frames = outbound ? stat.framesEncoded : stat.framesDecoded
        const bytes = outbound ? stat.bytesSent : stat.bytesReceived
        this.log('rtc_video_stats id=' + record.diagnosticId +
          ' role=' + record.role +
          ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
          ' direction=' + (outbound ? 'send' : 'recv') +
          ' codec=' + codec +
          ' resolution=' + resolution +
          ' fps=' + (stat.framesPerSecond ?? '') +
          ' frames=' + (frames ?? '') +
          ' bytes=' + (bytes ?? '') +
          ' packetsLost=' + (stat.packetsLost ?? ''))
      })
      if (videoRows === 0 && !record.videoStatsEmptyLogged) {
        record.videoStatsEmptyLogged = true
        this.log('rtc_video_stats_empty id=' + record.diagnosticId +
          ' role=' + record.role +
          ' sessionHash=' + this.getSessionHash(record.context.sessionId))
      }
    }).catch((error: Error) => {
      record.videoStatsInFlight = false
      if (record.videoStatsErrorLogged || this.peers.get(record.key)?.pc !== record.pc) {
        return
      }
      record.videoStatsErrorLogged = true
      this.error('rtc_video_stats_failed id=' + record.diagnosticId +
        ' role=' + record.role +
        ' sessionHash=' + this.getSessionHash(record.context.sessionId) +
        ' error=' + JSON.stringify(error))
    })
  }

  private getResourceSummary(): string {
    let publishPeers = 0
    let subscribePeers = 0
    this.peers.forEach((record: RtcWebRtcPeerRecord) => {
      if (record.role === RTC_WEBRTC_PEER_ROLE_PUBLISH) {
        publishPeers += 1
      } else {
        subscribePeers += 1
      }
    })
    return `resources sessions=${this.sessions.size} peers=${this.peers.size}` +
      ` publishPeers=${publishPeers} subscribePeers=${subscribePeers}` +
      ` localAudio=${this.audioController.getLocalAudioTrack()?.readyState || 'none'}` +
      ` localVideo=${this.audioController.getLocalVideoTrack()?.readyState || 'none'}`
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
