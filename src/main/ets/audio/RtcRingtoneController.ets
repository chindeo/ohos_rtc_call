export enum RtcRingtoneChannel {
  WEBRTC = 'webrtc',
  SIP = 'sip'
}

export interface RtcRingtoneDriver {
  playIncoming(): Promise<boolean>
  playUrl?(url: string): Promise<boolean>
  stop(): Promise<void>
}

export interface RtcRingtonePolicy {
  webrtcEnabled?: boolean
  sipEnabled?: boolean
  externalUrlEnabled?: boolean
}

export class RtcRingtoneController {
  private driver?: RtcRingtoneDriver
  private playing: boolean = false
  private creating: boolean = false
  private stopping: boolean = false
  private activeChannel: RtcRingtoneChannel | undefined = undefined
  private policy: RtcRingtonePolicy = {
    webrtcEnabled: true,
    sipEnabled: true,
    externalUrlEnabled: false
  }

  configureDriver(driver: RtcRingtoneDriver): void {
    this.driver = driver
  }

  configurePolicy(policy: RtcRingtonePolicy): void {
    this.policy = {
      webrtcEnabled: policy.webrtcEnabled !== false,
      sipEnabled: policy.sipEnabled !== false,
      externalUrlEnabled: policy.externalUrlEnabled === true
    }
  }

  setChannelEnabled(channel: RtcRingtoneChannel, enabled: boolean): void {
    if (channel === RtcRingtoneChannel.SIP) {
      this.policy.sipEnabled = enabled
    } else {
      this.policy.webrtcEnabled = enabled
    }
  }

  isChannelEnabled(channel: RtcRingtoneChannel): boolean {
    if (channel === RtcRingtoneChannel.SIP) {
      return this.policy.sipEnabled !== false
    }
    return this.policy.webrtcEnabled !== false
  }

  getActiveChannel(): RtcRingtoneChannel | undefined {
    return this.activeChannel
  }

  async playIncoming(channel: RtcRingtoneChannel = RtcRingtoneChannel.WEBRTC): Promise<void> {
    if (!this.canPlay(channel) || !this.driver) {
      return
    }
    this.creating = true
    this.stopping = false
    try {
      const started = await this.driver.playIncoming()
      if (this.stopping) {
        await this.stop()
        return
      }
      this.playing = started
      this.activeChannel = started ? channel : undefined
    } finally {
      this.creating = false
    }
  }

  async playUrl(url: string, channel: RtcRingtoneChannel = RtcRingtoneChannel.WEBRTC): Promise<void> {
    if (!url || this.policy.externalUrlEnabled !== true || !this.canPlay(channel) || !this.driver || !this.driver.playUrl) {
      return
    }
    this.creating = true
    this.stopping = false
    try {
      const started = await this.driver.playUrl(url)
      if (this.stopping) {
        await this.stop()
        return
      }
      this.playing = started
      this.activeChannel = started ? channel : undefined
    } finally {
      this.creating = false
    }
  }

  async stop(): Promise<void> {
    if (!this.driver || (!this.playing && !this.creating)) {
      this.playing = false
      this.activeChannel = undefined
      return
    }
    this.stopping = true
    this.playing = false
    this.activeChannel = undefined
    try {
      await this.driver.stop()
    } finally {
      this.stopping = false
    }
  }

  private canPlay(channel: RtcRingtoneChannel): boolean {
    if (this.playing || this.creating) {
      return false
    }
    return this.isChannelEnabled(channel)
  }
}
