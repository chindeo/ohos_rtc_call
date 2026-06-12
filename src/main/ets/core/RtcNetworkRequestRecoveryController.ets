export const RTC_NETWORK_ERROR_MESSAGE = '网络异常，请检查网络'

export type RtcNetworkRequestPhase = 'idle' | 'loading' | 'offline' | 'online'

export interface RtcNetworkRequestRecoveryOptions {
  offlineMessage?: string
}

export interface RtcNetworkRequestFailureOptions {
  message?: string
  recoverable?: boolean
}

export interface RtcNetworkRequestCacheOptions {
  usedCache?: boolean
  source?: string
  errorMessage?: string
}

export class RtcNetworkRequestState {
  phase: RtcNetworkRequestPhase = 'idle'
  online: boolean = true
  loading: boolean = false
  message: string = ''
  lastSuccessAt: number = 0
  lastFailureAt: number = 0
  failureCount: number = 0
  usingCache: boolean = false
  errorMessage: string = ''
}

export type RtcNetworkRequestStateListener = (state: RtcNetworkRequestState) => void

export class RtcNetworkRequestRecoveryController {
  private state: RtcNetworkRequestState = new RtcNetworkRequestState()
  private listeners: RtcNetworkRequestStateListener[] = []
  private offlineMessage: string

  constructor(options?: RtcNetworkRequestRecoveryOptions) {
    this.offlineMessage = options?.offlineMessage || RTC_NETWORK_ERROR_MESSAGE
  }

  begin(message: string = ''): RtcNetworkRequestState {
    this.state.loading = true
    this.state.phase = this.state.online ? 'loading' : 'offline'
    if (message && this.state.online) {
      this.state.message = message
    }
    this.emit()
    return this.getState()
  }

  markSuccess(message: string = ''): RtcNetworkRequestState {
    this.state.phase = 'online'
    this.state.online = true
    this.state.loading = false
    this.state.message = message
    this.state.lastSuccessAt = Date.now()
    this.state.failureCount = 0
    this.state.usingCache = false
    this.state.errorMessage = ''
    this.emit()
    return this.getState()
  }

  markFailure(error?: Object, options?: RtcNetworkRequestFailureOptions): RtcNetworkRequestState {
    this.state.phase = 'offline'
    this.state.online = false
    this.state.loading = false
    this.state.message = options?.message || this.offlineMessage
    this.state.lastFailureAt = Date.now()
    this.state.failureCount += 1
    this.state.errorMessage = RtcNetworkRequestRecoveryController.getErrorMessage(error)
    this.emit()
    return this.getState()
  }

  applyCacheResult(options: RtcNetworkRequestCacheOptions): RtcNetworkRequestState {
    if (options.usedCache === true || options.source === 'cache' || options.source === 'fallback') {
      this.state.phase = 'offline'
      this.state.online = false
      this.state.loading = false
      this.state.message = this.offlineMessage
      this.state.lastFailureAt = Date.now()
      this.state.failureCount += 1
      this.state.usingCache = true
      this.state.errorMessage = options.errorMessage || ''
      this.emit()
      return this.getState()
    }
    return this.markSuccess()
  }

  getState(): RtcNetworkRequestState {
    return RtcNetworkRequestRecoveryController.copyState(this.state)
  }

  onChange(listener: RtcNetworkRequestStateListener): () => void {
    this.listeners.push(listener)
    listener(this.getState())
    return () => {
      this.listeners = this.listeners.filter((item: RtcNetworkRequestStateListener) => item !== listener)
    }
  }

  reset(): void {
    this.state = new RtcNetworkRequestState()
    this.emit()
  }

  private emit(): void {
    const snapshot = this.getState()
    this.listeners.forEach((listener: RtcNetworkRequestStateListener) => {
      listener(RtcNetworkRequestRecoveryController.copyState(snapshot))
    })
  }

  private static copyState(state: RtcNetworkRequestState): RtcNetworkRequestState {
    const copy = new RtcNetworkRequestState()
    copy.phase = state.phase
    copy.online = state.online
    copy.loading = state.loading
    copy.message = state.message
    copy.lastSuccessAt = state.lastSuccessAt
    copy.lastFailureAt = state.lastFailureAt
    copy.failureCount = state.failureCount
    copy.usingCache = state.usingCache
    copy.errorMessage = state.errorMessage
    return copy
  }

  private static getErrorMessage(error?: Object): string {
    if (!error) {
      return ''
    }
    const message = JSON.stringify(error)
    return message === '{}' ? `${error}` : message
  }
}
