export interface RtcWebRtcAudioProcessingOptions {
  echoCancellation: boolean
  noiseSuppression: boolean
  autoGainControl: boolean
  channelCount: number
  sampleRate?: number
}

export interface RtcOhosAudioSourceOptions {
  echoCancellation: boolean
  noiseSuppression: boolean
}

export interface RtcBrowserMediaConstraints {
  audio: RtcWebRtcAudioProcessingOptions
  video: boolean | RtcWebRtcVideoSourceOptions
}

export interface RtcWebRtcVideoSourceOptions {
  width: number
  height: number
  frameRate: number
  facingMode?: string
}

export interface RtcWebRtcStatsOptions {
  enabled: boolean
  intervalMs: number
  activeAudioLevel: number
  silentAudioLevel: number
  logCandidatePair: boolean
  logJitter: boolean
  logPacketLoss: boolean
}

export interface RtcWebRtcOpusOptions {
  minptime: number
  maxptime: number
  ptime: number
  useInBandFec: boolean
  useDtx: boolean
  stereo: boolean
  maxAverageBitrate: number
  googleMinBitrate: number
  googleStartBitrate: number
  googleMaxBitrate: number
}

export class RtcWebRtcConfig {
  static lowLatencyAudio(): RtcWebRtcAudioProcessingOptions {
    return {
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      channelCount: 1
    }
  }

  static lowLatencyOhosAudioSource(): RtcOhosAudioSourceOptions {
    return {
      echoCancellation: true,
      noiseSuppression: true
    }
  }

  static lowLatencyBrowserMedia(video: boolean = false): RtcBrowserMediaConstraints {
    return {
      audio: RtcWebRtcConfig.lowLatencyAudio(),
      video
    }
  }

  static lowBandwidthVideoSource(): RtcWebRtcVideoSourceOptions {
    return {
      width: 640,
      height: 360,
      frameRate: 15,
      facingMode: 'user'
    }
  }

  static defaultStatsOptions(): RtcWebRtcStatsOptions {
    return {
      enabled: true,
      intervalMs: 1000,
      activeAudioLevel: 0.02,
      silentAudioLevel: 0.005,
      logCandidatePair: true,
      logJitter: true,
      logPacketLoss: true
    }
  }

  static lowLatencyOpus(): RtcWebRtcOpusOptions {
    return {
      minptime: 10,
      maxptime: 20,
      ptime: 20,
      useInBandFec: true,
      useDtx: true,
      stereo: false,
      maxAverageBitrate: 32000,
      googleMinBitrate: 6,
      googleStartBitrate: 24,
      googleMaxBitrate: 32
    }
  }
}
