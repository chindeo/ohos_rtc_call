import { RtcCallSession, RtcCallState, RtcHostPhase } from '../model/RtcCallConfig'

export class RtcCallSessionGuard {
  static isWebRtcCallInProgress(session?: RtcCallSession): boolean {
    if (!session || !session.active) {
      return false
    }
    return session.visible === true ||
      session.pendingTrigger === true ||
      session.state === RtcCallState.CALLING ||
      session.hostPhase === RtcHostPhase.INCOMING_READY ||
      session.hostPhase === RtcHostPhase.OUTGOING_READY ||
      session.hostPhase === RtcHostPhase.MEDIA_ACTIVE
  }
}
