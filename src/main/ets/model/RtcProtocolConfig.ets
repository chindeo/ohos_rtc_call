export enum RtcTransportProtocol {
  WEBRTC = 'webrtc',
  SIP = 'sip'
}

export interface RtcRegisterAddressInfo {
  rawAddress: string
  protocol: RtcTransportProtocol
  normalizedAddress: string
  host: string
  port: number
  secure: boolean
  valid: boolean
  reason: string
}

function createInfo(
  rawAddress: string,
  protocol: RtcTransportProtocol,
  normalizedAddress: string,
  host: string,
  port: number,
  secure: boolean,
  valid: boolean,
  reason: string
): RtcRegisterAddressInfo {
  return {
    rawAddress,
    protocol,
    normalizedAddress,
    host,
    port,
    secure,
    valid,
    reason
  }
}

function parsePort(portText: string): number {
  const port = Number(portText)
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    return 0
  }
  return port
}

export class RtcRegisterAddressResolver {
  static resolve(address: string): RtcRegisterAddressInfo {
    const rawAddress = (address || '').trim()
    if (!rawAddress) {
      return createInfo(rawAddress, RtcTransportProtocol.SIP, '', '', 0, false, false, 'empty address')
    }

    const lowerAddress = rawAddress.toLowerCase()
    if (lowerAddress.startsWith('ws://') || lowerAddress.startsWith('wss://')) {
      return RtcRegisterAddressResolver.resolveWebRtc(rawAddress)
    }

    return RtcRegisterAddressResolver.resolveSip(rawAddress)
  }

  static isWebRtcAddress(address: string): boolean {
    return RtcRegisterAddressResolver.resolve(address).protocol === RtcTransportProtocol.WEBRTC
  }

  static isSipAddress(address: string): boolean {
    return RtcRegisterAddressResolver.resolve(address).protocol === RtcTransportProtocol.SIP
  }

  private static resolveWebRtc(address: string): RtcRegisterAddressInfo {
    const secure = address.toLowerCase().startsWith('wss://')
    const protocolEnd = address.indexOf('://') + 3
    const hostAndPath = address.substring(protocolEnd)
    const slashIndex = hostAndPath.indexOf('/')
    const queryIndex = hostAndPath.indexOf('?')
    const hostEnd = slashIndex >= 0 ? slashIndex : (queryIndex >= 0 ? queryIndex : hostAndPath.length)
    const hostPort = hostAndPath.substring(0, hostEnd)
    const hostParts = hostPort.split(':')
    const host = hostParts[0] || ''
    const defaultPort = secure ? 443 : 80
    const port = hostParts.length > 1 ? parsePort(hostParts[1]) : defaultPort
    const valid = host.length > 0 && port > 0
    let normalizedAddress = address
    const path = slashIndex >= 0 ?
      hostAndPath.substring(slashIndex, queryIndex >= 0 ? queryIndex : hostAndPath.length) : ''
    if (valid && (!path || path === '/')) {
      const query = queryIndex >= 0 ? hostAndPath.substring(queryIndex) : ''
      const baseEnd = queryIndex >= 0 ? protocolEnd + queryIndex : address.length
      const base = address.substring(0, baseEnd).replace(/\/$/, '')
      normalizedAddress = `${base}/websocket${query}`
    }
    return createInfo(
      address,
      RtcTransportProtocol.WEBRTC,
      normalizedAddress,
      host,
      port,
      secure,
      valid,
      valid ? 'websocket signaling address' : 'invalid websocket signaling address'
    )
  }

  private static resolveSip(address: string): RtcRegisterAddressInfo {
    const normalizedAddress = address.replace(/^sip:/i, '')
    const hostParts = normalizedAddress.split(':')
    const host = hostParts[0] || ''
    const port = hostParts.length > 1 ? parsePort(hostParts[1]) : 5060
    const valid = host.length > 0 && port > 0
    return createInfo(
      address,
      RtcTransportProtocol.SIP,
      normalizedAddress,
      host,
      port,
      false,
      valid,
      valid ? 'sip server address' : 'invalid sip server address'
    )
  }
}
