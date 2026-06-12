import { RtcPeerIdentity } from '../model/RtcCallConfig'

const RTC_BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='

export interface RtcWebRtcTrackIdentity {
  ip: string
  identity: string
  display_name: string
  client_type: string
  number: string
  loc_id: string
  hospital_id: string
  is_mirror: boolean
  is_auto_answer: boolean
  is_expired: boolean
  is_nat: boolean
  conn_type: string
  grpc_port: number
  system_type: string
  app_version: string
  is_hosted: boolean
  hosted_hosts: RtcWebRtcTrackIdentity[]
}

export class RtcWebRtcTrackIdentityCodec {
  private static sequence: number = 0

  static buildTrackId(identity: RtcPeerIdentity, appVersion: string, suffix?: string): string {
    const value: RtcWebRtcTrackIdentity = {
      ip: identity.ip || '',
      identity: identity.identity || identity.number,
      display_name: identity.displayName || identity.number,
      client_type: identity.clientType || '',
      number: identity.number,
      loc_id: identity.locId || '',
      hospital_id: identity.hospitalId || '',
      is_mirror: false,
      is_auto_answer: identity.autoAnswer === true,
      is_expired: false,
      is_nat: false,
      conn_type: 'ws',
      grpc_port: 0,
      system_type: 'android',
      app_version: appVersion,
      is_hosted: false,
      hosted_hosts: []
    }
    RtcWebRtcTrackIdentityCodec.sequence += 1
    const resolvedSuffix = suffix || `${Date.now()}_${RtcWebRtcTrackIdentityCodec.sequence}`
    return RtcWebRtcTrackIdentityCodec.encodeUtf8(JSON.stringify(value)) + '-b___' + resolvedSuffix
  }

  static parse(value?: string): RtcWebRtcTrackIdentity | undefined {
    const encoded = (value || '').trim().split('-b___')[0]
    if (!encoded) {
      return undefined
    }
    try {
      return JSON.parse(RtcWebRtcTrackIdentityCodec.decodeUtf8(encoded)) as RtcWebRtcTrackIdentity
    } catch (_error) {
      return undefined
    }
  }

  static encodeLatin1(value: string): string {
    let output = ''
    let index = 0
    while (index < value.length) {
      const c1 = value.charCodeAt(index++)
      const c2 = index < value.length ? value.charCodeAt(index++) : NaN
      const c3 = index < value.length ? value.charCodeAt(index++) : NaN
      const e1 = c1 >> 2
      const e2 = ((c1 & 3) << 4) | (isNaN(c2) ? 0 : c2 >> 4)
      const e3 = isNaN(c2) ? 64 : (((c2 & 15) << 2) | (isNaN(c3) ? 0 : c3 >> 6))
      const e4 = isNaN(c3) ? 64 : (c3 & 63)
      output += RTC_BASE64_CHARS.charAt(e1) + RTC_BASE64_CHARS.charAt(e2) +
        RTC_BASE64_CHARS.charAt(e3) + RTC_BASE64_CHARS.charAt(e4)
    }
    return output
  }

  static decodeLatin1(value: string): string {
    const input = value.replace(/[^A-Za-z0-9+/=]/g, '')
    let output = ''
    let index = 0
    while (index < input.length) {
      const e1 = RTC_BASE64_CHARS.indexOf(input.charAt(index++))
      const e2 = RTC_BASE64_CHARS.indexOf(input.charAt(index++))
      const e3 = RTC_BASE64_CHARS.indexOf(input.charAt(index++))
      const e4 = RTC_BASE64_CHARS.indexOf(input.charAt(index++))
      output += String.fromCharCode((e1 << 2) | (e2 >> 4))
      if (e3 !== 64 && e3 !== -1) {
        output += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2))
      }
      if (e4 !== 64 && e4 !== -1) {
        output += String.fromCharCode(((e3 & 3) << 6) | e4)
      }
    }
    return output
  }

  static encodeUtf8(value: string): string {
    let binary = ''
    const bytes = RtcWebRtcTrackIdentityCodec.toUtf8Bytes(value)
    bytes.forEach((byte: number) => {
      binary += String.fromCharCode(byte)
    })
    return RtcWebRtcTrackIdentityCodec.encodeLatin1(binary)
  }

  static decodeUtf8(value: string): string {
    const binary = RtcWebRtcTrackIdentityCodec.decodeLatin1(value)
    const bytes: number[] = []
    for (let i = 0; i < binary.length; i += 1) {
      bytes.push(binary.charCodeAt(i) & 0xff)
    }
    return RtcWebRtcTrackIdentityCodec.fromUtf8Bytes(bytes)
  }

  private static toUtf8Bytes(value: string): number[] {
    const bytes: number[] = []
    for (let i = 0; i < value.length; i += 1) {
      let codePoint = value.charCodeAt(i)
      if (codePoint >= 0xd800 && codePoint <= 0xdbff && i + 1 < value.length) {
        const next = value.charCodeAt(i + 1)
        if (next >= 0xdc00 && next <= 0xdfff) {
          codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (next - 0xdc00)
          i += 1
        }
      }
      if (codePoint <= 0x7f) {
        bytes.push(codePoint)
      } else if (codePoint <= 0x7ff) {
        bytes.push(0xc0 | (codePoint >> 6))
        bytes.push(0x80 | (codePoint & 0x3f))
      } else if (codePoint <= 0xffff) {
        bytes.push(0xe0 | (codePoint >> 12))
        bytes.push(0x80 | ((codePoint >> 6) & 0x3f))
        bytes.push(0x80 | (codePoint & 0x3f))
      } else {
        bytes.push(0xf0 | (codePoint >> 18))
        bytes.push(0x80 | ((codePoint >> 12) & 0x3f))
        bytes.push(0x80 | ((codePoint >> 6) & 0x3f))
        bytes.push(0x80 | (codePoint & 0x3f))
      }
    }
    return bytes
  }

  private static fromUtf8Bytes(bytes: number[]): string {
    let output = ''
    let index = 0
    while (index < bytes.length) {
      const c1 = bytes[index++]
      if (c1 < 0x80) {
        output += String.fromCharCode(c1)
      } else if (c1 < 0xe0 && index < bytes.length) {
        const c2 = bytes[index++]
        output += String.fromCharCode(((c1 & 0x1f) << 6) | (c2 & 0x3f))
      } else if (c1 < 0xf0 && index + 1 < bytes.length) {
        const c2 = bytes[index++]
        const c3 = bytes[index++]
        output += String.fromCharCode(((c1 & 0x0f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f))
      } else if (index + 2 < bytes.length) {
        const c2 = bytes[index++]
        const c3 = bytes[index++]
        const c4 = bytes[index++]
        const codePoint = ((c1 & 0x07) << 18) | ((c2 & 0x3f) << 12) |
          ((c3 & 0x3f) << 6) | (c4 & 0x3f)
        const offset = codePoint - 0x10000
        output += String.fromCharCode(0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff))
      }
    }
    return output
  }
}
