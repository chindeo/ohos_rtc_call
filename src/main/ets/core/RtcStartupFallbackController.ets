import { RTC_NETWORK_ERROR_MESSAGE } from './RtcNetworkRequestRecoveryController'

export type RtcStartupFallbackSource = 'network' | 'cache' | 'fallback' | 'empty'

export interface RtcStartupFallbackItem {
  key: string
  label?: string
  required?: boolean
  source?: RtcStartupFallbackSource | string
  usedCache?: boolean
  valueAvailable?: boolean
  errorMessage?: string
}

export interface RtcStartupFallbackEvaluateOptions {
  items: RtcStartupFallbackItem[]
  allowEnterWithMissingRequired?: boolean
  offlineMessage?: string
}

export class RtcStartupFallbackState {
  canEnterHome: boolean = false
  degraded: boolean = false
  message: string = ''
  missingKeys: string[] = []
  cacheKeys: string[] = []
  fallbackKeys: string[] = []
  networkKeys: string[] = []
  errorMessages: string[] = []
}

export class RtcStartupFallbackController {
  static evaluate(options: RtcStartupFallbackEvaluateOptions): RtcStartupFallbackState {
    const state = new RtcStartupFallbackState()
    const offlineMessage = options.offlineMessage || RTC_NETWORK_ERROR_MESSAGE
    const items = options.items || []

    items.forEach((item: RtcStartupFallbackItem) => {
      const key = item.key
      const source = item.source || 'empty'
      const available = item.valueAvailable === true
      if (source === 'network') {
        state.networkKeys.push(key)
      }
      if (item.usedCache === true || source === 'cache') {
        state.cacheKeys.push(key)
      }
      if (source === 'fallback') {
        state.fallbackKeys.push(key)
      }
      if (item.errorMessage) {
        state.errorMessages.push(item.errorMessage)
      }
      if (item.required === true && !available) {
        state.missingKeys.push(key)
      }
    })

    state.degraded = state.missingKeys.length > 0 ||
      state.cacheKeys.length > 0 ||
      state.fallbackKeys.length > 0 ||
      state.errorMessages.length > 0
    state.canEnterHome = state.missingKeys.length === 0 || options.allowEnterWithMissingRequired === true
    state.message = state.degraded ? offlineMessage : ''
    return state
  }
}
