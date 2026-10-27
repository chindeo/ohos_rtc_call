import { RtcRegisterAddressInfo, RtcRegisterAddressResolver, RtcTransportProtocol } from '../model/RtcProtocolConfig'

export interface RtcCallRoute {
  protocol: RtcTransportProtocol
  registerAddress: RtcRegisterAddressInfo
  webrtcSignalUrl?: string
}

export interface RtcCallRouteOptions {
  registerAddress: string
}

/**
 * 只有一个通路时仍然保留这层：地址不合法要在这里判掉并把 reason 带出去，
 * 不能让调用方拿着一个空的 webrtcSignalUrl 去连信令。
 */
export class RtcCallRouteResolver {
  static resolve(options: RtcCallRouteOptions): RtcCallRoute {
    const registerAddress = RtcRegisterAddressResolver.resolve(options.registerAddress)
    return {
      protocol: RtcTransportProtocol.WEBRTC,
      registerAddress,
      webrtcSignalUrl: registerAddress.valid ? registerAddress.normalizedAddress : undefined
    }
  }
}
