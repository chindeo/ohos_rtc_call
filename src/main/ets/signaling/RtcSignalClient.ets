import webSocket from '@ohos.net.webSocket'
import { RtcApplySignalData, RtcCandidateSignalData, RtcSdpSignalData, RtcServerInfo, RtcSignalMessage } from '../model/RtcSignalTypes'

export interface RtcSignalClientOptions {
  url: string
  number: string
  clientType?: string
  displayName?: string
}

export interface RtcSignalClientListener {
  onOpen?: () => void
  onClose?: () => void
  onError?: (error: Error | string) => void
  onRegister?: (server: RtcServerInfo) => void
  onMessage?: (message: RtcSignalMessage) => void
}

export class RtcSignalClient {
  private socket: webSocket.WebSocket = webSocket.createWebSocket()
  private options: RtcSignalClientOptions
  private listener: RtcSignalClientListener = {}
  private bound: boolean = false
  private opened: boolean = false

  constructor(options: RtcSignalClientOptions) {
    this.options = options
  }

  setListener(listener: RtcSignalClientListener): void {
    this.listener = listener
  }

  isOpen(): boolean {
    return this.opened
  }

  connect(): void {
    this.bindEvents()
    this.socket.connect(this.options.url, (error, value) => {
      if (error) {
        this.listener.onError?.(JSON.stringify(error))
        return
      }
      if (value) {
        this.opened = true
      }
    })
  }

  close(): void {
    try {
      this.socket.close()
    } catch (_error) {
    }
    this.opened = false
  }

  sendApply(data: RtcApplySignalData): void {
    this.sendSignal('s__apply', data)
  }

  sendSdp(data: RtcSdpSignalData): void {
    this.sendSignal('s__sdp', data)
  }

  sendCandidate(data: RtcCandidateSignalData): void {
    this.sendSignal('s__candidate', data)
  }

  sendSignal(eventName: string, data: Object): void {
    const message: RtcSignalMessage = {
      eventName: eventName,
      number: this.options.number,
      clientType: this.options.clientType,
      displayName: this.options.displayName,
      data: JSON.stringify(data)
    }
    this.socket.send(JSON.stringify(message), (error, success) => {
      if (!success) {
        this.listener.onError?.(JSON.stringify(error))
      }
    })
  }

  private bindEvents(): void {
    if (this.bound) {
      return
    }
    this.bound = true
    this.socket.on('open', () => {
      this.opened = true
      this.listener.onOpen?.()
    })
    this.socket.on('close', () => {
      this.opened = false
      this.listener.onClose?.()
    })
    this.socket.on('error', (error) => {
      this.opened = false
      this.listener.onError?.(JSON.stringify(error))
    })
    this.socket.on('message', (error, data: string | ArrayBuffer) => {
      if (error) {
        this.listener.onError?.(JSON.stringify(error))
        return
      }
      const text = data.toString()
      text.split('<__>').forEach((item: string) => {
        if (!item) {
          return
        }
        try {
          const message = JSON.parse(item) as RtcSignalMessage
          if (message.eventName === 'c__register' && message.data) {
            this.listener.onRegister?.(JSON.parse(message.data) as RtcServerInfo)
          }
          this.listener.onMessage?.(message)
        } catch (parseError) {
          this.listener.onError?.(JSON.stringify(parseError))
        }
      })
    })
  }
}
