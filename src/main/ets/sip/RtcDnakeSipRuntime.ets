export interface RtcDnakeSipRuntimeConfig {
  deviceType: number
  bindingCode?: string
  ntpServer?: string
  sipUser: string
  sipPassword: string
  sipServer: string
  ringTimeoutSeconds: number
  talkVolume: number
}

export interface RtcDnakeSipDisableConfig {
  ringTimeoutSeconds: number
}

export interface RtcDnakeSipCallInfo {
  mode?: number
  description?: string
  bedCode?: string
  bed_name?: string
  call_user?: string
  device_name?: string
}

export interface RtcDnakeSipRuntimeAdapter {
  setCallListener(listener: Object): void
  configure(config: RtcDnakeSipRuntimeConfig): Promise<void>
  disable(config: RtcDnakeSipDisableConfig): Promise<void>
  isSipAvailable(): boolean
  startCall(sipUser: string, deviceIp: string, info: RtcDnakeSipCallInfo, video: boolean): void
  accept(callId: number): void
  terminate(callId: number): void
  stopPlayRing(): void
  setIncomingRingEnabled(enabled: boolean): void
  setOutgoingRingEnabled(enabled: boolean): void
  setDmsgHandlerEnabled?(enabled: boolean): void
}

export class RtcDnakeSipRuntime {
  private adapter?: RtcDnakeSipRuntimeAdapter

  configureAdapter(adapter: RtcDnakeSipRuntimeAdapter): void {
    this.adapter = adapter
  }

  hasAdapter(): boolean {
    return this.adapter !== undefined
  }

  setCallListener(listener: Object): boolean {
    if (!this.adapter) {
      return false
    }
    this.adapter.setCallListener(listener)
    return true
  }

  configure(config: RtcDnakeSipRuntimeConfig): Promise<boolean> {
    if (!this.adapter) {
      return Promise.resolve(false)
    }
    return this.adapter.configure(config).then(() => true)
  }

  disable(config: RtcDnakeSipDisableConfig): Promise<boolean> {
    if (!this.adapter) {
      return Promise.resolve(false)
    }
    return this.adapter.disable(config).then(() => true)
  }

  isSipAvailable(): boolean {
    return this.adapter?.isSipAvailable() ?? false
  }

  startCall(sipUser: string, deviceIp: string, info: RtcDnakeSipCallInfo, video: boolean = true): boolean {
    if (!this.adapter) {
      return false
    }
    this.adapter.startCall(sipUser, deviceIp, info, video)
    return true
  }

  accept(callId: number): boolean {
    if (!this.adapter || !callId) {
      return false
    }
    this.adapter.accept(callId)
    return true
  }

  terminate(callId: number): boolean {
    if (!this.adapter || !callId) {
      return false
    }
    this.adapter.terminate(callId)
    return true
  }

  stopPlayRing(): void {
    this.adapter?.stopPlayRing()
  }

  setRingEnabled(enabled: boolean): void {
    this.adapter?.setIncomingRingEnabled(enabled)
    this.adapter?.setOutgoingRingEnabled(enabled)
    if (!enabled) {
      this.adapter?.stopPlayRing()
    }
  }

  setDmsgHandlerEnabled(enabled: boolean): void {
    this.adapter?.setDmsgHandlerEnabled?.(enabled)
  }
}
