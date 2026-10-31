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
  utterance_id?: number
  sentence_end?: boolean
  sentence_text?: string
  begin_ms?: number
  end_ms?: number
  generation?: number
  source_number?: string
  client_type?: string
  role?: string
  language?: string
  ts?: string
}

interface RtcAsrSubtitleBroadcastWrapper {
  commonRequest?: Object
  data?: string | Object
}

/**
 * v2 契约：一句一帧。text（整场累计）已从帧里删除，显示内容只有 sentence_text。
 * state 是会话级（partial=会话进行中，final=会话收尾），一句是否说完只看 sentence_end。
 */
export class RtcAsrSubtitleFrame {
  uid: string = ''
  speaker: string = ''
  sentenceText: string = ''
  clientType: string = ''
  role: string = ''
  language: string = ''
  ts: string = ''
  sessionFinal: boolean = false
  hasSeq: boolean = false
  seq: number = 0
  hasUtterance: boolean = false
  utteranceId: number = 0
  sentenceEnd: boolean = false
  hasBeginMs: boolean = false
  beginMs: number = 0
  hasEndMs: boolean = false
  endMs: number = 0
  generation: number = 0
}

/** 一行的主键：v2 按 (uid, source_number, utterance_id) 定位，缺 utterance_id 时退回用 seq。 */
export function rtcSubtitleUtteranceKey(frame: RtcAsrSubtitleFrame): string {
  return frame.hasUtterance ? 'utt' + frame.utteranceId : 'seq' + frame.seq
}

function readNumber(value: number | undefined): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
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
  frame.sentenceText = typeof candidate.sentence_text === 'string' ? candidate.sentence_text : ''
  frame.clientType = typeof candidate.client_type === 'string' ? candidate.client_type.trim() : ''
  frame.role = typeof candidate.role === 'string' ? candidate.role.trim().toLowerCase() : ''
  frame.language = typeof candidate.language === 'string' ? candidate.language.trim() : ''
  frame.ts = typeof candidate.ts === 'string' ? candidate.ts.trim() : ''
  frame.sessionFinal = typeof candidate.state === 'string' && candidate.state.trim().toLowerCase() === 'final'
  frame.sentenceEnd = candidate.sentence_end === true
  const seq = readNumber(candidate.seq)
  if (seq !== undefined) {
    frame.hasSeq = true
    frame.seq = seq
  }
  const utterance = readNumber(candidate.utterance_id)
  if (utterance !== undefined) {
    frame.hasUtterance = true
    frame.utteranceId = utterance
  }
  const beginMs = readNumber(candidate.begin_ms)
  if (beginMs !== undefined) {
    frame.hasBeginMs = true
    frame.beginMs = beginMs
  }
  const endMs = readNumber(candidate.end_ms)
  if (endMs !== undefined) {
    frame.hasEndMs = true
    frame.endMs = endMs
  }
  const generation = readNumber(candidate.generation)
  frame.generation = generation === undefined ? 0 : generation
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

function isRtcSubtitleSayableCode(code: number): boolean {
  if (code >= 0x4E00 && code <= 0x9FFF) {
    return true
  }
  if (code >= 0x0041 && code <= 0x005A) {
    return true
  }
  if (code >= 0x0061 && code <= 0x007A) {
    return true
  }
  return code >= 0x0030 && code <= 0x0039
}

/** 空文本和只有标点/符号的帧不产生新行。 */
export function hasRtcSubtitleSayableText(text: string): boolean {
  if (!text) {
    return false
  }
  for (let i = 0; i < text.length; i += 1) {
    if (isRtcSubtitleSayableCode(text.charCodeAt(i))) {
      return true
    }
  }
  return false
}

function rtcSubtitleRolePrefix(role: string): string {
  if (role === 'host') {
    return '主机'
  }
  if (role === 'door') {
    return '门口'
  }
  if (role === 'doctor') {
    return '医生'
  }
  if (role === 'nurse' || role === 'nurses') {
    return '护士站'
  }
  if (role === 'watch') {
    return '手表'
  }
  if (role === 'pda') {
    return 'PDA'
  }
  if (role === 'monitor') {
    return '监护屏'
  }
  if (role === 'web') {
    return '网页'
  }
  return ''
}

/**
 * 显示名只按 role 取，不再枚举 client_type：真机上 1033 显示成裸号码就是漏了 nurses 这类取值。
 * role=other 或没给 role 时回落到裸号码；bed 单独处理成「1022床」这种更自然的说法。
 */
export function rtcSubtitleSpeakerLabel(role: string, sourceNumber: string): string {
  const number = (sourceNumber || '').trim()
  const key = (role || '').trim().toLowerCase()
  if (key === 'bed') {
    return number.length === 0 ? '床旁' : number + '床'
  }
  const prefix = rtcSubtitleRolePrefix(key)
  if (prefix.length === 0) {
    return number.length === 0 ? '对方' : number
  }
  return number.length === 0 ? prefix : prefix + ' ' + number
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
