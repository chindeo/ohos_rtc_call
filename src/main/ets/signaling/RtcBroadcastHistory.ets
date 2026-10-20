import { RtcBroadcastSignalData } from '../model/RtcSignalTypes'

/**
 * c__broadcast 携带的通话记录，字段名与网关下发的下划线格式保持一致。
 */
export interface RtcBroadcastHistory {
  uid?: string
  from?: string
  to?: string
  to_name?: string
  from_name?: string
  start_time?: string
  end_time?: string
  is_video?: boolean
  is_auto_answer?: boolean
  status?: string
  hang_up_type?: string
  hang_up_number?: string
  is_mpp?: boolean
  is_hold?: boolean
  is_calling?: boolean
  is_timeout?: boolean
  is_offline?: boolean
}

const RTC_HISTORY_TIMEOUT_STATUS: string[] = ['拨打超时挂断', '拨打回调超时挂断']
const RTC_HISTORY_BUSY_STATUS: string[] = ['主机繁忙，请稍后再试', '对方忙线中']
const RTC_HISTORY_OFFLINE_STATUS: string[] = ['离线挂断']

function matchesStatus(history: RtcBroadcastHistory, timedOut: boolean | undefined, texts: string[]): boolean {
  if (timedOut === true) {
    return true
  }
  const status = (history.status || '').trim()
  return status.length > 0 && texts.indexOf(status) >= 0
}

function parseHistoryObject(text: string): RtcBroadcastHistory | undefined {
  if (!text) {
    return undefined
  }
  try {
    const parsed = JSON.parse(text) as RtcBroadcastHistory
    // 只认带 status 字段的消息，包装壳和媒体降级都不算通话记录。
    return parsed && typeof parsed.status === 'string' ? parsed : undefined
  } catch (_error) {
    return undefined
  }
}

/**
 * 通话记录可能是裸 JSON，也可能被广播的 data 字段再包一层，两种都要认；
 * 口径对齐安卓 BroadcastConst.isOperationType，其余广播继续按未知广播上抛。
 */
export function parseRtcBroadcastHistory(data: string): RtcBroadcastHistory | undefined {
  const direct = parseHistoryObject(data)
  if (direct) {
    return direct
  }
  try {
    const wrapper = JSON.parse(data) as RtcBroadcastSignalData
    const nested = wrapper && typeof wrapper.data === 'string' ? wrapper.data : ''
    return nested ? parseHistoryObject(nested) : undefined
  } catch (_error) {
    return undefined
  }
}

export function isRtcBroadcastHistoryTimeout(history: RtcBroadcastHistory): boolean {
  return matchesStatus(history, history.is_timeout, RTC_HISTORY_TIMEOUT_STATUS)
}

export function isRtcBroadcastHistoryBusy(history: RtcBroadcastHistory): boolean {
  return matchesStatus(history, history.is_calling, RTC_HISTORY_BUSY_STATUS)
}

export function isRtcBroadcastHistoryOffline(history: RtcBroadcastHistory): boolean {
  return matchesStatus(history, history.is_offline, RTC_HISTORY_OFFLINE_STATUS)
}

/**
 * 网关把挂断原因写在 c__hangup 的 reason 字段里（call-gateway `peer_grpc.go` 的
 * `HangUpRequest.Reason = UnwrapErr(e).Error()`），值是**错误码不是中文**；
 * 安卓是拿网关内部 errToGBK 码表翻成中文再念的，鸿蒙拿不到那张表，所以这里只镜像
 * 播报要用的四个码。其余（正常挂断、已接听）返回空串，免得每次挂断都多一句噪音。
 * 网关也可能直接下发中文文本，两种都认。
 */
const RTC_HANGUP_NOTICE_TEXTS: string[][] = [
  ['timeout', '无人接听'],
  ['rejected', '对方拒接'],
  ['other_answer', '其他设备接听'],
  ['is_calling', '对方忙线中']
]

export function rtcHangupReasonText(reason?: string): string {
  const key = (reason || '').trim()
  if (key === '') {
    return ''
  }
  for (const pair of RTC_HANGUP_NOTICE_TEXTS) {
    if (pair[0] === key || pair[1] === key) {
      return pair[1]
    }
  }
  return ''
}
