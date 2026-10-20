// 单独成文件是为了能被 Hypium 直接 import：RtcTtsController 顶部挂着 libsherpa_onnx.so 和 media，
// 测试环境里加载不了，把纯取值逻辑放这里才测得到。

export const DEFAULT_SPEECH_RATE = 1.0
const SPEECH_RATE_MIN = 0.5
const SPEECH_RATE_MAX = 2.0

/** 越界或非数一律回落到 1.0：后台填了 0 或 7（少打小数点）时宁可原速，也不要念成一堆噪音。 */
export function clampSpeechRate(value: number): number {
  if (!Number.isFinite(value) || value < SPEECH_RATE_MIN || value > SPEECH_RATE_MAX) {
    return DEFAULT_SPEECH_RATE
  }
  return value
}

/** 后台"参数设置"里的 tts.TextToSpeechSpeechRate 是字符串，空串按未配置处理。 */
export function parseSpeechRate(raw: string): number {
  const trimmed = (raw || '').trim()
  if (trimmed === '') {
    return DEFAULT_SPEECH_RATE
  }
  return clampSpeechRate(Number(trimmed))
}
