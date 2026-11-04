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
  // 本机自预览小窗是否绘制，来自网关注册响应的 localPreview，默认不画。
  // 只影响这块视图是否进组件树，不影响采集、编码与上行。
  showLocalPreview: boolean = false
  activeCall?: RtcHostCallUiItem
  sideCalls: RtcHostCallUiItem[] = []
  actions: RtcCallUiActionState[] = []
  showHangupAll: boolean = false
  muted: boolean = false
  speakerEnabled: boolean = false
  speakerActionLabel: string = '免提'
  speakerActionIsMicSwitch: boolean = false
  speakerActionEnabled: boolean = true
  speakerActionVisible: boolean = true
  deviceRole: RtcCallDeviceRole | string = RtcCallDeviceRole.HOST
  volume: number = 0
  videoState: RtcHostVideoState = new RtcHostVideoState()
  message: string = ''
}

export type RtcHostCallUiModelListener = (model: RtcHostCallUiModel) => void
