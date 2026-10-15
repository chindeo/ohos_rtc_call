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
  private logger?: (message: string) => void
  private policy: RtcRingtonePolicy = {
    webrtcEnabled: true,
    sipEnabled: true,
    externalUrlEnabled: false
  }

  configureDriver(driver: RtcRingtoneDriver): void {
    this.driver = driver
  }

  configureLogger(logger?: (message: string) => void): void {
    this.logger = logger
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
    const reason = this.localGateReason(channel)
    if (reason) {
      this.log(`ring_local_gate result=skip reason=${reason} channel=${channel}`)
      return
    }
    this.log(`ring_local_gate result=play channel=${channel}`)
    const driver = this.driver as RtcRingtoneDriver
    this.creating = true
    this.stopping = false
    try {
      const started = await driver.playIncoming()
      if (this.stopping) {
        await this.stop()
        return
      }
      this.playing = started
      this.activeChannel = started ? channel : undefined
      if (!started) {
        this.log(`ring_local_gate result=driverRefused channel=${channel}`)
      }
    } finally {
      this.creating = false
    }
  }

  async playUrl(url: string, channel: RtcRingtoneChannel = RtcRingtoneChannel.WEBRTC): Promise<void> {
    const reason = this.urlGateReason(url, channel)
    if (reason) {
      this.log(`ring_url_gate result=skip reason=${reason} channel=${channel}`)
      return
    }
    this.log(`ring_url_gate result=play channel=${channel}`)
    const driver = this.driver as RtcRingtoneDriver
    const playUrl = driver.playUrl as (url: string) => Promise<boolean>
    this.creating = true
    this.stopping = false
    try {
      const started = await playUrl.call(driver, url)
      if (this.stopping) {
        await this.stop()
        return
      }
      this.playing = started
      this.activeChannel = started ? channel : undefined
      if (!started) {
        this.log(`ring_url_gate result=driverRefused channel=${channel}`)
      }
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

  private busyReason(channel: RtcRingtoneChannel): string {
    if (this.playing || this.creating) {
      return 'busy'
    }
    if (!this.isChannelEnabled(channel)) {
      return 'channelDisabled'
    }
    return ''
  }

  private localGateReason(channel: RtcRingtoneChannel): string {
    const busy = this.busyReason(channel)
    if (busy) {
      return busy
    }
    if (!this.driver) {
      return 'noDriver'
    }
    return ''
  }

  private urlGateReason(url: string, channel: RtcRingtoneChannel): string {
    if (!url) {
      return 'emptyUrl'
    }
    if (this.policy.externalUrlEnabled !== true) {
      return 'policyDisabled'
    }
    const busy = this.busyReason(channel)
    if (busy) {
      return busy
    }
    if (!this.driver) {
      return 'noDriver'
    }
    if (!this.driver.playUrl) {
      return 'driverNoUrl'
    }
    return ''
  }

  private log(message: string): void {
    this.logger?.(message)
  }
}
