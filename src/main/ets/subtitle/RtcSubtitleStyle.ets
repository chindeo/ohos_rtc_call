export const RTC_ASR_SUBTITLE_STYLE_TYPE: string = 'asr_subtitle_style'

/** 内置默认配色：收不到样式帧也必须能正常出字幕，样式帧只是覆盖它。 */
export const RTC_SUBTITLE_STYLE_DEFAULT_FONT_SIZE: number = 20
export const RTC_SUBTITLE_STYLE_DEFAULT_TEXT_COLOR: string = '#FFFFFF'
export const RTC_SUBTITLE_STYLE_DEFAULT_BACKGROUND_COLOR: string = '#000000'
export const RTC_SUBTITLE_STYLE_DEFAULT_BACKGROUND_OPACITY: number = 60
export const RTC_SUBTITLE_STYLE_DEFAULT_STROKE_COLOR: string = '#000000'
export const RTC_SUBTITLE_STYLE_DEFAULT_STROKE_WIDTH: number = 1

const FONT_SIZE_MIN: number = 12
const FONT_SIZE_MAX: number = 48
const STROKE_WIDTH_MAX: number = 4

/**
 * 网关后台下发的字幕样式。整场通话级、全场统一一份，不按 uid 或发言人分桶。
 * background_opacity=0 与 stroke_width=0 都是运维的主动选择，绝不替换成默认值。
 */
export class RtcSubtitleStyleSpec {
  fontSize: number = RTC_SUBTITLE_STYLE_DEFAULT_FONT_SIZE
  textColor: string = RTC_SUBTITLE_STYLE_DEFAULT_TEXT_COLOR
  backgroundColor: string = RTC_SUBTITLE_STYLE_DEFAULT_BACKGROUND_COLOR
  backgroundOpacity: number = RTC_SUBTITLE_STYLE_DEFAULT_BACKGROUND_OPACITY
  strokeColor: string = RTC_SUBTITLE_STYLE_DEFAULT_STROKE_COLOR
  strokeWidth: number = RTC_SUBTITLE_STYLE_DEFAULT_STROKE_WIDTH
}

export class RtcSubtitleStyleFrame {
  styleVersion: number = 0
  style: RtcSubtitleStyleSpec = new RtcSubtitleStyleSpec()
  /** 被回落到默认值的字段名，只进日志点名用，不打整帧内容。 */
  fallbackFields: string[] = []
}

interface RtcSubtitleStyleFrameJson {
  type?: string
  style_version?: number
  font_size?: number
  text_color?: string
  background_color?: string
  background_opacity?: number
  stroke_color?: string
  stroke_width?: number
}

interface RtcSubtitleStyleBroadcastWrapper {
  commonRequest?: Object
  data?: string | Object
}

function readFiniteNumber(value: number | undefined): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

/** 只认 #RRGGBB / #RGB（大小写都收，归一成大写）；其它写法一律判非法由调用方回落。 */
export function normalizeRtcSubtitleHexColor(value: string | undefined): string | undefined {
  if (typeof value !== 'string') {
    return undefined
  }
  const raw = value.trim()
  if (raw.length !== 4 && raw.length !== 7) {
    return undefined
  }
  if (raw.charAt(0) !== '#') {
    return undefined
  }
  const hex = '0123456789abcdefABCDEF'
  for (let i = 1; i < raw.length; i += 1) {
    if (hex.indexOf(raw.charAt(i)) < 0) {
      return undefined
    }
  }
  if (raw.length === 4) {
    return ('#' + raw.charAt(1) + raw.charAt(1) + raw.charAt(2) + raw.charAt(2) +
      raw.charAt(3) + raw.charAt(3)).toUpperCase()
  }
  return raw.toUpperCase()
}

function toTwoHex(value: number): string {
  const text = value.toString(16).toUpperCase()
  return text.length < 2 ? '0' + text : text
}

/** 底色 = 颜色 + 不透明度合成的 #AARRGGBB；opacity=0 时 alpha=00，完全透明。 */
export function rtcSubtitleBackgroundArgb(style: RtcSubtitleStyleSpec): string {
  const clamped = Math.max(0, Math.min(100, Math.round(style.backgroundOpacity)))
  const alpha = Math.round(clamped * 255 / 100)
  return '#' + toTwoHex(alpha) + style.backgroundColor.substring(1)
}

/** 描边色带满 alpha 供 textShadow 使用；stroke_width=0 时调用方不应再挂阴影。 */
export function rtcSubtitleStrokeArgb(style: RtcSubtitleStyleSpec): string {
  return '#FF' + style.strokeColor.substring(1)
}

/**
 * 给 #RRGGBB 叠一个 0–1 的 alpha，返回 #AARRGGBB。
 * 弱显（上一句）只该作用在文字上：opacity 挂在整条 Text 上会把底色一起变淡。
 */
export function rtcSubtitleWithAlpha(hexColor: string, alpha: number): string {
  const clamped = Math.max(0, Math.min(1, alpha))
  return '#' + toTwoHex(Math.round(clamped * 255)) + hexColor.substring(1)
}

/** 行高按字号稳定计算：同一行内样式变化不造成行高跳变或文字位置抖动。 */
export function rtcSubtitleLineHeightFromFp(fontSizeFp: number): number {
  return Math.round(fontSizeFp * 1.4)
}

function pickFontSize(value: number | undefined, fallbacks: string[]): number {
  const parsed = readFiniteNumber(value)
  if (parsed === undefined || parsed < FONT_SIZE_MIN || parsed > FONT_SIZE_MAX) {
    fallbacks.push('font_size')
    return RTC_SUBTITLE_STYLE_DEFAULT_FONT_SIZE
  }
  return Math.round(parsed)
}

function pickColor(value: string | undefined, fallbacks: string[], field: string): string {
  const normalized = normalizeRtcSubtitleHexColor(value)
  if (normalized === undefined) {
    fallbacks.push(field)
    return field === 'text_color' ? RTC_SUBTITLE_STYLE_DEFAULT_TEXT_COLOR :
      (field === 'stroke_color' ? RTC_SUBTITLE_STYLE_DEFAULT_STROKE_COLOR :
        RTC_SUBTITLE_STYLE_DEFAULT_BACKGROUND_COLOR)
  }
  return normalized
}

function pickOpacity(value: number | undefined, fallbacks: string[]): number {
  const parsed = readFiniteNumber(value)
  if (parsed === undefined || parsed < 0 || parsed > 100) {
    fallbacks.push('background_opacity')
    return RTC_SUBTITLE_STYLE_DEFAULT_BACKGROUND_OPACITY
  }
  return Math.round(parsed)
}

function pickStrokeWidth(value: number | undefined, fallbacks: string[]): number {
  const parsed = readFiniteNumber(value)
  if (parsed === undefined || parsed < 0 || parsed > STROKE_WIDTH_MAX) {
    fallbacks.push('stroke_width')
    return RTC_SUBTITLE_STYLE_DEFAULT_STROKE_WIDTH
  }
  return Math.round(parsed)
}

function pickStyleVersion(value: number | undefined, fallbacks: string[]): number {
  const parsed = readFiniteNumber(value)
  if (parsed === undefined) {
    fallbacks.push('style_version')
    return 0
  }
  return Math.round(parsed)
}

function toStyleFrame(candidate: RtcSubtitleStyleFrameJson | undefined): RtcSubtitleStyleFrame | undefined {
  if (!candidate || candidate.type !== RTC_ASR_SUBTITLE_STYLE_TYPE) {
    return undefined
  }
  const fallbacks: string[] = []
  const frame = new RtcSubtitleStyleFrame()
  frame.styleVersion = pickStyleVersion(candidate.style_version, fallbacks)
  const style = new RtcSubtitleStyleSpec()
  style.fontSize = pickFontSize(candidate.font_size, fallbacks)
  style.textColor = pickColor(candidate.text_color, fallbacks, 'text_color')
  style.backgroundColor = pickColor(candidate.background_color, fallbacks, 'background_color')
  style.backgroundOpacity = pickOpacity(candidate.background_opacity, fallbacks)
  style.strokeColor = pickColor(candidate.stroke_color, fallbacks, 'stroke_color')
  style.strokeWidth = pickStrokeWidth(candidate.stroke_width, fallbacks)
  frame.style = style
  frame.fallbackFields = fallbacks
  return frame
}

function parseStyleText(text: string): RtcSubtitleStyleFrame | undefined {
  if (!text) {
    return undefined
  }
  try {
    return toStyleFrame(JSON.parse(text) as RtcSubtitleStyleFrameJson)
  } catch (_error) {
    return undefined
  }
}

/**
 * 与正文帧同一条三层嵌套链路：WS 信封 → BroadcastRequest 壳 → 样式帧，每层 data 都是字符串。
 * 任何一层解析失败只返回 undefined，不抛异常，调用方继续走原有业务分支。
 */
export function parseRtcSubtitleStyleFrame(data: string): RtcSubtitleStyleFrame | undefined {
  const direct = parseStyleText(data)
  if (direct) {
    return direct
  }
  try {
    const wrapper = JSON.parse(data) as RtcSubtitleStyleBroadcastWrapper
    const nested = wrapper ? wrapper.data : undefined
    if (typeof nested === 'string') {
      return parseStyleText(nested)
    }
    return nested ? toStyleFrame(nested as RtcSubtitleStyleFrameJson) : undefined
  } catch (_error) {
    return undefined
  }
}

/**
 * 落盘用的规范化帧：只写网关语义那几个键。回读仍旧走 parseRtcSubtitleStyleFrame，
 * 不给缓存自成一套宽松解析——否则半截或旧结构的值会直接画上界面，还绕开逐字段回落日志。
 */
export function serializeRtcSubtitleStyleFrame(version: number, style: RtcSubtitleStyleSpec): string {
  const frame: RtcSubtitleStyleFrameJson = {
    type: RTC_ASR_SUBTITLE_STYLE_TYPE,
    style_version: version,
    font_size: style.fontSize,
    text_color: style.textColor,
    background_color: style.backgroundColor,
    background_opacity: style.backgroundOpacity,
    stroke_color: style.strokeColor,
    stroke_width: style.strokeWidth
  }
  return JSON.stringify(frame)
}
