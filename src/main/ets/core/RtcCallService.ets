import { RtcCallMode, RtcPeerIdentity } from '../model/RtcCallConfig'
import { RtcCallViewState, RtcCallViewStateListener } from '../model/RtcCallViewState'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcCallRoute, RtcCallRouteOptions } from './RtcCallRouteResolver'

export interface RtcCallTarget extends RtcPeerIdentity {
  deviceIp?: string
}

export interface RtcCallRuntimeConfig extends RtcCallRouteOptions {
  local: RtcPeerIdentity
  autoAnswer?: boolean
  protocol?: RtcTransportProtocol
  metadata?: Record<string, string>
}

export interface RtcCallPrepareResult {
  route: RtcCallRoute
  viewState: RtcCallViewState
  changed: boolean
  reason: string
}

export interface RtcCallRefreshOptions {
  reason: string
  changedKeys?: string[]
}

export type RtcCallUnsubscribe = () => void

export interface RtcCallService {
  configure(config: RtcCallRuntimeConfig): void
  prepare(reason?: string): Promise<RtcCallPrepareResult>
  startCall(target: RtcCallTarget, mode: RtcCallMode): Promise<void>
  acceptCall(): Promise<void>
  terminateCall(reason?: string): Promise<void>
  refreshConfig(config: RtcCallRuntimeConfig, options: RtcCallRefreshOptions): Promise<RtcCallPrepareResult>
  getViewState(): RtcCallViewState
  onViewStateChange(listener: RtcCallViewStateListener): RtcCallUnsubscribe
  dispose(): void
}

