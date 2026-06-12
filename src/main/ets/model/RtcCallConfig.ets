import webrtc from '@ohos/webrtc'

export enum RtcCallMode {
  AUDIO = 'audio',
  VIDEO = 'video'
}

export enum RtcCallState {
  IDLE = 'idle',
  PREPARING = 'preparing',
  REQUESTING_CONFIG = 'requesting_config',
  LOADING_WEB = 'loading_web',
  REGISTERING = 'registering',
  RINGING = 'ringing',
  TRIGGERING_CALL = 'triggering_call',
  CALLING = 'calling',
  CONNECTED = 'connected',
  FAILED = 'failed',
  ENDED = 'ended'
}

export enum RtcHostPhase {
  IDLE = 'idle',
  STANDBY_READY = 'standby_ready',
  INCOMING_READY = 'incoming_ready',
  OUTGOING_READY = 'outgoing_ready',
  MEDIA_ACTIVE = 'media_active',
  TEARING_DOWN = 'tearing_down'
}

export interface RtcPeerIdentity {
  number: string
  uid?: string
  displayName?: string
  clientType?: string
  identity?: string
  ip?: string
  locId?: string
  hospitalId?: string
  autoAnswer?: boolean
}

export interface RtcCallKitOptions {
  signalUrl: string
  local: RtcPeerIdentity
  iceServers?: webrtc.RTCIceServer[]
  callTimeoutMs?: number
  autoAnswer?: boolean
  enableAecDump?: boolean
  enableAudioSampleStats?: boolean
  lowLatencyAnswerWaitMs?: number
  lowLatencyAnswerWaitAttempts?: number
}

export class RtcCallConfigResponse {
  callUrl: string = ''
  number: string = ''
  calleeNumber: string = ''
  locId: string = ''
  hospitalId: string = ''
  displayName: string = ''
  clientType: string = ''
  ip: string = ''
  identity: string = ''
  ws: string = ''
  isAutoAnswer: string = ''
  triggerScript: string = ''
  readyCheckScript: string = ''
  timeoutMs: number = 15000
}

export class RtcCallSession {
  requestId: string = ''
  uid: string = ''
  mode: RtcCallMode = RtcCallMode.AUDIO
  state: RtcCallState = RtcCallState.IDLE
  hostPhase: RtcHostPhase = RtcHostPhase.IDLE
  active: boolean = false
  pendingTrigger: boolean = false
  visible: boolean = false
  callUrl: string = ''
  localNumber: string = ''
  calleeNumber: string = ''
  displayName: string = ''
  locId: string = ''
  hospitalId: string = ''
  clientType: string = ''
  ip: string = ''
  identity: string = ''
  isAutoAnswer: string = ''
  isHold: string = ''
  triggerScript: string = ''
  readyCheckScript: string = ''
  timeoutMs: number = 15000
  errorMessage: string = ''
}

export interface RtcCallDiagnosticsOptions {
  enableAecDump?: boolean
  enableAudioSampleStats?: boolean
  logTag?: string
}
