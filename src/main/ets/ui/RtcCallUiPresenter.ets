import { RtcCallDirection, RtcCallViewPhase, RtcCallViewState } from '../model/RtcCallViewState'
import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'

export enum RtcCallDeviceRole {
  HOST = 'host',
  BED = 'bed'
}

export enum RtcCallUiLayout {
  HIDDEN = 'hidden',
  HOST_MULTI_PARTY = 'host_multi_party',
  BED_SINGLE_PARTY = 'bed_single_party'
}

export enum RtcCallUiAction {
  ACCEPT = 'accept',
  HANGUP = 'hangup',
  HANGUP_ALL = 'hangup_all',
  HOLD = 'hold',
  RESUME = 'resume',
  MUTE = 'mute',
  SPEAKER = 'speaker',
  CAMERA = 'camera'
}

export interface RtcCallUiOptions {
  role: RtcCallDeviceRole | string
  participantCount?: number
  muted?: boolean
  speakerEnabled?: boolean
  cameraEnabled?: boolean
}

export interface RtcCallUiActionState {
  action: RtcCallUiAction
  visible: boolean
  enabled: boolean
  active?: boolean
  label: string
}

export interface RtcCallUiModel {
  layout: RtcCallUiLayout
  visible: boolean
  title: string
  subtitle: string
  phaseText: string
  protocolText: string
  mode: RtcCallMode
  protocol: RtcTransportProtocol
  showVideo: boolean
  showVolume: boolean
  volumePercent: number
  actions: RtcCallUiActionState[]
}

export class RtcCallUiPresenter {
  static present(state: RtcCallViewState, options: RtcCallUiOptions): RtcCallUiModel {
    const visible = state.visible && state.phase !== RtcCallViewPhase.HIDDEN
    const layout = RtcCallUiPresenter.resolveLayout(state, options)
    return {
      layout,
      visible,
      title: RtcCallUiPresenter.resolveTitle(state),
      subtitle: RtcCallUiPresenter.resolveSubtitle(state, options),
      phaseText: RtcCallUiPresenter.resolvePhaseText(state),
      protocolText: state.protocol === RtcTransportProtocol.SIP ? 'SIP' : 'WebRTC',
      mode: state.mode,
      protocol: state.protocol,
      showVideo: state.mode === RtcCallMode.VIDEO,
      showVolume: state.volume.enabled,
      volumePercent: state.volume.percent,
      actions: RtcCallUiPresenter.resolveActions(state, options)
    }
  }

  private static resolveLayout(state: RtcCallViewState, options: RtcCallUiOptions): RtcCallUiLayout {
    if (!state.visible || state.phase === RtcCallViewPhase.HIDDEN) {
      return RtcCallUiLayout.HIDDEN
    }
    if (options.role === RtcCallDeviceRole.HOST) {
      return RtcCallUiLayout.HOST_MULTI_PARTY
    }
    return RtcCallUiLayout.BED_SINGLE_PARTY
  }

  private static resolveTitle(state: RtcCallViewState): string {
    const remoteName = state.remote.displayName || state.remote.number
    if (remoteName) {
      return remoteName
    }
    if (state.direction === RtcCallDirection.INCOMING) {
      return '来电'
    }
    if (state.direction === RtcCallDirection.OUTGOING) {
      return '呼叫中'
    }
    return '音视频通话'
  }

  private static resolveSubtitle(state: RtcCallViewState, options: RtcCallUiOptions): string {
    const participants = options.participantCount || 0
    if (options.role === RtcCallDeviceRole.HOST && participants > 1) {
      return participants + ' 人通话'
    }
    if (state.errorMessage) {
      return state.errorMessage
    }
    if (state.registrationErrorMessage) {
      return state.registrationErrorMessage
    }
    return state.remote.number || state.local.number || ''
  }

  private static resolvePhaseText(state: RtcCallViewState): string {
    switch (state.phase) {
      case RtcCallViewPhase.INCOMING:
        return '来电'
      case RtcCallViewPhase.OUTGOING:
        return '呼叫中'
      case RtcCallViewPhase.CONNECTING:
        return '连接中'
      case RtcCallViewPhase.CONNECTED:
        return '通话中'
      case RtcCallViewPhase.HELD:
        return '保持中'
      case RtcCallViewPhase.ERROR:
        return '通话异常'
      case RtcCallViewPhase.ENDED:
        return '已结束'
      default:
        return ''
    }
  }

  private static resolveActions(state: RtcCallViewState, options: RtcCallUiOptions): RtcCallUiActionState[] {
    const canControlMedia = state.phase === RtcCallViewPhase.CONNECTING ||
      state.phase === RtcCallViewPhase.CONNECTED ||
      state.phase === RtcCallViewPhase.HELD
    const canUseHold = options.role === RtcCallDeviceRole.HOST
    const actions: RtcCallUiActionState[] = [
      {
        action: RtcCallUiAction.ACCEPT,
        visible: state.canAccept,
        enabled: state.canAccept,
        label: '接听'
      },
      {
        action: RtcCallUiAction.HANGUP,
        visible: state.canHangup || state.visible,
        enabled: state.canHangup || state.visible,
        label: '挂断'
      },
      {
        action: RtcCallUiAction.HANGUP_ALL,
        visible: options.role === RtcCallDeviceRole.HOST && (options.participantCount || 0) > 1,
        enabled: options.role === RtcCallDeviceRole.HOST && (options.participantCount || 0) > 1,
        label: '挂断全部'
      },
      {
        action: RtcCallUiAction.HOLD,
        visible: canUseHold && (state.phase === RtcCallViewPhase.CONNECTED ||
          state.phase === RtcCallViewPhase.CONNECTING),
        enabled: canUseHold && (state.phase === RtcCallViewPhase.CONNECTED ||
          state.phase === RtcCallViewPhase.CONNECTING),
        label: '保持'
      },
      {
        action: RtcCallUiAction.RESUME,
        visible: canUseHold && state.phase === RtcCallViewPhase.HELD,
        enabled: canUseHold && state.phase === RtcCallViewPhase.HELD,
        label: '恢复'
      },
      {
        action: RtcCallUiAction.MUTE,
        visible: canControlMedia,
        enabled: canControlMedia,
        active: options.muted === true,
        label: '静音'
      },
      {
        action: RtcCallUiAction.SPEAKER,
        visible: canControlMedia,
        enabled: canControlMedia,
        active: options.speakerEnabled === true,
        label: '扬声器'
      }
    ]
    if (state.mode === RtcCallMode.VIDEO) {
      actions.push({
        action: RtcCallUiAction.CAMERA,
        visible: canControlMedia,
        enabled: canControlMedia,
        active: options.cameraEnabled !== false,
        label: '摄像头'
      })
    }
    return actions
  }
}
