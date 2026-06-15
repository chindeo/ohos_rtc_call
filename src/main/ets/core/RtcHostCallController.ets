import { RtcAudioController, RtcVideoRendererAdapter } from '../audio/RtcAudioController'
import {
  RTC_DEVICE_ROLE_NURSE_HOST,
  RtcCallAudioPolicyController
} from '../audio/RtcCallAudioPolicyController'
import { RTC_CALL_CONTROL_SOURCE_SCREEN } from './RtcCallControlCommand'
import { RtcCallMode, RtcCallSession, RtcPeerIdentity } from '../model/RtcCallConfig'
import { RtcCallDirection } from '../model/RtcCallViewState'
import { RtcCallDeviceRole } from '../ui/RtcCallUiPresenter'
import { RtcHostCallUiModel, RtcHostCallUiModelListener } from '../model/RtcHostCallUiModel'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'
import { RtcCallControlCommand } from './RtcCallControlCommand'
import {
  RtcDefaultCallService,
  RtcDefaultCallServiceHandlers,
  RtcIncomingCallOptions,
  RtcCallListItem
} from './RtcDefaultCallService'
import {
  RtcHostCallOperationResult,
  RtcHostLocalCardOptions,
  RtcHostMultiCallController
} from './RtcHostMultiCallController'
import { RtcCallTarget, RtcCallUnsubscribe } from './RtcCallService'
import {
  RtcWebRtcCallController,
  RtcWebRtcCallControllerConfig,
  RtcWebRtcCallSessionInfo
} from '../webrtc/RtcWebRtcCallController'
import {
  RtcWebRtcMediaController,
  RtcWebRtcMediaState,
  RtcVideoSurfaceController
} from '../webrtc/RtcWebRtcMediaController'
import { RtcCallStatusNotifier } from '../model/RtcCallStatusMessage'

export interface RtcHostCallControllerOptions {
  serverUrl: string
  local: RtcPeerIdentity
  appVersion: string
  systemType?: string
  autoAnswer?: boolean
  localVideoEnabled?: boolean
  onRegistered?: () => void
  onIncoming?: (session: RtcWebRtcCallSessionInfo) => void
  onConnected?: (sessionKey: string) => void
  onEnded?: (sessionKey: string, all: boolean) => void
  onHold?: (session: RtcCallSession) => void | Promise<void>
  onResume?: (session: RtcCallSession) => void | Promise<void>
  deviceRole?: RtcCallDeviceRole | string
  speakerActionLabel?: string
  speakerActionIsMicSwitch?: boolean
  onMicSwitch?: () => boolean | void | Promise<boolean | void>
  onError?: (message: string) => void
  onLog?: (message: string) => void
}

export class RtcHostCallController {
  private options: RtcHostCallControllerOptions
  private service: RtcDefaultCallService
  private multiCallController: RtcHostMultiCallController
  private mediaController: RtcWebRtcMediaController
  private webRtcController: RtcWebRtcCallController
  private audioPolicyController: RtcCallAudioPolicyController
  private localVideoSurface: RtcVideoSurfaceController = new RtcVideoSurfaceController()
  private remoteVideoSurface: RtcVideoSurfaceController = new RtcVideoSurfaceController()
  private sessionRemoteVideoSurfaces: Map<string, RtcVideoSurfaceController> = new Map()
  private started: boolean = false

  constructor(options: RtcHostCallControllerOptions) {
    this.options = options
    this.audioPolicyController = new RtcCallAudioPolicyController({
      deviceRole: RTC_DEVICE_ROLE_NURSE_HOST,
      restoreVolumeOnEnd: true
    })
    const audioController = new RtcAudioController()
    this.mediaController = new RtcWebRtcMediaController({
      local: options.local,
      appVersion: options.appVersion,
      localVideoEnabled: options.localVideoEnabled,
      audioController,
      onMediaStateChange: (state: RtcWebRtcMediaState) => this.handleMediaStateChange(state),
      onLog: options.onLog,
      onError: options.onError
    })
    const handlers: RtcDefaultCallServiceHandlers = {
      onStartCall: async (target: RtcCallTarget, mode: RtcCallMode, session: RtcCallSession) => {
        const signal = this.webRtcController.registerOutgoingSession(session.requestId, target, mode)
        this.webRtcController.startCall(signal.sessionKey)
      },
      onAcceptCall: async (session: RtcCallSession, command?: RtcCallControlCommand) => {
        const route = await this.audioPolicyController.applyAnswerPolicy(
          command?.source || RTC_CALL_CONTROL_SOURCE_SCREEN,
          'host accept'
        )
        this.multiCallController.setMediaControlState(
          this.getUiModel().muted,
          route.speakerEnabled,
          route.volumePercent
        )
        this.webRtcController.accept(session.uid || session.requestId)
      },
      onTerminateCall: async (session: RtcCallSession, reason: string) => {
        const key = session.uid || session.requestId
        if (reason.indexOf('remote hangup') !== 0) {
          this.webRtcController.hangup(key)
        }
        this.releaseSessionRemoteVideoSurface(key)
        if (this.service.getCallListItems().filter((item: RtcCallListItem) => item.canHangup).length === 0) {
          await this.restoreAfterLastCall('last call ended')
        }
        this.options.onEnded?.(key, false)
      },
      onTerminateAllCalls: async () => {
        this.webRtcController.hangupAll()
        this.releaseAllSessionRemoteVideoSurfaces()
        await this.restoreAfterLastCall('all calls ended')
        this.options.onEnded?.('', true)
      },
      onHoldCall: async (session: RtcCallSession) => {
        const key = this.resolveCallSessionKey(session)
        if (!this.sendHoldSwitch(session, true)) {
          this.rollbackHoldSwitch(session, false)
          return
        }
        this.mediaController.setHeld(key, true)
        await this.options.onHold?.(session)
      },
      onResumeCall: async (session: RtcCallSession) => {
        const key = this.resolveCallSessionKey(session)
        if (!this.sendHoldSwitch(session, false)) {
          this.rollbackHoldSwitch(session, true)
          return
        }
        this.mediaController.setHeld(key, false)
        await this.options.onResume?.(session)
      }
    }
    this.service = new RtcDefaultCallService({ handlers })
    this.service.configure({
      registerAddress: options.serverUrl,
      local: options.local,
      autoAnswer: false,
      protocol: RtcTransportProtocol.WEBRTC
    })
    this.multiCallController = new RtcHostMultiCallController({
      service: this.service,
      deviceRole: options.deviceRole || RtcCallDeviceRole.HOST,
      speakerActionLabel: options.speakerActionLabel ||
        (options.speakerActionIsMicSwitch ? '切麦' : '免提'),
      speakerActionIsMicSwitch: options.speakerActionIsMicSwitch
    })
    this.multiCallController.setLocalCard({
      number: options.local.number,
      displayName: options.local.displayName || options.local.number,
      clientType: options.local.clientType || '',
      hasVideo: options.localVideoEnabled === true,
      videoReady: false
    })
    this.webRtcController = new RtcWebRtcCallController(this.mediaController, {
      onRegistered: () => {
        this.options.onLog?.('rtc host registered')
        this.options.onRegistered?.()
      },
      onIncoming: (session: RtcWebRtcCallSessionInfo) => {
        this.handleIncoming(session)
      },
      onAnswerNotice: (session: RtcWebRtcCallSessionInfo) => {
        this.options.onLog?.('answer notice session=' + session.sessionKey)
      },
      onPublishReady: (sessionKey: string, session?: RtcWebRtcCallSessionInfo) => {
        this.multiCallController.setCallAnswerReady(
          sessionKey,
          true,
          session ? [session.sessionId, session.uid] : [],
          session?.targetNumber || ''
        )
        if (this.options.autoAnswer) {
          this.multiCallController.accept(sessionKey)
        }
      },
      onHangup: (sessionKey: string, all: boolean) => {
        this.handleRemoteHangup(sessionKey, all)
      },
      onHoldChange: (sessionKey: string, isHold: boolean) => {
        this.handleRemoteHoldChange(sessionKey, isHold)
      },
      onError: (message: string) => {
        this.multiCallController.setMessage(message)
        this.options.onError?.(message)
      },
      onLog: options.onLog
    })
    this.bindLocalVideoRenderer(this.localVideoSurface)
    this.bindRemoteVideoRenderer(this.remoteVideoSurface)
  }

  start(): void {
    if (this.started) {
      return
    }
    this.started = true
    const config: RtcWebRtcCallControllerConfig = {
      serverUrl: this.options.serverUrl,
      identity: {
        locId: this.options.local.locId,
        hospitalId: this.options.local.hospitalId,
        number: this.options.local.number,
        displayName: this.options.local.displayName,
        clientType: this.options.local.clientType,
        ip: this.options.local.ip,
        identity: this.options.local.identity,
        isAutoAnswer: this.options.autoAnswer ? 'true' : 'false'
      },
      local: this.options.local,
      appVersion: this.options.appVersion,
      systemType: this.options.systemType || 'android'
    }
    this.webRtcController.start(config)
  }

  async startCall(target: RtcCallTarget, mode: RtcCallMode): Promise<void> {
    await this.multiCallController.startCall(target, mode)
  }

  async accept(sessionKey?: string, command?: RtcCallControlCommand): Promise<RtcHostCallOperationResult> {
    return this.multiCallController.accept(sessionKey, command)
  }

  async hangup(sessionKey?: string, reason: string = 'host single hangup'):
    Promise<RtcHostCallOperationResult> {
    return this.multiCallController.hangup(sessionKey, reason)
  }

  async hangupAll(reason: string = 'host hangup all'): Promise<RtcHostCallOperationResult> {
    return this.multiCallController.hangupAll(reason)
  }

  async hold(sessionKey?: string, command?: RtcCallControlCommand): Promise<RtcHostCallOperationResult> {
    return this.multiCallController.hold(sessionKey, command)
  }

  async resume(sessionKey?: string, command?: RtcCallControlCommand): Promise<RtcHostCallOperationResult> {
    return this.multiCallController.resume(sessionKey, command)
  }

  select(sessionKey?: string): RtcHostCallOperationResult {
    const result = this.multiCallController.select(sessionKey)
    if (result.handled) {
      this.webRtcController.select(result.sessionKey)
    }
    return result
  }

  setLocalCard(options: RtcHostLocalCardOptions): void {
    this.multiCallController.setLocalCard(options)
  }

  setMediaControlState(muted: boolean, speakerEnabled: boolean, volume: number): void {
    this.mediaController.setMuted(muted)
    this.multiCallController.setMediaControlState(muted, speakerEnabled, volume)
  }

  toggleMute(): void {
    const next = !this.getUiModel().muted
    this.audioPolicyController.setMuted(next)
    this.mediaController.setMuted(next)
    const audio = this.audioPolicyController.getState()
    this.multiCallController.setMediaControlState(next, audio.speakerEnabled, audio.currentVolumePercent)
  }

  async toggleSpeaker(): Promise<void> {
    if (this.options.speakerActionIsMicSwitch) {
      const before = this.getUiModel().speakerEnabled === true
      this.options.onLog?.('rtc_mic_switch action=speaker before=' + before)
      if (!this.options.onMicSwitch) {
        this.options.onLog?.('rtc_mic_switch action=speaker success=false reason=missing_callback')
        RtcCallStatusNotifier.warning('当前设备不支持切麦或切换失败')
        return
      }
      try {
        const result = await this.options.onMicSwitch()
        if (result === false) {
          this.options.onLog?.('rtc_mic_switch action=speaker success=false before=' + before)
          RtcCallStatusNotifier.warning('当前设备不支持切麦或切换失败')
          return
        }
        this.multiCallController.setMediaControlState(
          this.getUiModel().muted,
          !before,
          this.getUiModel().volume
        )
        this.options.onLog?.('rtc_mic_switch action=speaker success=true after=' + (!before))
      } catch (error) {
        this.options.onLog?.('rtc_mic_switch action=speaker success=false error=' + JSON.stringify(error))
        RtcCallStatusNotifier.warning('当前设备不支持切麦或切换失败')
      }
      return
    }
    const audio = this.audioPolicyController.getState()
    await this.audioPolicyController.setSpeakerEnabled(!audio.speakerEnabled, 'host toggle speaker')
    const next = this.audioPolicyController.getState()
    this.multiCallController.setMediaControlState(
      this.getUiModel().muted,
      next.speakerEnabled,
      next.currentVolumePercent
    )
  }

  bindLocalVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    this.mediaController.bindLocalVideoRenderer(renderer)
  }

  bindRemoteVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    this.mediaController.bindRemoteVideoRenderer(renderer)
  }

  bindSessionRemoteVideoRenderer(
    sessionKey: string,
    renderer?: RtcVideoRendererAdapter
  ): boolean {
    return this.mediaController.bindSessionRemoteVideoRenderer(sessionKey, renderer)
  }

  getLocalVideoSurfaceController(): RtcVideoSurfaceController {
    return this.localVideoSurface
  }

  getRemoteVideoSurfaceController(): RtcVideoSurfaceController {
    return this.remoteVideoSurface
  }

  getSessionRemoteVideoSurfaceController(sessionKey: string): RtcVideoSurfaceController {
    const key = (sessionKey || '').trim()
    let surface = this.sessionRemoteVideoSurfaces.get(key)
    if (!surface) {
      surface = new RtcVideoSurfaceController()
      this.sessionRemoteVideoSurfaces.set(key, surface)
    }
    this.bindSessionRemoteVideoRenderer(key, surface)
    return surface
  }

  getUiModel(): RtcHostCallUiModel {
    return this.multiCallController.getUiModel()
  }

  onUiModelChange(listener: RtcHostCallUiModelListener): RtcCallUnsubscribe {
    return this.multiCallController.onUiModelChange(listener)
  }

  dispose(): void {
    this.started = false
    this.multiCallController.dispose()
    this.service.dispose()
    this.webRtcController.dispose()
    this.releaseAllSessionRemoteVideoSurfaces()
  }

  private handleIncoming(session: RtcWebRtcCallSessionInfo): void {
    const direction = session.incoming ? RtcCallDirection.INCOMING : RtcCallDirection.OUTGOING
    const incoming: RtcIncomingCallOptions = {
      callId: session.sessionId,
      uid: session.sessionKey,
      from: session.commonRequest.from,
      to: session.commonRequest.to,
      direction,
      target: {
        number: session.targetNumber,
        displayName: session.targetName,
        clientType: session.remoteClientType
      },
      mode: session.mode,
      autoAnswer: false,
      status: session.incoming ? 'incoming' : 'outgoing'
    }
    this.multiCallController.receiveIncomingCall(incoming).then(() => {
      this.options.onIncoming?.(session)
    })
  }

  private handleMediaStateChange(state: RtcWebRtcMediaState): void {
    this.multiCallController.setLocalCard({
      videoReady: state.localVideoReady === true
    })
    this.multiCallController.setCallMediaState(state)
    this.options.onLog?.(`rtc_answer_state channelType=${state.channelType || ''}` +
      ` state=${state.mediaConnected ? 'connected' : 'connecting'}`)
    if (!state.mediaConnected) {
      return
    }
    const result = this.multiCallController.markConnectedByMediaState(state)
    this.options.onLog?.('rtc_answer_mark handled=' + result.handled + ' reason=' + result.reason)
    if (result.handled) {
      this.options.onConnected?.(result.sessionKey)
    }
  }

  private handleRemoteHangup(sessionKey: string, all: boolean): void {
    if (all) {
      this.releaseAllSessionRemoteVideoSurfaces()
      this.multiCallController.hangupAll('remote hangup all')
      return
    }
    this.releaseSessionRemoteVideoSurface(sessionKey)
    this.multiCallController.hangup(sessionKey, 'remote hangup')
  }

  private releaseSessionRemoteVideoSurface(sessionKey: string): void {
    const key = (sessionKey || '').trim()
    if (!key) {
      return
    }
    this.mediaController.bindSessionRemoteVideoRenderer(key, undefined)
    const surface = this.sessionRemoteVideoSurfaces.get(key)
    surface?.setVideoTrack(null)
    this.sessionRemoteVideoSurfaces.delete(key)
  }

  private releaseAllSessionRemoteVideoSurfaces(): void {
    this.sessionRemoteVideoSurfaces.forEach((
      surface: RtcVideoSurfaceController,
      sessionKey: string
    ) => {
      this.mediaController.bindSessionRemoteVideoRenderer(sessionKey, undefined)
      surface.setVideoTrack(null)
    })
    this.sessionRemoteVideoSurfaces.clear()
  }

  private async restoreAfterLastCall(reason: string): Promise<void> {
    await this.audioPolicyController.restoreAfterCall(reason)
    this.mediaController.setMuted(false)
    this.multiCallController.resetMediaControlState()
    this.options.onLog?.('host media controls reset reason=' + reason)
  }

  private resolveCallSessionKey(session: RtcCallSession): string {
    return session.uid || session.requestId || session.calleeNumber
  }

  private buildHoldSwitchCandidates(session: RtcCallSession): string[] {
    const candidates: string[] = [
      session.uid,
      session.requestId,
      session.calleeNumber
    ]
    const unique: string[] = []
    candidates.forEach((candidate: string) => {
      const key = (candidate || '').trim()
      if (key && unique.indexOf(key) < 0) {
        unique.push(key)
      }
    })
    return unique
  }

  private sendHoldSwitch(session: RtcCallSession, isHold: boolean): boolean {
    const candidates = this.buildHoldSwitchCandidates(session)
    for (let i = 0; i < candidates.length; i += 1) {
      const key = candidates[i]
      const sent = isHold ? this.webRtcController.hold(key) : this.webRtcController.resume(key)
      if (sent) {
        this.options.onLog?.('host hold switch sent action=' + (isHold ? 'hold' : 'resume') +
          ' sidHash=' + this.getSessionHash(key))
        return true
      }
    }
    this.options.onLog?.('host hold switch not sent action=' + (isHold ? 'hold' : 'resume') +
      ' sidHash=' + this.getSessionHash(this.resolveCallSessionKey(session)))
    return false
  }

  private rollbackHoldSwitch(session: RtcCallSession, isHold: boolean): void {
    const key = this.resolveCallSessionKey(session)
    const result = this.multiCallController.applyRemoteHold(key, isHold)
    this.mediaController.setHeld(key, isHold)
    this.options.onLog?.('host hold switch rollback action=' + (isHold ? 'hold' : 'resume') +
      ' sidHash=' + this.getSessionHash(key) +
      ' handled=' + result.handled +
      ' reason=' + result.reason)
  }

  private getSessionHash(sessionKey: string): string {
    const key = (sessionKey || '').trim()
    let hash = 0
    for (let i = 0; i < key.length; i += 1) {
      hash = (hash * 33 + key.charCodeAt(i)) % 60466176
    }
    let text = hash.toString(36)
    while (text.length < 6) {
      text = '0' + text
    }
    return text
  }

  private handleRemoteHoldChange(sessionKey: string, isHold: boolean): void {
    const result = this.multiCallController.applyRemoteHold(sessionKey, isHold)
    if (!result.handled) {
      this.options.onLog?.('ignore remote hold state session=' + sessionKey + ' reason=' + result.reason)
      return
    }
    this.mediaController.setHeld(result.sessionKey, isHold)
    const session = this.service.getSessionById(result.sessionKey)
    if (!session) {
      return
    }
    if (isHold) {
      this.options.onHold?.(session)
    } else {
      this.options.onResume?.(session)
    }
  }
}
