export interface RtcCommonRequest {
  uuid: string
  locId?: string
  hospitalId?: string
  number: string
  displayName?: string
  clientType?: string
  identity?: string
  to?: string
  toName?: string
  from?: string
  fromName?: string
  grpcFrom?: string
  grpcTo?: string
  isVideo?: boolean
}

export interface RtcSignalPayload {
  commonRequest: RtcCommonRequest
  applyType?: number
  isAll?: boolean
  isHangUp?: boolean
  sdp?: string
  sdpType?: string
  rtcUid?: string
  candidate?: string
  sdpMLineIndex?: number
  sdpMid?: string
}

export interface RtcSignalMessage {
  eventName: string
  number?: string
  clientType?: string
  displayName?: string
  data: string
}

export interface RtcServerInfo {
  serveNumber: string
  serveIp: string
  serveDisplayName: string
  iceConf?: string
  i10n?: string
}

export interface RtcApplySignalData {
  applyType: number
  toIp: string
  isAll: boolean
  commonRequest: RtcCommonRequest
}

export interface RtcBroadcastSignalData {
  data: string
}

export interface RtcHoldSwitchNotice {
  type?: string
  info?: string | Record<string, boolean>
  uid?: string
  status?: string
  is_hold?: boolean
}

export interface RtcSdpSignalData {
  sdp: string
  sdpType: string
  rtcUid: string
  commonRequest: RtcCommonRequest
}

export interface RtcCandidateSignalData {
  candidateType: string
  candidate: string
  sdpMLineIndex?: number
  sdpMid?: string
  rtcUid: string
  commonRequest: RtcCommonRequest
}
