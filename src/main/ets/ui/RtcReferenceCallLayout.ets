import {
  RtcHostCallUiItem,
  RtcHostCallUiModel
} from '../model/RtcHostCallUiModel'
import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallDirection, RtcCallViewPhase } from '../model/RtcCallViewState'

@Component
export struct RtcReferenceCallLayout {
  @Prop model: RtcHostCallUiModel = new RtcHostCallUiModel()
  @BuilderParam localVideoBuilder?: () => void
  @BuilderParam remoteVideoBuilder?: () => void
  @BuilderParam sessionRemoteVideoBuilder?: (sessionKey: string) => void

  onAccept?: (sessionKey: string) => void
  onHangup?: (sessionKey: string) => void
  onHangupAll?: () => void
  onHold?: (sessionKey: string) => void
  onResume?: (sessionKey: string) => void
  onSelect?: (sessionKey: string) => void
  onMute?: () => void
  onSpeaker?: () => void

  @State private areaWidth: number = 0
  @State private areaHeight: number = 0
  @State private nowMs: number = Date.now()
  private timerId: number = -1
  private lastModelLogKey: string = ''
  private lastBackgroundBranchKey: string = ''
  private lastCallCenterBranchKey: string = ''
  private lastActiveMediaBranchKey: string = ''
  private lastControlBranchKey: string = ''
  private lastCallingControlsBranchKey: string = ''
  private lastOverlayBranchKey: string = ''
  private lastRootAreaLogKey: string = ''
  private lastMediaAreaLogKey: string = ''
  private lastControlAreaLogKey: string = ''
  private lastAudioAreaLogKey: string = ''
  private lastControlsAreaLogKey: string = ''
  private lastSideActionAreaLogKey: string = ''
  private lastSideActionRowAreaLogKey: string = ''
  private lastSideSwitchAreaLogKey: string = ''
  private lastSideCardLogKey: string = ''

  aboutToAppear(): void {
    console.info('RtcReferenceCallLayout rtc_layout_appear')
    this.timerId = setInterval(() => {
      this.nowMs = Date.now()
    }, 1000)
  }

  aboutToDisappear(): void {
    console.info('RtcReferenceCallLayout rtc_layout_disappear')
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private isLandscape(): boolean {
    return this.areaWidth <= 0 || this.areaWidth >= this.areaHeight
  }

  private getAllCalls(): RtcHostCallUiItem[] {
    const calls: RtcHostCallUiItem[] = []
    if (this.model.activeCall) {
      calls.push(this.model.activeCall)
    }
    const sideCalls = this.model.sideCalls || []
    sideCalls.forEach((call: RtcHostCallUiItem) => {
      if (call) {
        calls.push(call)
      }
    })
    return calls
  }

  private getSideCalls(): RtcHostCallUiItem[] {
    return this.model.sideCalls || []
  }

  private hasEstablishedCall(): boolean {
    return this.getAllCalls().some((call: RtcHostCallUiItem) =>
      call.phase === RtcCallViewPhase.CONNECTED || call.phase === RtcCallViewPhase.HELD)
  }

  private shouldShowOverlay(): boolean {
    const call = this.model.activeCall
    if (!call || this.hasEstablishedCall()) {
      return false
    }
    return call.phase === RtcCallViewPhase.INCOMING ||
      call.phase === RtcCallViewPhase.OUTGOING
  }

  private getPeerName(call?: RtcHostCallUiItem): string {
    return call?.displayName || call?.peerNumber || '通话'
  }

  private getInviteText(call: RtcHostCallUiItem): string {
    if (call.phase === RtcCallViewPhase.CONNECTING) {
      return '正在连接'
    }
    if (call.direction === RtcCallDirection.OUTGOING ||
      call.phase === RtcCallViewPhase.OUTGOING) {
      return '正在等待对方接受邀请..'
    }
    return call.mode === RtcCallMode.VIDEO ? '邀请你视频通话' : '邀请你语音通话'
  }

  private getDurationText(call: RtcHostCallUiItem): string {
    if (!call.connectedAt) {
      return call.durationText || '00:00'
    }
    const elapsedSeconds = Math.max(0, Math.floor((this.nowMs - call.connectedAt) / 1000))
    const hours = Math.floor(elapsedSeconds / 3600)
    const minutes = Math.floor((elapsedSeconds % 3600) / 60)
    const seconds = elapsedSeconds % 60
    const minuteText = minutes < 10 ? '0' + minutes : '' + minutes
    const secondText = seconds < 10 ? '0' + seconds : '' + seconds
    return hours > 0 ? hours + ':' + minuteText + ':' + secondText : minuteText + ':' + secondText
  }

  private showRemoteVideo(call: RtcHostCallUiItem): boolean {
    return call.phase !== RtcCallViewPhase.HELD &&
      call.mode === RtcCallMode.VIDEO &&
      call.hasRemoteVideo
  }

  private getSpeakerActionLabel(): string {
    return (this.model.speakerActionLabel || '').trim() || '免提'
  }

  private shouldRenderCallLayout(): boolean {
    const call = this.model.activeCall
    if (!this.model.visible || !call) {
      return false
    }
    const allCount = this.getAllCalls().length
    const sideCount = this.getSideCalls().length
    const shouldOverlay = this.shouldShowOverlay()
    const key = 'phase=' + call.phase +
      '|activeHash=' + this.getSessionHash(call.sessionKey) +
      '|mode=' + call.mode +
      '|canHangup=' + (call.canHangup === true) +
      '|canHold=' + (call.canHold === true) +
      '|mediaConnected=' + (call.mediaConnected === true) +
      '|shouldOverlay=' + shouldOverlay +
      '|allCount=' + allCount +
      '|sideCount=' + sideCount +
      this.getSideDebugSummary() +
      '|showHangupAll=' + this.model.showHangupAll +
      '|muted=' + this.model.muted +
      '|speakerEnabled=' + this.model.speakerEnabled
    if (this.lastModelLogKey !== key) {
      this.lastModelLogKey = key
      console.info('RtcReferenceCallLayout rtc_layout_model ' + key)
    }
    return true
  }

  private getRenderKey(call: RtcHostCallUiItem): string {
    return call.sessionKey +
      '|phase=' + call.phase +
      '|mode=' + call.mode +
      '|overlay=' + this.shouldShowOverlay() +
      '|sideCount=' + this.getSideCalls().length
  }

  private getControlsRenderKey(call: RtcHostCallUiItem): string {
    return call.sessionKey +
      '|phase=' + call.phase +
      '|canHangup=' + (call.canHangup === true) +
      '|canHold=' + (call.canHold === true) +
      '|canResume=' + (call.canResume === true) +
      '|showHangupAll=' + (this.model.showHangupAll === true) +
      '|muted=' + (this.model.muted === true) +
      '|speakerEnabled=' + (this.model.speakerEnabled === true) +
      '|speakerLabel=' + this.getSpeakerActionLabel()
  }

  private getSideCardRenderKey(call: RtcHostCallUiItem): string {
    return call.sessionKey +
      '|phase=' + call.phase +
      '|canAccept=' + (call.canAccept === true) +
      '|canHangup=' + (call.canHangup === true) +
      '|canHold=' + (call.canHold === true) +
      '|canResume=' + (call.canResume === true) +
      '|isHold=' + (call.isHold === true) +
      '|mediaConnected=' + (call.mediaConnected === true)
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

  private getSideDebugSummary(): string {
    const calls = this.getSideCalls()
    const hashes: string[] = []
    const phases: string[] = []
    const accepts: string[] = []
    const hangups: string[] = []
    const holds: string[] = []
    const resumes: string[] = []
    calls.forEach((call: RtcHostCallUiItem) => {
      hashes.push(this.getSessionHash(call.sessionKey))
      phases.push(call.phase)
      accepts.push(call.canAccept ? '1' : '0')
      hangups.push(call.canHangup ? '1' : '0')
      holds.push(call.canHold ? '1' : '0')
      resumes.push(call.canResume ? '1' : '0')
    })
    return '|sideHashes=' + hashes.join(',') +
      '|sidePhases=' + phases.join(',') +
      '|sideCanAccept=' + accepts.join(',') +
      '|sideCanHangup=' + hangups.join(',') +
      '|sideCanHold=' + holds.join(',') +
      '|sideCanResume=' + resumes.join(',')
  }

  private logSideCard(call: RtcHostCallUiItem): boolean {
    const key = 'sidHash=' + this.getSessionHash(call.sessionKey) +
      '|phase=' + call.phase +
      '|canAccept=' + (call.canAccept === true) +
      '|canHangup=' + (call.canHangup === true) +
      '|canHold=' + (call.canHold === true) +
      '|canResume=' + (call.canResume === true)
    if (this.lastSideCardLogKey === key) {
      return true
    }
    this.lastSideCardLogKey = key
    console.info('RtcReferenceCallLayout side_card ' + key)
    return true
  }

  private logSideAction(actionName: string, call: RtcHostCallUiItem, enabled: boolean): void {
    console.info('RtcReferenceCallLayout side_action action=' + actionName +
      ' sidHash=' + this.getSessionHash(call.sessionKey) +
      ' phase=' + call.phase +
      ' enabled=' + enabled)
  }

  private logSideSwitch(call: RtcHostCallUiItem): void {
    console.info('RtcReferenceCallLayout side_switch sidHash=' + this.getSessionHash(call.sessionKey) +
      ' phase=' + call.phase)
  }

  private getTouchTypeText(event: TouchEvent): string {
    return '' + event.type
  }

  private getTouchX(event: TouchEvent): number {
    if (event.touches && event.touches.length > 0) {
      return Number(event.touches[0].x)
    }
    return 0
  }

  private getTouchY(event: TouchEvent): number {
    if (event.touches && event.touches.length > 0) {
      return Number(event.touches[0].y)
    }
    return 0
  }

  private logTouch(name: string, event: TouchEvent, call?: RtcHostCallUiItem, actionName?: string,
    enabled?: boolean): void {
    let message = 'RtcReferenceCallLayout ' + name +
      ' type=' + this.getTouchTypeText(event) +
      ' x=' + this.getTouchX(event) +
      ' y=' + this.getTouchY(event)
    if (call) {
      message += ' sidHash=' + this.getSessionHash(call.sessionKey) +
        ' phase=' + call.phase
    }
    if (actionName) {
      message += ' action=' + actionName
    }
    if (enabled !== undefined) {
      message += ' enabled=' + enabled
    }
    console.info(message)
  }

  private logBranch(name: string, call?: RtcHostCallUiItem): boolean {
    const key = name +
      '|phase=' + (call?.phase || '') +
      '|mode=' + (call?.mode || '') +
      '|allCount=' + this.getAllCalls().length +
      '|sideCount=' + this.getSideCalls().length
    switch (name) {
      case 'background':
        if (this.lastBackgroundBranchKey === key) {
          return true
        }
        this.lastBackgroundBranchKey = key
        break
      case 'call_center':
        if (this.lastCallCenterBranchKey === key) {
          return true
        }
        this.lastCallCenterBranchKey = key
        break
      case 'media':
        if (this.lastActiveMediaBranchKey === key) {
          return true
        }
        this.lastActiveMediaBranchKey = key
        break
      case 'control':
        if (this.lastControlBranchKey === key) {
          return true
        }
        this.lastControlBranchKey = key
        break
      case 'calling_controls':
        if (this.lastCallingControlsBranchKey === key) {
          return true
        }
        this.lastCallingControlsBranchKey = key
        break
      case 'overlay':
        if (this.lastOverlayBranchKey === key) {
          return true
        }
        this.lastOverlayBranchKey = key
        break
      default:
        break
    }
    console.info('RtcReferenceCallLayout rtc_layout_branch_' + name + ' ' + key)
    return true
  }

  private logArea(name: string, width: number, height: number): void {
    const key = name + '|width=' + width + '|height=' + height
    switch (name) {
      case 'root':
        if (this.lastRootAreaLogKey === key) {
          return
        }
        this.lastRootAreaLogKey = key
        break
      case 'media':
        if (this.lastMediaAreaLogKey === key) {
          return
        }
        this.lastMediaAreaLogKey = key
        break
      case 'control':
        if (this.lastControlAreaLogKey === key) {
          return
        }
        this.lastControlAreaLogKey = key
        break
      case 'audio':
        if (this.lastAudioAreaLogKey === key) {
          return
        }
        this.lastAudioAreaLogKey = key
        break
      case 'calling_controls':
        if (this.lastControlsAreaLogKey === key) {
          return
        }
        this.lastControlsAreaLogKey = key
        break
      case 'side_action':
        if (this.lastSideActionAreaLogKey === key) {
          return
        }
        this.lastSideActionAreaLogKey = key
        break
      case 'side_action_row':
        if (this.lastSideActionRowAreaLogKey === key) {
          return
        }
        this.lastSideActionRowAreaLogKey = key
        break
      case 'side_switch':
        if (this.lastSideSwitchAreaLogKey === key) {
          return
        }
        this.lastSideSwitchAreaLogKey = key
        break
      default:
        break
    }
    console.info('RtcReferenceCallLayout rtc_layout_area_' + name + ' width=' + width + ' height=' + height)
  }

  @Builder
  private BackgroundLayer() {
    if (this.logBranch('background')) {
      Image($r('app.media.rtc_call_background'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
  }

  @Builder
  private Avatar(call: RtcHostCallUiItem, size: string) {
    Image(call.phase === RtcCallViewPhase.HELD ?
      $r('app.media.rtc_call_hold_avatar') :
      $r('app.media.rtc_call_avatar'))
      .width(size)
      .height(size)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  private NameTag(call: RtcHostCallUiItem, fontSize: string) {
    Text(this.getPeerName(call) + (call.phase === RtcCallViewPhase.HELD ? ' - 保持中' : ''))
      .fontSize(fontSize)
      .fontColor('#FFFFFFFF')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: '25vp', right: '25vp', top: '10vp', bottom: '10vp' })
      .backgroundColor('#B3333333')
      .borderRadius({ bottomRight: '20vp' })
  }

  @Builder
  private AudioPlaceholder(call: RtcHostCallUiItem, compact: boolean) {
    Column({ space: compact ? '8vp' : '10vp' }) {
      this.Avatar(call, compact ? '76vp' : '150vp')
      Text(this.getPeerName(call))
        .fontSize(compact ? '22fp' : '30fp')
        .fontColor('#FFFFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ActiveMedia(call: RtcHostCallUiItem) {
    if (this.logBranch('media', call) && call.mode === RtcCallMode.AUDIO) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: '10vp' }) {
          this.Avatar(call, '150vp')
          Text(this.getPeerName(call))
            .fontSize('30fp')
            .fontColor('#FFFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.logArea('audio', Number(newArea.width), Number(newArea.height))
        })
      }
      .width('100%')
      .height('100%')
    } else if (this.logBranch('media', call)) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.rtc_call_video_background'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)

        if (this.showRemoteVideo(call) && this.remoteVideoBuilder) {
          this.remoteVideoBuilder()
        } else {
          this.AudioPlaceholder(call, false)
        }

        Column() {
          this.NameTag(call, '20fp')
          Blank()
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private LocalCard() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.rtc_call_video_background'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      if (this.model.localCard.hasVideo && this.model.localCard.videoReady && this.localVideoBuilder) {
        this.localVideoBuilder()
      } else {
        Image($r('app.media.rtc_call_avatar'))
          .width('82vp')
          .height('82vp')
          .objectFit(ImageFit.Contain)
      }

      Column() {
        Blank()
        Text((this.model.localCard.displayName || this.model.localCard.number || '自己') + ' -- 自己')
          .width('100%')
          .fontSize('20fp')
          .fontColor('#FFFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: '25vp', right: '25vp', top: '8vp', bottom: '8vp' })
          .backgroundColor('#B3333333')
          .borderRadius({ topRight: '20vp' })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('300vp')
    .border({ width: '3vp', color: '#7E7F80' })
    .borderRadius('3vp')
  }

  @Builder
  private SideAction(
    icon: Resource,
    enabled: boolean,
    actionName: string,
    call: RtcHostCallUiItem,
    action: () => void
  ) {
    Stack({ alignContent: Alignment.Center }) {
      Image(icon)
        .width('70vp')
        .height('70vp')
        .objectFit(ImageFit.Contain)
    }
      .width('92vp')
      .height('92vp')
      .opacity(enabled ? 1 : 0.35)
      .zIndex(3)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.logArea('side_action', Number(newArea.width), Number(newArea.height))
      })
      .onTouch((event: TouchEvent) => {
        this.logTouch('touch_side_action', event, call, actionName, enabled)
      })
      .onClick(() => {
        console.info('RtcReferenceCallLayout side_action_click action=' + actionName +
          ' sidHash=' + this.getSessionHash(call.sessionKey) +
          ' enabled=' + enabled)
        this.logSideAction(actionName, call, enabled)
        if (enabled) {
          action()
        }
      })
  }

  @Builder
  private SideSwitchButton(call: RtcHostCallUiItem) {
    Stack({ alignContent: Alignment.Center }) {
      Text('⇄')
        .fontSize('28fp')
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFFFF')
    }
      .width('56vp')
      .height('56vp')
      .backgroundColor('#66000000')
      .borderRadius('28vp')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.logArea('side_switch', Number(newArea.width), Number(newArea.height))
      })
      .onTouch((event: TouchEvent) => {
        this.logTouch('touch_side_switch', event, call)
      })
      .onClick(() => {
        console.info('RtcReferenceCallLayout side_switch_click sidHash=' + this.getSessionHash(call.sessionKey))
        this.logSideSwitch(call)
        this.onSelect?.(call.sessionKey)
      })
  }

  @Builder
  private SideCallCard(call: RtcHostCallUiItem) {
    if (this.logSideCard(call)) {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.rtc_call_video_background'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)

          if (this.showRemoteVideo(call) && this.sessionRemoteVideoBuilder) {
            this.sessionRemoteVideoBuilder(call.sessionKey)
          } else {
            this.AudioPlaceholder(call, true)
          }

          Column() {
            Row() {
              Blank()
              this.SideSwitchButton(call)
            }
            .width('100%')
            .height('72vp')
            .padding({ top: '8vp', right: '8vp' })

            Blank()

            Row() {
              Text(this.getPeerName(call))
                .fontSize('28fp')
                .fontColor('#FFFFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: '25vp', right: '25vp', top: '8vp', bottom: '8vp' })
                .backgroundColor('#B3333333')
                .borderRadius({ topRight: '20vp' })
              Blank()
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .onTouch((event: TouchEvent) => {
            this.logTouch('touch_side_card', event, call)
          })
        }
        .width('100%')
        .height('208vp')

        Row({ space: '18vp' }) {
          if (call.phase === RtcCallViewPhase.INCOMING) {
            this.SideAction($r('app.media.rtc_call_accept'), call.canAccept, 'accept', call, () => {
              this.onAccept?.(call.sessionKey)
            })
          } else if (call.canHold) {
            this.SideAction($r('app.media.rtc_call_hold'), true, 'hold', call, () => {
              this.onHold?.(call.sessionKey)
            })
          } else if (call.canResume) {
            this.SideAction($r('app.media.rtc_call_resume'), true, 'resume', call, () => {
              this.onResume?.(call.sessionKey)
            })
          }

          this.SideAction($r('app.media.rtc_call_hangup'), call.canHangup, 'hangup', call, () => {
            this.onHangup?.(call.sessionKey)
          })
        }
        .width('100%')
        .height('92vp')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#66000000')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.logArea('side_action_row', Number(newArea.width), Number(newArea.height))
        })
        .onTouch((event: TouchEvent) => {
          this.logTouch('touch_side_action_row', event, call)
        })
      }
      .width('100%')
      .height('300vp')
      .margin('2vp')
      .border({
        width: '3vp',
        color: call.isSelected ? '#69F46E' : '#7E7F80'
      })
      .borderRadius('3vp')
      .onTouch((event: TouchEvent) => {
        this.logTouch('touch_side_card', event, call)
      })
    }
  }

  @Builder
  private MultiMediaLayer(call: RtcHostCallUiItem) {
    Row() {
      Stack() {
        this.ActiveMedia(call)
      }
      .width('75%')
      .height('100%')

      Column() {
        this.LocalCard()
        List({ space: '0vp' }) {
          ForEach(this.getSideCalls(), (sideCall: RtcHostCallUiItem) => {
            ListItem() {
              this.SideCallCard(sideCall)
            }
          }, (sideCall: RtcHostCallUiItem) => this.getSideCardRenderKey(sideCall))
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('25%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private CallCenterLayer(call: RtcHostCallUiItem) {
    if (this.logBranch('call_center', call)) {
      if (this.getAllCalls().length > 1) {
        this.MultiMediaLayer(call)
      } else {
        this.ActiveMedia(call)
      }
    }
  }

  @Builder
  private ControlButton(
    icon: Resource,
    label: string,
    enabled: boolean,
    action: () => void
  ) {
    Column({ space: '15vp' }) {
      Image(icon)
        .width('88vp')
        .height('88vp')
        .objectFit(ImageFit.Contain)
      Text(label)
        .fontSize('22fp')
        .fontColor('#FFFFFFFF')
        .maxLines(1)
    }
    .opacity(enabled ? 1 : 0.35)
    .onClick(() => {
      if (enabled) {
        action()
      }
    })
  }

  @Builder
  private CallingControls(call: RtcHostCallUiItem) {
    if (this.logBranch('calling_controls', call)) {
      ForEach([this.getControlsRenderKey(call)], (_controlKey: string) => {
        Row({ space: this.getAllCalls().length > 1 ? '22vp' : '30vp' }) {
          Text(this.getDurationText(call))
            .fontSize('30fp')
            .fontColor('#FFFFFFFF')

          this.ControlButton(
            this.model.muted ? $r('app.media.rtc_call_mute') : $r('app.media.rtc_call_microphone'),
            '静音',
            true,
            () => this.onMute?.()
          )

          if (call.canHold) {
            this.ControlButton($r('app.media.rtc_call_hold'), '保持', true, () => {
              this.onHold?.(call.sessionKey)
            })
          } else if (call.canResume) {
            this.ControlButton($r('app.media.rtc_call_resume'), '恢复', true, () => {
              this.onResume?.(call.sessionKey)
            })
          }

          this.ControlButton($r('app.media.rtc_call_hangup'), '挂断', call.canHangup, () => {
            this.onHangup?.(call.sessionKey)
          })

          if (this.model.showHangupAll) {
            this.ControlButton($r('app.media.rtc_call_hangup_all'), '挂断全部', true, () => {
              this.onHangupAll?.()
            })
          }

          this.ControlButton(
            this.model.speakerEnabled ?
              $r('app.media.rtc_call_speaker_pressed') :
              $r('app.media.rtc_call_speaker'),
            this.getSpeakerActionLabel(),
            true,
            () => this.onSpeaker?.()
          )
        }
        .padding({ left: '50vp', right: '50vp', top: '40vp', bottom: '40vp' })
        .backgroundColor('#B3333333')
        .borderRadius('40vp')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.logArea('calling_controls', Number(newArea.width), Number(newArea.height))
        })
      }, (controlKey: string) => controlKey)
    }
  }

  @Builder
  private ControlLayer(call: RtcHostCallUiItem) {
    if (this.logBranch('control', call)) {
      Stack({ alignContent: Alignment.Bottom }) {
      if (call.phase === RtcCallViewPhase.CONNECTING ||
        call.phase === RtcCallViewPhase.CONNECTED ||
        call.phase === RtcCallViewPhase.HELD) {
        Column() {
          this.CallingControls(call)
        }
        .margin({ bottom: '20vp' })
      } else if (this.getAllCalls().length > 1) {
        Row({ space: '30vp' }) {
          this.ControlButton(
            $r('app.media.rtc_call_hangup'),
            call.direction === RtcCallDirection.INCOMING ? '拒接' : '挂断',
            call.canHangup,
            () => this.onHangup?.(call.sessionKey)
          )
          if (call.phase === RtcCallViewPhase.INCOMING) {
            this.ControlButton(
              $r('app.media.rtc_call_accept'),
              '接听',
              call.canAccept,
              () => this.onAccept?.(call.sessionKey)
            )
          }
        }
        .padding({ left: '50vp', right: '50vp', top: '40vp', bottom: '40vp' })
        .backgroundColor('#B3333333')
        .borderRadius('40vp')
        .margin({ bottom: '20vp' })
      }
    }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.logArea('control', Number(newArea.width), Number(newArea.height))
      })
    }
  }

  @Builder
  private IncomingActionButton(
    icon: Resource,
    label: string,
    enabled: boolean,
    action: () => void
  ) {
    Column({ space: '15vp' }) {
      Image(icon)
        .width('120vp')
        .height('120vp')
        .objectFit(ImageFit.Contain)
      Text(label)
        .fontSize('22fp')
        .fontColor('#FFFFFFFF')
    }
    .opacity(enabled ? 1 : 0.35)
    .onClick(() => {
      if (enabled) {
        action()
      }
    })
  }

  @Builder
  private SingleCallOverlay(call: RtcHostCallUiItem) {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.rtc_call_background'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      Column({ space: '30vp' }) {
        Image($r('app.media.rtc_call_avatar'))
          .width('150vp')
          .height('150vp')
          .objectFit(ImageFit.Contain)
        Text(this.getPeerName(call))
          .fontSize(call.direction === RtcCallDirection.INCOMING && this.isLandscape() ? '100fp' : '46fp')
          .fontColor('#FFFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getInviteText(call))
          .fontSize('20fp')
          .fontColor('#FFFFFFFF')
      }
      .alignItems(HorizontalAlign.Center)

      Column() {
        Blank()
        Row({ space: '100vp' }) {
          this.IncomingActionButton(
            $r('app.media.rtc_call_hangup'),
            call.direction === RtcCallDirection.INCOMING ? '拒接' : '挂断',
            call.canHangup,
            () => this.onHangup?.(call.sessionKey)
          )
          if (call.phase === RtcCallViewPhase.INCOMING) {
            this.IncomingActionButton(
              $r('app.media.rtc_call_accept'),
              '接听',
              call.canAccept,
              () => this.onAccept?.(call.sessionKey)
            )
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: '100vp' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private MultiIncomingCard(call: RtcHostCallUiItem, fullWidth: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.rtc_call_background'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      Column({ space: '10vp' }) {
        Text(this.getPeerName(call))
          .width('100%')
          .fontSize('38fp')
          .fontColor('#FFFFFFFF')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getInviteText(call))
          .width('100%')
          .fontSize('24fp')
          .fontColor('#FFFFFFFF')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .position({ x: 0, y: '18%' })

      Column() {
        Blank()
        Row({ space: '50vp' }) {
          this.SideAction($r('app.media.rtc_call_hangup'), call.canHangup, 'hangup', call, () => {
            this.onHangup?.(call.sessionKey)
          })
          if (call.phase === RtcCallViewPhase.INCOMING) {
            this.SideAction($r('app.media.rtc_call_accept'), call.canAccept, 'accept', call, () => {
              this.onAccept?.(call.sessionKey)
            })
          }
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: '54vp' })
    }
    .width(fullWidth ? '100%' : '50%')
    .height(this.getAllCalls().length <= 2 ? '100%' : '50%')
    .padding('5vp')
    .border({ width: '3vp', color: call.isSelected ? '#69F46E' : '#7E7F80' })
    .borderRadius('3vp')
  }

  @Builder
  private MultiCallOverlay() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap, alignContent: FlexAlign.Start }) {
        ForEach(this.getAllCalls(), (call: RtcHostCallUiItem, index: number) => {
          this.MultiIncomingCard(
            call,
            this.getAllCalls().length % 2 === 1 && index === this.getAllCalls().length - 1
          )
        }, (call: RtcHostCallUiItem) => call.sessionKey)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF212226')
  }

  @Builder
  private OverlayLayer(call: RtcHostCallUiItem) {
    if (this.logBranch('overlay', call)) {
      if (this.getAllCalls().length > 1) {
        this.MultiCallOverlay()
      } else {
        this.SingleCallOverlay(call)
      }
    }
  }

  build() {
    if (this.shouldRenderCallLayout()) {
      Stack() {
        Stack() {
          this.BackgroundLayer()
        }
        .width('100%')
        .height('100%')
        .zIndex(0)

        ForEach([this.getRenderKey(this.model.activeCall)], (_renderKey: string) => {
          Stack() {
            Stack() {
              this.CallCenterLayer(this.model.activeCall)
            }
            .width('100%')
            .height('100%')
            .zIndex(1)
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.logArea('media', Number(newArea.width), Number(newArea.height))
            })
            .onTouch((event: TouchEvent) => {
              this.logTouch('touch_call_center', event)
            })

            Stack() {
              this.ControlLayer(this.model.activeCall)
            }
            .width(this.getAllCalls().length > 1 ? '75%' : '100%')
            .height('100%')
            .position({ x: 0, y: 0 })
            .zIndex(2)
            .onTouch((event: TouchEvent) => {
              this.logTouch('touch_control_wrapper', event)
            })

            if (this.shouldShowOverlay()) {
              Stack() {
                this.OverlayLayer(this.model.activeCall)
              }
              .width('100%')
              .height('100%')
              .zIndex(3)
            }
          }
          .width('100%')
          .height('100%')
        }, (renderKey: string) => renderKey)
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.areaWidth = Number(newArea.width)
        this.areaHeight = Number(newArea.height)
        this.logArea('root', this.areaWidth, this.areaHeight)
      })
      .onTouch((event: TouchEvent) => {
        this.logTouch('touch_root', event)
      })
    } else {
      Blank()
        .width(0)
        .height(0)
    }
  }
}
