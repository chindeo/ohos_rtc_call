import { RtcRegisterAddressInfo, RtcRegisterAddressResolver, RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcSipConfig } from '../sip/RtcSipConfig'

export interface RtcCallRoute {
  protocol: RtcTransportProtocol
  registerAddress: RtcRegisterAddressInfo
  webrtcSignalUrl?: string
  sipConfig?: RtcSipConfig
}

export interface RtcCallRouteOptions {
  registerAddress: string
  sipUser?: string
  sipPassword?: string
  ntpServer?: string
  bindingCode?: string
  deviceIp?: string
}

export class RtcCallRouteResolver {
  static resolve(options: RtcCallRouteOptions): RtcCallRoute {
    const registerAddress = RtcRegisterAddressResolver.resolve(options.registerAddress)
    if (registerAddress.protocol === RtcTransportProtocol.WEBRTC) {
      return {
        protocol: RtcTransportProtocol.WEBRTC,
        registerAddress,
        webrtcSignalUrl: registerAddress.normalizedAddress
      }
    }

    return {
      protocol: RtcTransportProtocol.SIP,
      registerAddress,
      sipConfig: {
        sipUser: options.sipUser || '',
        sipPassword: options.sipPassword || '',
        sipServer: registerAddress.normalizedAddress,
        ntpServer: options.ntpServer,
        bindingCode: options.bindingCode,
        deviceIp: options.deviceIp
      }
    }
  }
}
