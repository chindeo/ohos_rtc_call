import { RtcCallDirection, RtcCallViewPhase, RtcCallViewState } from '../model/RtcCallViewState'
import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcTransportProtocol } from '../model/RtcProtocolConfig'

export enum RtcSipCallPhase {
  IDLE = 'idle',
  INCOMING = 'incoming',
  OUTGOING = 'outgoing',
  CONNECTED = 'connected',
  HELD = 'held',
  ENDED = 'ended',
  ERROR = 'error'
}

export interface RtcSipCallViewOptions {
  phase: RtcSipCallPhase | string
  visible?: boolean
  number?: string
  displayName?: string
  deviceIp?: string
  callId?: string
  autoAnswer?: boolean
  registered?: boolean
  errorMessage?: string
  registrationErrorMessage?: string
}

export class RtcSipCallStateMapper {
  static toViewState(options: RtcSipCallViewOptions): RtcCallViewState {
    const state = new RtcCallViewState()
    const phase = RtcSipCallStateMapper.normalizePhase(options.phase)
    state.protocol = RtcTransportProtocol.SIP
    state.mode = RtcCallMode.AUDIO
    state.visible = options.visible === true && phase !== RtcSipCallPhase.IDLE
    state.phase = RtcSipCallStateMapper.toViewPhase(phase)
    state.direction = RtcSipCallStateMapper.toDirection(phase)
    state.callId = options.callId || ''
    state.remote = {
      number: options.number || '',
      displayName: options.displayName || options.number || '',
      deviceIp: options.deviceIp || ''
    }
    state.autoAnswer = options.autoAnswer === true
    state.registered = options.registered === true
    state.canAccept = phase === RtcSipCallPhase.INCOMING
    state.canHangup = phase === RtcSipCallPhase.INCOMING ||
      phase === RtcSipCallPhase.OUTGOING ||
      phase === RtcSipCallPhase.CONNECTED ||
      phase === RtcSipCallPhase.HELD
    state.errorMessage = options.errorMessage || ''
    state.registrationErrorMessage = options.registrationErrorMessage || ''
    state.volume.enabled = phase === RtcSipCallPhase.CONNECTED
    return state
  }

  private static normalizePhase(phase: RtcSipCallPhase | string): RtcSipCallPhase {
    switch (phase) {
      case RtcSipCallPhase.INCOMING:
        return RtcSipCallPhase.INCOMING
      case RtcSipCallPhase.OUTGOING:
        return RtcSipCallPhase.OUTGOING
      case RtcSipCallPhase.CONNECTED:
        return RtcSipCallPhase.CONNECTED
      case RtcSipCallPhase.HELD:
        return RtcSipCallPhase.HELD
      case RtcSipCallPhase.ENDED:
        return RtcSipCallPhase.ENDED
      case RtcSipCallPhase.ERROR:
        return RtcSipCallPhase.ERROR
      case RtcSipCallPhase.IDLE:
      default:
        return RtcSipCallPhase.IDLE
    }
  }

  private static toViewPhase(phase: RtcSipCallPhase): RtcCallViewPhase {
    switch (phase) {
      case RtcSipCallPhase.INCOMING:
        return RtcCallViewPhase.INCOMING
      case RtcSipCallPhase.OUTGOING:
        return RtcCallViewPhase.OUTGOING
      case RtcSipCallPhase.CONNECTED:
        return RtcCallViewPhase.CONNECTED
      case RtcSipCallPhase.HELD:
        return RtcCallViewPhase.HELD
      case RtcSipCallPhase.ENDED:
        return RtcCallViewPhase.ENDED
      case RtcSipCallPhase.ERROR:
        return RtcCallViewPhase.ERROR
      case RtcSipCallPhase.IDLE:
      default:
        return RtcCallViewPhase.HIDDEN
    }
  }

  private static toDirection(phase: RtcSipCallPhase): RtcCallDirection {
    switch (phase) {
      case RtcSipCallPhase.INCOMING:
        return RtcCallDirection.INCOMING
      case RtcSipCallPhase.OUTGOING:
        return RtcCallDirection.OUTGOING
      default:
        return RtcCallDirection.NONE
    }
  }
}
