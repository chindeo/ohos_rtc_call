import { RtcCallMode, RtcPeerIdentity } from '../model/RtcCallConfig'
import {
  RtcWebRtcPeerConnectionAdapter,
  RtcWebRtcSignalHandleResult
} from '../signaling/RtcWebRtcSignalStateMachine'

export const RTC_CALL_GATEWAY_CHANNEL_PUBLISH = 'publish'
export const RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE = 'subscribe'

export type RtcCallGatewayChannelType = 'publish' | 'subscribe'
export type RtcCallGatewayDirection = 'incoming' | 'outgoing'
export type RtcCallGatewayPhase = 'incoming' | 'outgoing' | 'answering' | 'answered' | 'held' | 'ended'

export interface RtcCallGatewayAdapter {
  start?(): void | Promise<void>
  stop?(): void | Promise<void>
  callInvite(to: string, isVideo: boolean): void | Promise<void>
  callAnswer(uid: string): void | Promise<void>
  callSwitch(uid: string): void | Promise<void>
  callHangUp(uid: string, d: number): void | Promise<void>
  sendSdp(
    signalUID: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    sdp: string,
    sdpType: string,
    status: number
  ): void | Promise<void>
  sendCandidate(
    signalUID: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    sdpMid: string,
    candidate: string,
    sdpMLineIndex: number
  ): void | Promise<void>
}

export interface RtcCallGatewayClientOptions {
  adapter: RtcCallGatewayAdapter
  local: RtcPeerIdentity
  peerAdapter?: RtcWebRtcPeerConnectionAdapter
  autoAnswer?: boolean
  allowSingleCallNumberFallback?: boolean
  onStateChange?: (snapshot: RtcCallGatewaySnapshot) => void
  onError?: (message: string) => void
  onLog?: (message: string) => void
}

export interface RtcCallGatewayOpenActivityOptions {
  num: string
  name?: string
  uid: string
  isOut: boolean
  isVideo?: boolean
  multi?: boolean
}

export interface RtcCallGatewayHangupOptions {
  from?: string
  to?: string
  uid: string
  d?: number
}

export interface RtcCallGatewaySdpOptions {
  from: string
  to: string
  uid: string
  rtcUID: string
  channelType: RtcCallGatewayChannelType
  sdp: string
  sdpType: string
  isVideo?: boolean
}

export interface RtcCallGatewayCandidateOptions {
  from: string
  to: string
  uid: string
  rtcUID: string
  channelType: RtcCallGatewayChannelType
  sdpMid?: string
  candidate: string
  sdpMLineIndex?: number
}

export interface RtcCallGatewayCallSession {
  uid: string
  number: string
  name: string
  direction: RtcCallGatewayDirection
  phase: RtcCallGatewayPhase
  mode: RtcCallMode
  isSelected: boolean
  uplinkMuted: boolean
  lastUpdatedAt: number
}

export interface RtcCallGatewayPeerSession {
  key: string
  uid: string
  rtcUID: string
  channelType: RtcCallGatewayChannelType
  from: string
  to: string
  lastUpdatedAt: number
}

export interface RtcCallGatewaySnapshot {
  selectedUid: string
  calls: RtcCallGatewayCallSession[]
  peers: RtcCallGatewayPeerSession[]
}

export interface RtcCallGatewayOperationResult {
  handled: boolean
  reason: string
  uid: string
}

export interface RtcCallGatewaySignalResult extends RtcCallGatewayOperationResult {
  signal?: RtcWebRtcSignalHandleResult
}
