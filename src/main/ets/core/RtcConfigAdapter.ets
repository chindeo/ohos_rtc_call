import { RtcPeerIdentity } from '../model/RtcCallConfig'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcCallRuntimeConfig } from './RtcCallService'

export interface RtcBusinessRuntimeConfig {
  registerAddress: string
  local: RtcPeerIdentity
  sipPassword?: string
  ntpServer?: string
  bindingCode?: string
  deviceIp?: string
  autoAnswer?: boolean
  metadata?: Record<string, string>
}

export interface RtcRuntimeConfigAdapter<T> {
  toRuntimeConfig(source: T): RtcCallRuntimeConfig
}

export class RtcConfigAdapter {
  static fromBusinessConfig(source: RtcBusinessRuntimeConfig): RtcCallRuntimeConfig {
    return {
      registerAddress: source.registerAddress,
      sipUser: source.local.number,
      sipPassword: source.sipPassword || '',
      ntpServer: source.ntpServer,
      bindingCode: source.bindingCode,
      deviceIp: source.deviceIp,
      local: source.local,
      autoAnswer: source.autoAnswer,
      protocol: undefined,
      metadata: source.metadata
    }
  }

  static shouldUseWebRtc(config: RtcCallRuntimeConfig): boolean {
    return config.protocol === RtcTransportProtocol.WEBRTC
  }
}

