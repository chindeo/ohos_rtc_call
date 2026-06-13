import { RtcCallMode } from './RtcCallConfig'
import { RtcCallDirection, RtcCallViewPhase } from './RtcCallViewState'
import { RtcCallDeviceRole, RtcCallUiActionState } from '../ui/RtcCallUiPresenter'

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
  direction: RtcCallDirection = RtcCallDirection.NONE
  phase: RtcCallViewPhase = RtcCallViewPhase.HIDDEN
  mode: RtcCallMode = RtcCallMode.AUDIO
  statusText: string = ''
  durationText: string = ''
  receivedAt: number = 0
  connectedAt: number = 0
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
  speakerActionLabel: string = '免提'
  speakerActionIsMicSwitch: boolean = false
  deviceRole: RtcCallDeviceRole | string = RtcCallDeviceRole.HOST
  volume: number = 0
  videoState: RtcHostVideoState = new RtcHostVideoState()
  message: string = ''
}

export type RtcHostCallUiModelListener = (model: RtcHostCallUiModel) => void
