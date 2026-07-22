import webSocket from '@ohos.net.webSocket'
import { RtcRegisterAddressResolver, RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcServerInfo, RtcSignalMessage } from '../model/RtcSignalTypes'
import {
  RtcWebRtcReconnectConfig,
  RtcWebRtcReconnectOptions,
  RtcWebRtcReconnectPolicy
} from './RtcWebRtcReconnectPolicy'

export interface RtcWebRtcSignalIdentity {
  locId?: string
  hospitalId?: string
  number: string
  displayName?: string
  clientType?: string
  ip?: string
  identity?: string
  isAutoAnswer?: string
}

export interface RtcWebRtcSignalConnectOptions {
  serverUrl: string
  identity: RtcWebRtcSignalIdentity
  appVersion: string
  systemType?: string
  reconnect?: RtcWebRtcReconnectOptions
}

export interface RtcWebRtcSignalConnectResult {
  started: boolean
  skipped: boolean
  reason: string
  url: string
}

export interface RtcWebRtcSignalState {
  url: string
  connecting: boolean
  connected: boolean
  registered: boolean
  reconnecting: boolean
  reconnectAttempt: number
  nextReconnectAt: number
  lastDisconnectReason: string
  lastError: string
}

export interface RtcWebRtcSignalMessage extends RtcSignalMessage {
  status?: number
  ip?: string
  result?: string
  systemType?: string
  isAutoAnswer?: boolean
}

export interface RtcWebRtcSignalSessionListener {
  onOpen?: (state: RtcWebRtcSignalState) => void
  onClose?: (state: RtcWebRtcSignalState) => void
  onError?: (message: string, state: RtcWebRtcSignalState) => void
  onMessage?: (message: RtcWebRtcSignalMessage) => void
  onRegister?: (message: RtcWebRtcSignalMessage, server?: RtcServerInfo) => void
  onStateChange?: (state: RtcWebRtcSignalState) => void
  onReconnectScheduled?: (attempt: number, delayMs: number, reason: string) => void
  onReconnectAttempt?: (attempt: number, reason: string) => void
}

export interface RtcWebRtcSignalScheduler {
  setTimeout(callback: () => void, delayMs: number): number
  clearTimeout(timer: number): void
  now(): number
}

export interface RtcWebRtcSignalRandomSource {
  next(): number
}

export interface RtcWebRtcSignalSocket {
  connect(url: string, callback: (error: Object | undefined, success: boolean) => void): void
  close(): void
  send(message: string, callback: (error: Object | undefined, success: boolean) => void): void
  onOpen(callback: () => void): void
  onClose(callback: () => void): void
  onError(callback: (error: Object) => void): void
  onMessage(callback: (error: Object | undefined, data: string | ArrayBuffer) => void): void
  clearListeners(): void
}

export interface RtcWebRtcSignalSocketFactory {
  create(): RtcWebRtcSignalSocket
}

export interface RtcWebRtcSignalSessionDependencies {
  scheduler?: RtcWebRtcSignalScheduler
  randomSource?: RtcWebRtcSignalRandomSource
  socketFactory?: RtcWebRtcSignalSocketFactory
}

class RtcDefaultWebRtcSignalScheduler implements RtcWebRtcSignalScheduler {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs)
  }

  clearTimeout(timer: number): void {
    clearTimeout(timer)
  }

  now(): number {
    return Date.now()
  }
}

class RtcDefaultWebRtcSignalRandomSource implements RtcWebRtcSignalRandomSource {
  next(): number {
    return Math.random()
  }
}

class RtcSystemWebRtcSignalSocket implements RtcWebRtcSignalSocket {
  private socket: webSocket.WebSocket = webSocket.createWebSocket()

  connect(url: string, callback: (error: Object | undefined, success: boolean) => void): void {
    this.socket.connect(url, (error, success) => callback(error, success))
  }

  close(): void {
    this.socket.close()
  }

  send(message: string, callback: (error: Object | undefined, success: boolean) => void): void {
    this.socket.send(message, (error, success) => callback(error, success))
  }

  onOpen(callback: () => void): void {
    this.socket.on('open', callback)
  }

  onClose(callback: () => void): void {
    this.socket.on('close', callback)
  }

  onError(callback: (error: Object) => void): void {
    this.socket.on('error', callback)
  }

  onMessage(callback: (error: Object | undefined, data: string | ArrayBuffer) => void): void {
    this.socket.on('message', callback)
  }

  clearListeners(): void {
    this.socket.off('open')
    this.socket.off('close')
    this.socket.off('error')
    this.socket.off('message')
  }
}

class RtcDefaultWebRtcSignalSocketFactory implements RtcWebRtcSignalSocketFactory {
  create(): RtcWebRtcSignalSocket {
    return new RtcSystemWebRtcSignalSocket()
  }
}

export class RtcWebRtcSignalSession {
  private listener: RtcWebRtcSignalSessionListener = {}
  private scheduler: RtcWebRtcSignalScheduler
  private randomSource: RtcWebRtcSignalRandomSource
  private socketFactory: RtcWebRtcSignalSocketFactory
  private socket?: RtcWebRtcSignalSocket
  private connectOptions?: RtcWebRtcSignalConnectOptions
  private reconnectConfig: RtcWebRtcReconnectConfig = RtcWebRtcReconnectPolicy.resolve()
  private desiredUrl: string = ''
  private deviceKey: string = ''
  private generation: number = 0
  private stopped: boolean = true
  private reconnectTimer: number = -1
  private connectTimeoutTimer: number = -1
  private registerTimeoutTimer: number = -1
  private stableResetTimer: number = -1
  private reconnectAttempt: number = 0
  private state: RtcWebRtcSignalState = {
    url: '',
    connecting: false,
    connected: false,
    registered: false,
    reconnecting: false,
    reconnectAttempt: 0,
    nextReconnectAt: 0,
    lastDisconnectReason: '',
    lastError: ''
  }

  constructor(dependencies?: RtcWebRtcSignalSessionDependencies) {
    this.scheduler = dependencies?.scheduler || new RtcDefaultWebRtcSignalScheduler()
    this.randomSource = dependencies?.randomSource || new RtcDefaultWebRtcSignalRandomSource()
    this.socketFactory = dependencies?.socketFactory || new RtcDefaultWebRtcSignalSocketFactory()
  }

  setListener(listener: RtcWebRtcSignalSessionListener): void {
    this.listener = listener
  }

  getState(): RtcWebRtcSignalState {
    return this.copyState()
  }

  isConnected(): boolean {
    return this.state.connected
  }

  isRegistered(): boolean {
    return this.state.registered
  }

  connect(options: RtcWebRtcSignalConnectOptions): RtcWebRtcSignalConnectResult {
    const url = RtcWebRtcSignalSession.buildRegisterUrl(options)
    if (!url) {
      return { started: false, skipped: true, reason: 'empty url', url: '' }
    }
    if (!this.stopped && this.desiredUrl === url &&
      (this.state.connecting || this.state.connected || this.state.registered || this.state.reconnecting)) {
      return { started: false, skipped: true, reason: 'duplicate connection', url }
    }

    this.stopTimers()
    this.disposeSocket()
    this.connectOptions = options
    this.reconnectConfig = RtcWebRtcReconnectPolicy.resolve(options.reconnect)
    this.desiredUrl = url
    this.deviceKey = RtcWebRtcSignalSession.buildDeviceKey(options.identity)
    this.reconnectAttempt = 0
    this.stopped = false
    this.startConnection('initial connect')
    return { started: true, skipped: false, reason: 'connecting', url }
  }

  close(): void {
    this.stopped = true
    this.connectOptions = undefined
    this.desiredUrl = ''
    this.deviceKey = ''
    this.reconnectAttempt = 0
    this.stopTimers()
    this.disposeSocket()
    this.updateState({
      url: '',
      connecting: false,
      connected: false,
      registered: false,
      reconnecting: false,
      reconnectAttempt: 0,
      nextReconnectAt: 0,
      lastDisconnectReason: '',
      lastError: ''
    })
  }

  sendRaw(message: string): void {
    const socket = this.socket
    const generation = this.generation
    if (!socket || !this.state.connected) {
      const errorMessage = 'signal socket is not connected'
      this.notifyError(errorMessage)
      this.scheduleReconnect(errorMessage, generation)
      return
    }
    socket.send(message, (error, success) => {
      if (!this.isCurrentGeneration(generation) || success) {
        return
      }
      const errorMessage = this.formatError(error)
      this.notifyError(errorMessage)
      this.scheduleReconnect(errorMessage, generation)
    })
  }

  sendSignal(message: RtcSignalMessage): void {
    this.sendRaw(JSON.stringify(message))
  }

  static buildRegisterUrl(options: RtcWebRtcSignalConnectOptions): string {
    const addressInfo = RtcRegisterAddressResolver.resolve((options.serverUrl || '').trim())
    const serverUrl = addressInfo.protocol === RtcTransportProtocol.WEBRTC && addressInfo.valid ?
      addressInfo.normalizedAddress : (options.serverUrl || '').trim()
    const number = (options.identity.number || '').trim()
    if (!serverUrl || !number) {
      return ''
    }
    const identity = options.identity
    const systemType = options.systemType || 'android'
    const queryPrefix = serverUrl.indexOf('?') >= 0 ? '&' : '?'
    return serverUrl +
      queryPrefix + 'locId=' + encodeURIComponent(identity.locId || '') +
      '&hospitalId=' + encodeURIComponent(identity.hospitalId || '') +
      '&number=' + encodeURIComponent(number) +
      '&displayName=' + encodeURIComponent(identity.displayName || '') +
      '&clientType=' + encodeURIComponent(identity.clientType || '') +
      '&ip=' + encodeURIComponent(identity.ip || '') +
      '&identity=' + encodeURIComponent(identity.identity || '') +
      '&isAutoAnswer=' + encodeURIComponent(identity.isAutoAnswer || 'false') +
      '&systemType=' + encodeURIComponent(systemType) +
      '&appVersion=' + encodeURIComponent(options.appVersion)
  }

  private startConnection(reason: string): void {
    if (this.stopped || !this.connectOptions || !this.desiredUrl) {
      return
    }
    this.clearReconnectTimer()
    this.clearConnectTimeoutTimer()
    this.clearRegisterTimeoutTimer()
    this.clearStableResetTimer()
    this.disposeSocket()
    this.socket = this.socketFactory.create()
    const generation = this.generation
    this.bindSocket(this.socket, generation)
    this.updateState({
      url: this.desiredUrl,
      connecting: true,
      connected: false,
      registered: false,
      reconnecting: this.reconnectAttempt > 0,
      reconnectAttempt: this.reconnectAttempt,
      nextReconnectAt: 0,
      lastDisconnectReason: reason,
      lastError: ''
    })
    this.connectTimeoutTimer = this.scheduler.setTimeout(() => {
      if (!this.isCurrentGeneration(generation) || !this.state.connecting) {
        return
      }
      const message = 'websocket connect timeout'
      this.notifyError(message)
      this.scheduleReconnect(message, generation)
    }, this.reconnectConfig.connectTimeoutMs)
    this.socket.connect(this.desiredUrl, (error, success) => {
      if (!this.isCurrentGeneration(generation) || success) {
        return
      }
      const message = error ? this.formatError(error) : 'websocket connect failed'
      this.notifyError(message)
      this.scheduleReconnect(message, generation)
    })
  }

  private bindSocket(socket: RtcWebRtcSignalSocket, generation: number): void {
    socket.onOpen(() => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      this.clearConnectTimeoutTimer()
      this.updateState({ connecting: false, connected: true, lastError: '' })
      this.startRegisterTimeout(generation)
      this.listener.onOpen?.(this.copyState())
    })
    socket.onClose(() => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      const reason = 'websocket closed'
      this.updateState({
        connecting: false,
        connected: false,
        registered: false,
        lastDisconnectReason: reason
      })
      this.listener.onClose?.(this.copyState())
      this.scheduleReconnect(reason, generation)
    })
    socket.onError((error: Object) => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      const message = this.formatError(error)
      this.notifyError(message)
      this.scheduleReconnect(message, generation)
    })
    socket.onMessage((error: Object | undefined, data: string | ArrayBuffer) => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      if (error) {
        const message = this.formatError(error)
        this.notifyError(message)
        this.scheduleReconnect(message, generation)
        return
      }
      this.dispatchMessages(data.toString(), generation)
    })
  }

  private dispatchMessages(text: string, generation: number): void {
    text.split('<__>').forEach((item: string) => {
      if (!item || !this.isCurrentGeneration(generation)) {
        return
      }
      try {
        const message = JSON.parse(item) as RtcWebRtcSignalMessage
        if (message.eventName === 'c__register') {
          this.applyRegisterMessage(message, generation)
        }
        this.listener.onMessage?.(message)
      } catch (error) {
        this.notifyError(this.formatError(error))
      }
    })
  }

  private applyRegisterMessage(message: RtcWebRtcSignalMessage, generation: number): void {
    if (!this.isCurrentGeneration(generation)) {
      return
    }
    const success = message.status === 200
    this.clearRegisterTimeoutTimer()
    this.updateState({
      connecting: false,
      connected: success,
      registered: success,
      reconnecting: false,
      nextReconnectAt: 0,
      lastError: success ? '' : (message.result || 'register failed')
    })

    let server: RtcServerInfo | undefined
    if (success && message.data) {
      try {
        server = JSON.parse(message.data) as RtcServerInfo
      } catch (error) {
        this.updateState({ lastError: this.formatError(error) })
      }
    }
    this.listener.onRegister?.(message, server)
    if (success) {
      this.startStableResetTimer(generation)
      return
    }
    this.scheduleReconnect(message.result || 'register failed', generation)
  }

  private scheduleReconnect(reason: string, generation: number): void {
    if (!this.isCurrentGeneration(generation) || this.stopped || !this.connectOptions ||
      !this.reconnectConfig.enabled || this.reconnectTimer >= 0) {
      return
    }
    this.clearConnectTimeoutTimer()
    this.clearRegisterTimeoutTimer()
    this.clearStableResetTimer()
    this.disposeSocket()
    this.reconnectAttempt += 1
    const delayMs = RtcWebRtcReconnectPolicy.calculateDelay(
      this.reconnectConfig,
      this.reconnectAttempt,
      this.deviceKey,
      this.randomSource.next()
    )
    const timerGeneration = this.generation
    this.updateState({
      connecting: false,
      connected: false,
      registered: false,
      reconnecting: true,
      reconnectAttempt: this.reconnectAttempt,
      nextReconnectAt: this.scheduler.now() + delayMs,
      lastDisconnectReason: reason,
      lastError: reason
    })
    this.listener.onReconnectScheduled?.(this.reconnectAttempt, delayMs, reason)
    this.reconnectTimer = this.scheduler.setTimeout(() => {
      if (this.stopped || timerGeneration !== this.generation) {
        return
      }
      this.reconnectTimer = -1
      this.listener.onReconnectAttempt?.(this.reconnectAttempt, reason)
      this.startConnection(reason)
    }, delayMs)
  }

  private startRegisterTimeout(generation: number): void {
    this.clearRegisterTimeoutTimer()
    this.registerTimeoutTimer = this.scheduler.setTimeout(() => {
      if (!this.isCurrentGeneration(generation) || this.state.registered) {
        return
      }
      const message = 'websocket register timeout'
      this.notifyError(message)
      this.scheduleReconnect(message, generation)
    }, this.reconnectConfig.registerTimeoutMs)
  }

  private startStableResetTimer(generation: number): void {
    this.clearStableResetTimer()
    this.stableResetTimer = this.scheduler.setTimeout(() => {
      if (!this.isCurrentGeneration(generation) || !this.state.registered) {
        return
      }
      this.reconnectAttempt = 0
      this.updateState({ reconnectAttempt: 0 })
    }, this.reconnectConfig.stableResetMs)
  }

  private notifyError(message: string): void {
    this.updateState({
      connecting: false,
      connected: false,
      registered: false,
      lastDisconnectReason: message,
      lastError: message
    })
    this.listener.onError?.(message, this.copyState())
  }

  private stopTimers(): void {
    this.clearReconnectTimer()
    this.clearConnectTimeoutTimer()
    this.clearRegisterTimeoutTimer()
    this.clearStableResetTimer()
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer >= 0) {
      this.scheduler.clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
  }

  private clearConnectTimeoutTimer(): void {
    if (this.connectTimeoutTimer >= 0) {
      this.scheduler.clearTimeout(this.connectTimeoutTimer)
      this.connectTimeoutTimer = -1
    }
  }

  private clearRegisterTimeoutTimer(): void {
    if (this.registerTimeoutTimer >= 0) {
      this.scheduler.clearTimeout(this.registerTimeoutTimer)
      this.registerTimeoutTimer = -1
    }
  }

  private clearStableResetTimer(): void {
    if (this.stableResetTimer >= 0) {
      this.scheduler.clearTimeout(this.stableResetTimer)
      this.stableResetTimer = -1
    }
  }

  private disposeSocket(): void {
    this.generation += 1
    const socket = this.socket
    this.socket = undefined
    if (!socket) {
      return
    }
    try {
      socket.clearListeners()
      socket.close()
    } catch (_error) {
    }
  }

  private isCurrentGeneration(generation: number): boolean {
    return !this.stopped && generation === this.generation
  }

  private updateState(change: Partial<RtcWebRtcSignalState>): void {
    this.state = {
      url: change.url ?? this.state.url,
      connecting: change.connecting ?? this.state.connecting,
      connected: change.connected ?? this.state.connected,
      registered: change.registered ?? this.state.registered,
      reconnecting: change.reconnecting ?? this.state.reconnecting,
      reconnectAttempt: change.reconnectAttempt ?? this.state.reconnectAttempt,
      nextReconnectAt: change.nextReconnectAt ?? this.state.nextReconnectAt,
      lastDisconnectReason: change.lastDisconnectReason ?? this.state.lastDisconnectReason,
      lastError: change.lastError ?? this.state.lastError
    }
    this.listener.onStateChange?.(this.copyState())
  }

  private copyState(): RtcWebRtcSignalState {
    return {
      url: this.state.url,
      connecting: this.state.connecting,
      connected: this.state.connected,
      registered: this.state.registered,
      reconnecting: this.state.reconnecting,
      reconnectAttempt: this.state.reconnectAttempt,
      nextReconnectAt: this.state.nextReconnectAt,
      lastDisconnectReason: this.state.lastDisconnectReason,
      lastError: this.state.lastError
    }
  }

  private static buildDeviceKey(identity: RtcWebRtcSignalIdentity): string {
    return `${identity.identity || ''}|${identity.number || ''}|${identity.ip || ''}|${identity.clientType || ''}`
  }

  private formatError(error: Error | string | Object | undefined): string {
    if (!error) {
      return 'signal error'
    }
    if (typeof error === 'string') {
      return error || 'signal error'
    }
    const maybeError = error as Error
    if (maybeError.message) {
      return maybeError.message
    }
    const json = JSON.stringify(error)
    if (json && json !== '{}') {
      return json
    }
    const text = `${error}`
    if (text && text !== '[object Object]') {
      return text
    }
    return 'signal error'
  }
}
