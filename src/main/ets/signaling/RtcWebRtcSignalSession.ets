import webSocket from '@ohos.net.webSocket'
import { RtcRegisterAddressResolver, RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcServerInfo, RtcSignalMessage } from '../model/RtcSignalTypes'

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
}

export class RtcWebRtcSignalSession {
  private socket: webSocket.WebSocket = webSocket.createWebSocket()
  private listener: RtcWebRtcSignalSessionListener = {}
  private bound: boolean = false
  private state: RtcWebRtcSignalState = {
    url: '',
    connecting: false,
    connected: false,
    registered: false,
    lastError: ''
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
    if (this.state.url === url && (this.state.connecting || this.state.connected || this.state.registered)) {
      return { started: false, skipped: true, reason: 'duplicate connection', url }
    }
    if (this.state.url && this.state.url !== url) {
      this.close()
    }

    this.bindEvents()
    this.updateState({
      url,
      connecting: true,
      connected: false,
      registered: false,
      lastError: ''
    })
    this.socket.connect(url, (error, success) => {
      if (error) {
        const errorMessage = this.formatError(error)
        this.updateState({
          connecting: false,
          connected: false,
          registered: false,
          lastError: errorMessage
        })
        this.listener.onError?.(this.state.lastError, this.copyState())
        return
      }
      if (!success) {
        this.updateState({
          connecting: false,
          connected: false,
          registered: false,
          lastError: 'websocket connect failed'
        })
        this.listener.onError?.(this.state.lastError, this.copyState())
      }
    })
    return { started: true, skipped: false, reason: 'connecting', url }
  }

  close(): void {
    try {
      this.socket.close()
      this.socket.off('open')
      this.socket.off('close')
      this.socket.off('error')
      this.socket.off('message')
    } catch (_error) {
    }
    this.socket = webSocket.createWebSocket()
    this.bound = false
    this.updateState({
      url: '',
      connecting: false,
      connected: false,
      registered: false,
      lastError: ''
    })
  }

  sendRaw(message: string): void {
    this.socket.send(message, (error, success) => {
      if (!success) {
        const errorMessage = this.formatError(error)
        this.updateState({ lastError: errorMessage })
        this.listener.onError?.(errorMessage, this.copyState())
      }
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

  private bindEvents(): void {
    if (this.bound) {
      return
    }
    this.bound = true
    this.socket.on('open', () => {
      this.updateState({ connecting: false, connected: true, lastError: '' })
      this.listener.onOpen?.(this.copyState())
    })
    this.socket.on('close', () => {
      this.updateState({ connecting: false, connected: false, registered: false })
      this.listener.onClose?.(this.copyState())
    })
    this.socket.on('error', (error) => {
      const errorMessage = this.formatError(error)
      this.updateState({
        connecting: false,
        connected: false,
        registered: false,
        lastError: errorMessage
      })
      this.listener.onError?.(errorMessage, this.copyState())
    })
    this.socket.on('message', (error, data: string | ArrayBuffer) => {
      if (error) {
        const errorMessage = this.formatError(error)
        this.updateState({ lastError: errorMessage })
        this.listener.onError?.(errorMessage, this.copyState())
        return
      }
      this.dispatchMessages(data.toString())
    })
  }

  private dispatchMessages(text: string): void {
    text.split('<__>').forEach((item: string) => {
      if (!item) {
        return
      }
      try {
        const message = JSON.parse(item) as RtcWebRtcSignalMessage
        if (message.eventName === 'c__register') {
          this.applyRegisterMessage(message)
        }
        this.listener.onMessage?.(message)
      } catch (error) {
        const errorMessage = this.formatError(error)
        this.updateState({ lastError: errorMessage })
        this.listener.onError?.(errorMessage, this.copyState())
      }
    })
  }

  private applyRegisterMessage(message: RtcWebRtcSignalMessage): void {
    const success = message.status === 200
    this.updateState({
      connecting: false,
      connected: success,
      registered: success,
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
  }

  private updateState(change: Partial<RtcWebRtcSignalState>): void {
    this.state = {
      url: change.url ?? this.state.url,
      connecting: change.connecting ?? this.state.connecting,
      connected: change.connected ?? this.state.connected,
      registered: change.registered ?? this.state.registered,
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
      lastError: this.state.lastError
    }
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
