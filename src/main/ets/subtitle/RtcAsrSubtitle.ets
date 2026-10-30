export const RTC_ASR_SUBTITLE_TYPE: string = 'asr_subtitle'

/**
 * 网关字幕帧的线上形状。字段全部可选：契约之外的缺字段帧按静默丢弃处理，
 * 不因为某个字段没给就打断信令分支。
 */
interface RtcAsrSubtitleFrameJson {
  type?: string
  uid?: string
  seq?: number
  state?: string
  text?: string
  source_number?: string
  client_type?: string
  language?: string
  ts?: string
}

interface RtcAsrSubtitleBroadcastWrapper {
  commonRequest?: Object
  data?: string | Object
}

export class RtcAsrSubtitleFrame {
  uid: string = ''
  speaker: string = ''
  text: string = ''
  clientType: string = ''
  language: string = ''
  isFinal: boolean = false
  hasSeq: boolean = false
  seq: number = 0
}

/** 哈希取固定 6 位，日志用它代替完整 uid 和号码：里面是病人信息，日志要在现场看。 */
export function rtcSubtitleIdHash(id: string): string {
  const key = (id || '').trim()
  if (key.length === 0) {
    return 'none'
  }
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

function toFrame(candidate: RtcAsrSubtitleFrameJson | undefined): RtcAsrSubtitleFrame | undefined {
  if (!candidate || candidate.type !== RTC_ASR_SUBTITLE_TYPE) {
    return undefined
  }
  const uid = typeof candidate.uid === 'string' ? candidate.uid.trim() : ''
  const speaker = typeof candidate.source_number === 'string' ? candidate.source_number.trim() : ''
  // 归属和发言人缺一就没法分容器，按契约外的帧处理：丢掉，不猜。
  if (uid.length === 0 || speaker.length === 0) {
    return undefined
  }
  const frame = new RtcAsrSubtitleFrame()
  frame.uid = uid
  frame.speaker = speaker
  frame.text = typeof candidate.text === 'string' ? candidate.text : ''
  frame.clientType = typeof candidate.client_type === 'string' ? candidate.client_type.trim() : ''
  frame.language = typeof candidate.language === 'string' ? candidate.language.trim() : ''
  frame.isFinal = typeof candidate.state === 'string' && candidate.state.trim().toLowerCase() === 'final'
  if (typeof candidate.seq === 'number' && Number.isFinite(candidate.seq)) {
    frame.hasSeq = true
    frame.seq = candidate.seq
  }
  return frame
}

function parseFrameText(text: string): RtcAsrSubtitleFrame | undefined {
  if (!text) {
    return undefined
  }
  try {
    return toFrame(JSON.parse(text) as RtcAsrSubtitleFrameJson)
  } catch (_error) {
    return undefined
  }
}

/**
 * `c__broadcast` 的 data 可能直接是字幕帧，也可能再包一层 BroadcastRequest 壳，
 * 壳里的业务载荷同样是字符串。任何一层解析失败都只返回 undefined，不抛异常。
 */
export function parseRtcAsrSubtitleFrame(data: string): RtcAsrSubtitleFrame | undefined {
  const direct = parseFrameText(data)
  if (direct) {
    return direct
  }
  try {
    const wrapper = JSON.parse(data) as RtcAsrSubtitleBroadcastWrapper
    const nested = wrapper ? wrapper.data : undefined
    if (typeof nested === 'string') {
      return parseFrameText(nested)
    }
    return nested ? toFrame(nested as RtcAsrSubtitleFrameJson) : undefined
  } catch (_error) {
    return undefined
  }
}

/** 空文本和只有标点/符号的帧不产生新行。 */
export function hasRtcSubtitleSayableText(text: string): boolean {
  if (!text) {
    return false
  }
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i)
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true
    }
    if (code >= 0x0041 && code <= 0x005A) {
      return true
    }
    if (code >= 0x0061 && code <= 0x007A) {
      return true
    }
    if (code >= 0x0030 && code <= 0x0039) {
      return true
    }
  }
  return false
}

export function rtcSubtitleSpeakerLabel(clientType: string, sourceNumber: string): string {
  const number = (sourceNumber || '').trim()
  if (number.length === 0) {
    return '对方'
  }
  const type = (clientType || '').trim().toLowerCase()
  if (type === 'bed') {
    return number + '床'
  }
  if (type === 'host') {
    return '主机 ' + number
  }
  if (type === 'door') {
    return '门口 ' + number
  }
  return number
}

const RTC_SUBTITLE_SPEAKER_COLORS: string[] = [
  '#FFFFE066',
  '#FF7DE88C',
  '#FF8AB4FF',
  '#FFFFA8A8',
  '#FFD8B4FE',
  '#FFFFC08A'
]

/** 颜色只由号码决定，同一设备任何时候刷新都落在同一个色值上。 */
export function rtcSubtitleSpeakerColor(sourceNumber: string): string {
  const key = (sourceNumber || '').trim()
  if (key.length === 0) {
    return RTC_SUBTITLE_SPEAKER_COLORS[0]
  }
  let hash = 0
  for (let i = 0; i < key.length; i += 1) {
    hash = (hash * 33 + key.charCodeAt(i)) % 60466176
  }
  return RTC_SUBTITLE_SPEAKER_COLORS[hash % RTC_SUBTITLE_SPEAKER_COLORS.length]
}
