import { RtcStartupDataCache, RtcStartupDataCacheStore } from '../core/RtcStartupDataCache'
import { parseRtcSubtitleStyleFrame } from './RtcSubtitleStyle'
import { RtcSubtitleStore } from './RtcSubtitleStore'

/**
 * 网关的样式补发按"这个 Peer 收到过哪个版本"去重，而该标记挂在队列里的 Peer 对象上；
 * 同号重复注册（app 重启、重装）刻意复用旧 Peer，标记跟着活下来，一条样式帧都不会再补发，
 * 界面只能退回内置默认。所以端上把最后一次真正生效的样式落一份，启动时先套上再等网关下发。
 */
const STYLE_PREFERENCE_NAME = 'rtcSubtitleStyle'
const STYLE_KEY = 'style_frame'

export interface RtcSubtitleStyleCacheOptions {
  preferenceName?: string
  /** 单测用的替身存储；不传走设备 preferences。 */
  store?: RtcStartupDataCacheStore
  onLog?: (message: string) => void
}

/** 帧文本原样入库，便于在设备偏好里直接读出来看。 */
function passThrough(value: string): string {
  return value
}

export class RtcSubtitleStyleCache {
  /**
   * 读回缓存样式套到 store 上。这次已经收到过网关帧就不覆盖，以网关为准。
   * 读失败（含不在 UI 上下文、偏好内容损坏）只记一条日志，不影响字幕正文。
   */
  static async restore(subtitleStore: RtcSubtitleStore,
    options?: RtcSubtitleStyleCacheOptions): Promise<boolean> {
    const onLog = options ? options.onLog : undefined
    try {
      const cached = await RtcStartupDataCache.get<string>(STYLE_KEY, {
        preferenceName: options ? options.preferenceName : undefined,
        store: options ? options.store : undefined,
        deserialize: passThrough
      })
      const text = cached.value || ''
      if (!text) {
        return false
      }
      if (!parseRtcSubtitleStyleFrame(text)) {
        if (onLog) {
          onLog('rtc_subtitle_style cache ignored reason=unparsable')
        }
        return false
      }
      const applied = subtitleStore.restoreStyle(text)
      if (!applied && onLog) {
        onLog(`rtc_subtitle_style cache skipped reason=gateway_frame_already_applied updatedAt=${cached.updatedAt}`)
      }
      return applied
    } catch (error) {
      if (onLog) {
        onLog(`rtc_subtitle_style cache restore failed error=${String(error)}`)
      }
      return false
    }
  }

  /** 只存真正应用过的帧原文；返回的 Promise 只为单测可等，链路上失败也只记日志、不打断字幕。 */
  static save(frameText: string, options?: RtcSubtitleStyleCacheOptions): Promise<void> {
    const onLog = options ? options.onLog : undefined
    return RtcStartupDataCache.save<string>(STYLE_KEY, frameText, {
      preferenceName: options ? options.preferenceName : undefined,
      store: options ? options.store : undefined,
      serialize: passThrough
    }).catch((error: Object): void => {
      if (onLog) {
        onLog(`rtc_subtitle_style cache save failed error=${String(error)}`)
      }
    })
  }
}
