export interface RtcWebRtcReconnectOptions {
  enabled?: boolean
  initialDelayMs?: number
  maxDelayMs?: number
  multiplier?: number
  cohortSpreadMs?: number
  stableResetMs?: number
  connectTimeoutMs?: number
  registerTimeoutMs?: number
}

export class RtcWebRtcReconnectConfig {
  enabled: boolean = true
  initialDelayMs: number = 5000
  maxDelayMs: number = 300000
  multiplier: number = 2
  cohortSpreadMs: number = 30000
  stableResetMs: number = 60000
  connectTimeoutMs: number = 15000
  registerTimeoutMs: number = 15000
}

export class RtcWebRtcReconnectPolicy {
  static resolve(options?: RtcWebRtcReconnectOptions): RtcWebRtcReconnectConfig {
    const resolved = new RtcWebRtcReconnectConfig()
    if (!options) {
      return resolved
    }
    resolved.enabled = options.enabled !== false
    resolved.initialDelayMs = Math.max(options.initialDelayMs || resolved.initialDelayMs, 1000)
    resolved.maxDelayMs = Math.max(options.maxDelayMs || resolved.maxDelayMs, resolved.initialDelayMs)
    resolved.multiplier = Math.max(1.2, Math.min(options.multiplier || resolved.multiplier, 4))
    resolved.cohortSpreadMs = Math.max(0, Math.min(
      options.cohortSpreadMs !== undefined ? options.cohortSpreadMs : resolved.cohortSpreadMs,
      Math.max(0, resolved.maxDelayMs - 1000)
    ))
    resolved.stableResetMs = Math.max(options.stableResetMs || resolved.stableResetMs, 10000)
    resolved.connectTimeoutMs = Math.max(options.connectTimeoutMs || resolved.connectTimeoutMs, 5000)
    resolved.registerTimeoutMs = Math.max(options.registerTimeoutMs || resolved.registerTimeoutMs, 5000)
    return resolved
  }

  static calculateDelay(
    config: RtcWebRtcReconnectConfig,
    attempt: number,
    deviceKey: string,
    randomValue: number
  ): number {
    const normalizedAttempt = Math.max(attempt, 1)
    const exponent = Math.min(normalizedAttempt - 1, 20)
    const backoffLimit = Math.max(config.maxDelayMs - config.cohortSpreadMs, config.initialDelayMs)
    const rawBackoff = Math.min(
      backoffLimit,
      config.initialDelayMs * Math.pow(config.multiplier, exponent)
    )
    const random = Math.max(0, Math.min(randomValue, 0.999999))
    const jitteredBackoff = rawBackoff * (0.5 + random * 0.5)
    const cohortOffset = config.cohortSpreadMs > 0 ?
      RtcWebRtcReconnectPolicy.hashDeviceKey(deviceKey) % (config.cohortSpreadMs + 1) : 0
    return Math.min(config.maxDelayMs, Math.floor(jitteredBackoff + cohortOffset))
  }

  static hashDeviceKey(value: string): number {
    let hash = 2166136261
    for (let i = 0; i < value.length; i += 1) {
      hash ^= value.charCodeAt(i)
      hash = Math.imul(hash, 16777619)
    }
    return hash >>> 0
  }
}
