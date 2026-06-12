import { RtcCallMode } from './RtcCallConfig'
import { RtcCallViewPhase } from './RtcCallViewState'
import { RtcCallUiActionState } from '../ui/RtcCallUiPresenter'

export class RtcHostLocalCard {
  number: string = ''
  displayName: string = ''
  clientType: string = ''
  hasVideo: boolean = false
  videoReady: boolean = false
}

export class RtcHostCallUiItem {
  sessionKey: string = ''
  callId: string = ''
  uid: string = ''
  peerNumber: string = ''
  displayName: string = ''
  clientType: string = ''
  phase: RtcCallViewPhase = RtcCallViewPhase.HIDDEN
  mode: RtcCallMode = RtcCallMode.AUDIO
  statusText: string = ''
  durationText: string = ''
  isActive: boolean = false
  isSelected: boolean = false
  isHold: boolean = false
  mediaConnected: boolean = false
  hasRemoteAudio: boolean = false
  hasRemoteVideo: boolean = false
  canAccept: boolean = false
  canHold: boolean = false
  canResume: boolean = false
  canHangup: boolean = false
}

export class RtcHostVideoState {
  enabled: boolean = false
  localReady: boolean = false
  remoteReady: boolean = false
  activeSessionKey: string = ''
}

export class RtcHostCallUiModel {
  visible: boolean = false
  registered: boolean = false
  localCard: RtcHostLocalCard = new RtcHostLocalCard()
  activeCall?: RtcHostCallUiItem
  sideCalls: RtcHostCallUiItem[] = []
  actions: RtcCallUiActionState[] = []
  showHangupAll: boolean = false
  muted: boolean = false
  speakerEnabled: boolean = false
  volume: number = 0
  videoState: RtcHostVideoState = new RtcHostVideoState()
  message: string = ''
}

export type RtcHostCallUiModelListener = (model: RtcHostCallUiModel) => void
