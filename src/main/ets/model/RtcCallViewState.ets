import { RtcCallMode } from './RtcCallConfig'
import { RtcTransportProtocol } from './RtcProtocolConfig'

export enum RtcCallDirection {
  NONE = 'none',
  INCOMING = 'incoming',
  OUTGOING = 'outgoing'
}

export enum RtcCallViewPhase {
  HIDDEN = 'hidden',
  INCOMING = 'incoming',
  OUTGOING = 'outgoing',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  HELD = 'held',
  ENDED = 'ended',
  ERROR = 'error'
}

export interface RtcCallViewPeer {
  number: string
  displayName?: string
  deviceIp?: string
  clientType?: string
  locId?: string
}

export interface RtcCallVolumeState {
  enabled: boolean
  percent: number
  updatedAt: number
}

export class RtcCallViewState {
  visible: boolean = false
  phase: RtcCallViewPhase = RtcCallViewPhase.HIDDEN
  protocol: RtcTransportProtocol = RtcTransportProtocol.WEBRTC
  direction: RtcCallDirection = RtcCallDirection.NONE
  mode: RtcCallMode = RtcCallMode.AUDIO
  callId: string = ''
  local: RtcCallViewPeer = { number: '' }
  remote: RtcCallViewPeer = { number: '' }
  autoAnswer: boolean = false
  registered: boolean = false
  canAccept: boolean = false
  canHangup: boolean = false
  errorMessage: string = ''
  registrationErrorMessage: string = ''
  volume: RtcCallVolumeState = {
    enabled: false,
    percent: 0,
    updatedAt: 0
  }
}

export type RtcCallViewStateListener = (state: RtcCallViewState) => void
