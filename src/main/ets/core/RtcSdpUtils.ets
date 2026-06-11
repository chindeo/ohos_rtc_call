export interface RtcLocalSdpResult {
  sdp: string
  source: string
}

export class RtcSdpUtils {
  static hasIceParams(sdp: string): boolean {
    const value = sdp || ''
    return value.indexOf('a=ice-ufrag:') >= 0 && value.indexOf('a=ice-pwd:') >= 0
  }

  static validateBasicSdp(sdp: string): boolean {
    const value = sdp || ''
    const hasVersion = value.indexOf('v=0') === 0 || value.indexOf('\nv=0') >= 0 || value.indexOf('\r\nv=0') >= 0
    const hasMedia = value.match(/(^|\r?\n)m=/) !== null
    return hasVersion && hasMedia
  }

  static encodeSdp(sdp: string, btoa: (value: string) => string): string {
    return JSON.stringify({ data: btoa(sdp || '') })
  }

  static decodeSdp(raw: string, atob: (value: string) => string): string {
    if (!raw) {
      return ''
    }
    try {
      const wrapper = JSON.parse(raw) as Record<string, string>
      if (wrapper.data) {
        return atob(wrapper.data)
      }
    } catch (_error) {
      return raw
    }
    return raw
  }

  static optimizeOpusForLowLatencyAudio(sdp: string): string {
    if (!sdp) {
      return sdp
    }
    const lines: string[] = sdp.split(/\r\n|\n/)
    let opusPt = ''
    let hasFmtp = false
    let hasPtime = false
    let hasMaxptime = false
    for (let i = 0; i < lines.length; i++) {
      const rtpmap = lines[i].match(/^a=rtpmap:(\d+)\s+opus\/48000/i)
      if (rtpmap) {
        opusPt = rtpmap[1]
      }
      if (opusPt && lines[i].indexOf('a=fmtp:' + opusPt) === 0) {
        hasFmtp = true
      }
      if (lines[i].indexOf('a=ptime:') === 0) {
        hasPtime = true
      }
      if (lines[i].indexOf('a=maxptime:') === 0) {
        hasMaxptime = true
      }
    }
    if (!opusPt) {
      return sdp
    }

    const params: string[] = [
      'minptime=10',
      'useinbandfec=1',
      'usedtx=1',
      'stereo=0',
      'sprop-stereo=0',
      'maxaveragebitrate=32000',
      'x-google-min-bitrate=6',
      'x-google-start-bitrate=24',
      'x-google-max-bitrate=32'
    ]
    const next: string[] = []
    let inAudio = false
    let insertedTiming = false
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      if (line.indexOf('m=audio') === 0) {
        inAudio = true
      } else if (line.indexOf('m=') === 0) {
        inAudio = false
      }
      if (inAudio && !insertedTiming && line.indexOf('a=send') === 0) {
        if (!hasPtime) {
          next.push('a=ptime:20')
        }
        if (!hasMaxptime) {
          next.push('a=maxptime:20')
        }
        insertedTiming = true
      }
      if (line.indexOf('a=fmtp:' + opusPt) === 0) {
        let fmtp = line.split(' ').slice(1).join(' ')
        params.forEach((param: string) => {
          const key = param.split('=')[0]
          if (fmtp.indexOf(key + '=') < 0) {
            fmtp += (fmtp ? ';' : '') + param
          }
        })
        next.push('a=fmtp:' + opusPt + ' ' + fmtp)
      } else {
        next.push(line)
        if (!hasFmtp && line.indexOf('a=rtpmap:' + opusPt) === 0) {
          next.push('a=fmtp:' + opusPt + ' ' + params.join(';'))
        }
      }
    }
    return next.join('\r\n')
  }
}
