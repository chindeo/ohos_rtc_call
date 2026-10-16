export enum RtcRingtoneChannel {
  WEBRTC = 'webrtc',
  SIP = 'sip'
}

/**
 * 外链播放器的真实结果。驱动只在确实观测到时才回报，
 * 控制器据此决定要不要回落本地铃声，不能靠"设置完 url"来判定出声。
 */
export enum RtcRingtoneUrlResult {
  PLAYING = 'playing',
  ERROR = 'error',
  IDLE = 'idle'
}

export interface RtcRingtoneDriver {
  playIncoming(): Promise<boolean>
  playUrl?(url: string, onResult?: (result: RtcRingtoneUrlResult) => void): Promise<boolean>
  stop(): Promise<void>
}

export interface RtcRingtonePolicy {
  webrtcEnabled?: boolean
  sipEnabled?: boolean
  externalUrlEnabled?: boolean
  urlFallbackEnabled?: boolean
  urlFallbackTimeoutMs?: number
}

const DEFAULT_URL_FALLBACK_TIMEOUT_MS = 1200

/**
 * 一次外链派发的回落上下文。必须挂在实例字段上：驱动的 error 回调几乎总比
 * playUrl() 的 promise 晚到，用局部变量记回落意图会在外层返回后永远无人读取。
 */
interface RtcUrlFallbackCall {
  settled: boolean
  returned: boolean
  timeoutId: number
  pendingReason: string
}

export class RtcRingtoneController {
  private driver?: RtcRingtoneDriver
  private playing: boolean = false
  private creating: boolean = false
  private stopping: boolean = false
  private activeChannel: RtcRingtoneChannel | undefined = undefined
  private urlCall?: RtcUrlFallbackCall
  private logger?: (message: string) => void
  private policy: RtcRingtonePolicy = {
    webrtcEnabled: true,
    sipEnabled: true,
    externalUrlEnabled: false
  }
  private urlFallbackTimeoutMs: number = DEFAULT_URL_FALLBACK_TIMEOUT_MS

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
      externalUrlEnabled: policy.externalUrlEnabled === true,
      urlFallbackEnabled: policy.urlFallbackEnabled === true
    }
    const timeoutMs = policy.urlFallbackTimeoutMs
    if (typeof timeoutMs === 'number' && Number.isFinite(timeoutMs) && timeoutMs > 0) {
      this.urlFallbackTimeoutMs = timeoutMs
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
    await this.startLocal(this.driver as RtcRingtoneDriver, channel)
  }

  async playUrl(url: string, channel: RtcRingtoneChannel = RtcRingtoneChannel.WEBRTC): Promise<void> {
    const reason = this.urlGateReason(url, channel)
    if (reason) {
      this.log(`ring_url_gate result=skip reason=${reason} channel=${channel}`)
      return
    }
    this.log(`ring_url_gate result=play channel=${channel}`)
    const driver = this.driver as RtcRingtoneDriver
    const playUrl = driver.playUrl as (
      url: string,
      onResult?: (result: RtcRingtoneUrlResult) => void
    ) => Promise<boolean>
    const fallbackEnabled = this.policy.urlFallbackEnabled === true
    const call: RtcUrlFallbackCall = { settled: false, returned: false, timeoutId: -1, pendingReason: '' }
    this.creating = true
    this.stopping = false
    this.urlCall = fallbackEnabled ? call : undefined
    const onResult = (result: RtcRingtoneUrlResult): void => {
      if (call.settled || this.stopping || this.urlCall !== call) {
        return
      }
      if (result === RtcRingtoneUrlResult.PLAYING) {
        call.settled = true
        this.clearUrlFallbackTimer(call)
        this.log(`ring_url_gate result=started channel=${channel}`)
        return
      }
      // error / idle 都说明外链没出声。
      call.settled = true
      this.clearUrlFallbackTimer(call)
      if (call.returned) {
        // 外层 await 已经返回，没人会再读挂起标记，就地回落。
        this.runFallback(driver, channel, 'io')
        return
      }
      call.pendingReason = 'io'
    }
    try {
      const started = await playUrl.call(driver, url, fallbackEnabled ? onResult : undefined)
      if (this.stopping) {
        await this.stop()
        return
      }
      this.playing = started
      this.activeChannel = started ? channel : undefined
      if (!started) {
        this.log(`ring_url_gate result=driverRefused channel=${channel}`)
        if (fallbackEnabled && !call.settled) {
          call.settled = true
          call.pendingReason = 'refused'
        }
      } else if (fallbackEnabled && !call.settled) {
        // 外链要等下载，串行等 playing 会把起音推到几秒后；
        // 所以只开计时器，到期还没出声就回落已预热的本地铃声。
        call.timeoutId = setTimeout((): void => {
          call.timeoutId = -1
          if (call.settled || this.stopping) {
            return
          }
          call.settled = true
          this.runFallback(driver, channel, 'timeout')
        }, this.urlFallbackTimeoutMs)
      }
    } finally {
      this.creating = false
      call.returned = true
    }
    if (call.pendingReason && this.urlCall === call) {
      const pending = call.pendingReason
      call.pendingReason = ''
      this.runFallback(driver, channel, pending)
    }
  }

  private clearUrlFallbackTimer(call: RtcUrlFallbackCall): void {
    if (call.timeoutId >= 0) {
      clearTimeout(call.timeoutId)
      call.timeoutId = -1
    }
  }

  private cancelUrlCall(): void {
    const call = this.urlCall
    if (!call) {
      return
    }
    call.settled = true
    call.pendingReason = ''
    this.clearUrlFallbackTimer(call)
    this.urlCall = undefined
  }

  private async startLocal(driver: RtcRingtoneDriver, channel: RtcRingtoneChannel): Promise<void> {
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

  private runFallback(driver: RtcRingtoneDriver, channel: RtcRingtoneChannel, reason: string): Promise<void> {
    this.cancelUrlCall()
    this.log(`ring_url_gate result=fallback reason=${reason} channel=${channel}`)
    return this.stopUrlAndPlayLocal(driver, channel)
  }

  private async stopUrlAndPlayLocal(driver: RtcRingtoneDriver, channel: RtcRingtoneChannel): Promise<void> {
    // 先复位外链播放器：它可能只是慢，之后突然出声会和本地铃声叠成双音。
    try {
      await driver.stop()
    } catch (error) {
      this.log(`ring_url_gate result=fallbackStopFailed channel=${channel}`)
    }
    this.playing = false
    this.activeChannel = undefined
    await this.startLocal(driver, channel)
  }

  async stop(): Promise<void> {
    // 挂断后驱动的 error/idle 回调还会晚到，取消上下文才不会把本地铃声重新拉起来。
    this.cancelUrlCall()
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
