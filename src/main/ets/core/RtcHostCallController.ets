import { RtcAudioController, RtcVideoRendererAdapter } from '../audio/RtcAudioController'
import {
  RTC_DEVICE_ROLE_NURSE_HOST,
  RtcCallAudioPolicyController
} from '../audio/RtcCallAudioPolicyController'
import { RTC_CALL_CONTROL_SOURCE_SCREEN } from './RtcCallControlCommand'
import { RtcCallMode, RtcCallSession, RtcPeerIdentity } from '../model/RtcCallConfig'
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
        if (this.service.getCallListItems().filter((item: RtcCallListItem) => item.canHangup).length === 0) {
          await this.audioPolicyController.restoreAfterCall('last call ended')
        }
        this.options.onEnded?.(key, false)
      },
      onTerminateAllCalls: async () => {
        this.webRtcController.hangupAll()
        await this.audioPolicyController.restoreAfterCall('all calls ended')
        this.options.onEnded?.('', true)
      },
      onHoldCall: async (session: RtcCallSession) => {
        const key = session.uid || session.requestId
        this.webRtcController.hold(key)
        this.mediaController.setHeld(key, true)
        await this.options.onHold?.(session)
      },
      onResumeCall: async (session: RtcCallSession) => {
        const key = session.uid || session.requestId
        this.webRtcController.resume(key)
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
    this.multiCallController = new RtcHostMultiCallController({ service: this.service })
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

  getLocalVideoSurfaceController(): RtcVideoSurfaceController {
    return this.localVideoSurface
  }

  getRemoteVideoSurfaceController(): RtcVideoSurfaceController {
    return this.remoteVideoSurface
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
  }

  private handleIncoming(session: RtcWebRtcCallSessionInfo): void {
    const incoming: RtcIncomingCallOptions = {
      callId: session.sessionId,
      uid: session.sessionKey,
      from: session.commonRequest.from,
      to: session.commonRequest.to,
      target: {
        number: session.targetNumber,
        displayName: session.targetName,
        clientType: session.remoteClientType
      },
      mode: session.mode,
      autoAnswer: false,
      status: 'incoming'
    }
    this.multiCallController.receiveIncomingCall(incoming).then(() => {
      this.options.onIncoming?.(session)
    })
  }

  private handleMediaStateChange(state: RtcWebRtcMediaState): void {
    this.multiCallController.setCallMediaState(state)
    if (!state.mediaConnected) {
      return
    }
    const result = this.multiCallController.markConnected(state.sessionKey)
    if (result.handled) {
      this.options.onConnected?.(state.sessionKey)
    }
  }

  private handleRemoteHangup(sessionKey: string, all: boolean): void {
    if (all) {
      this.multiCallController.hangupAll('remote hangup all')
      return
    }
    this.multiCallController.hangup(sessionKey, 'remote hangup')
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
