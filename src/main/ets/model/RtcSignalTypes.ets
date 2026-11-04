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
  // 网关在 c__hangup 里带的挂断原因，值是错误码（timeout/rejected/…），不是中文。
  reason?: string
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
  // 网关注册响应下发：true 表示该病区来电只播报不响铃。
  // 产品口径是默认不响铃，宿主按 `!== false` 判定：只有显式 false 才恢复响铃，字段缺省视为静音。
  muteRingtone?: boolean
  // 网关注册响应下发：true 才绘制本机自预览小窗。口径与 muteRingtone 相反——本字段默认在
  // "不画"这一侧，所以只能写 `=== true`，写成 `!== false` 会把默认关变成默认开。
  localPreview?: boolean
}

/** 自预览可见性只认严格 true：键缺省、null、空串、0 一律不画。 */
export function isLocalPreviewEnabled(server?: RtcServerInfo): boolean {
  return server !== undefined && server.localPreview === true
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
  isHold?: boolean
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
