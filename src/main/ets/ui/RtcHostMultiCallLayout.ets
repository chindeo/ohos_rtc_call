import {
  RtcHostCallUiItem,
  RtcHostCallUiModel
} from '../model/RtcHostCallUiModel'
import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallViewPhase } from '../model/RtcCallViewState'

@Component
export struct RtcHostMultiCallLayout {
  @Prop model: RtcHostCallUiModel = new RtcHostCallUiModel()
  @BuilderParam localVideoBuilder?: () => void
  @BuilderParam remoteVideoBuilder?: () => void

  onAccept?: (sessionKey: string) => void
  onHangup?: (sessionKey: string) => void
  onHangupAll?: () => void
  onHold?: (sessionKey: string) => void
  onResume?: (sessionKey: string) => void
  onSelect?: (sessionKey: string) => void
  onMute?: () => void
  onSpeaker?: () => void

  private getPeerName(call?: RtcHostCallUiItem): string {
    return call?.displayName || call?.peerNumber || '通话'
  }

  private getPeerInitial(call?: RtcHostCallUiItem): string {
    const name = this.getPeerName(call)
    return name ? name.substring(0, 1) : '通'
  }

  private getStatusColor(call?: RtcHostCallUiItem): string {
    if (!call) {
      return '#6F7D89'
    }
    if (call.phase === RtcCallViewPhase.INCOMING || call.phase === RtcCallViewPhase.OUTGOING) {
      return '#D6A23D'
    }
    if (call.phase === RtcCallViewPhase.HELD) {
      return '#4F83C2'
    }
    if (call.phase === RtcCallViewPhase.CONNECTED) {
      return '#35A36F'
    }
    if (call.phase === RtcCallViewPhase.ERROR) {
      return '#D65C5C'
    }
    return '#6F7D89'
  }

  private getCardBackground(_call?: RtcHostCallUiItem): string {
    return '#19232C'
  }

  @Builder
  private Avatar(call: RtcHostCallUiItem | undefined, size: string, fontSize: string) {
    Stack() {
      Text(this.getPeerInitial(call))
        .fontSize(fontSize)
        .fontColor('#EAF1F7')
        .fontWeight(FontWeight.Bold)
    }
    .width(size)
    .height(size)
    .borderRadius(size)
    .backgroundColor(this.getStatusColor(call))
  }

  @Builder
  private ControlButton(
    icon: Resource,
    label: string,
    background: string,
    enabled: boolean,
    action: () => void
  ) {
    Column({ space: '8lpx' }) {
      Stack() {
        Image(icon)
          .width('40lpx')
          .height('40lpx')
          .objectFit(ImageFit.Contain)
      }
      .width('72lpx')
      .height('72lpx')
      .borderRadius('36lpx')
      .backgroundColor(background)

      Text(label)
        .fontSize('22lpx')
        .fontColor('#FFFFFF')
        .maxLines(1)
    }
    .width('106lpx')
    .opacity(enabled ? 1 : 0.36)
    .onClick(() => {
      if (enabled) {
        action()
      }
    })
  }

  @Builder
  private ActiveMedia(call: RtcHostCallUiItem) {
    Stack({ alignContent: Alignment.Center }) {
      if (call.mode === RtcCallMode.VIDEO && call.hasRemoteVideo && this.remoteVideoBuilder) {
        this.remoteVideoBuilder()
      } else {
        Column({ space: '22lpx' }) {
          this.Avatar(call, '176lpx', '62lpx')
          Text(this.getPeerName(call))
            .fontSize('46lpx')
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(call.statusText)
            .fontSize('28lpx')
            .fontColor('#D4DEE7')
            .maxLines(1)
          if (call.mode === RtcCallMode.VIDEO && !call.hasRemoteVideo) {
            Text('等待远端视频')
              .fontSize('22lpx')
              .fontColor('#91A4B5')
          }
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#111820')
  }

  @Builder
  private ActiveActions(call: RtcHostCallUiItem) {
    Row({ space: '22lpx' }) {
      if (call.phase === RtcCallViewPhase.INCOMING) {
        this.ControlButton($r('app.media.rtc_call_accept'), '接听', '#278A5B', call.canAccept, () => {
          this.onAccept?.(call.sessionKey)
        })
      }
      if (call.canHold) {
        this.ControlButton($r('app.media.rtc_call_hold'), '保持', '#426E9C', true, () => {
          this.onHold?.(call.sessionKey)
        })
      }
      if (call.canResume) {
        this.ControlButton($r('app.media.rtc_call_resume'), '恢复', '#426E9C', true, () => {
          this.onResume?.(call.sessionKey)
        })
      }
      if (call.phase !== RtcCallViewPhase.INCOMING) {
        this.ControlButton(
          this.model.muted ? $r('app.media.rtc_call_mute') : $r('app.media.rtc_call_microphone'),
          this.model.muted ? '已静音' : '静音',
          this.model.muted ? '#536170' : '#33414F', true, () => {
            this.onMute?.()
          })
      }
      this.ControlButton($r('app.media.rtc_call_hangup'), '挂断', '#C74747', call.canHangup, () => {
        this.onHangup?.(call.sessionKey)
      })
      if (call.phase !== RtcCallViewPhase.INCOMING) {
        this.ControlButton(
          this.model.speakerEnabled ?
            $r('app.media.rtc_call_speaker_pressed') :
            $r('app.media.rtc_call_speaker'),
          '免提',
          this.model.speakerEnabled ? '#3B78A0' : '#33414F', true, () => {
            this.onSpeaker?.()
          })
      }
      if (this.model.showHangupAll) {
        this.ControlButton($r('app.media.rtc_call_hangup_all'), '挂断全部', '#9E353B', true, () => {
          this.onHangupAll?.()
        })
      }
    }
    .width('100%')
    .height('142lpx')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#151D25')
  }

  @Builder
  private LocalCard() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.model.localCard.hasVideo && this.model.localCard.videoReady && this.localVideoBuilder) {
          this.localVideoBuilder()
        } else {
          Column({ space: '14lpx' }) {
            Stack() {
              Text((this.model.localCard.displayName || this.model.localCard.number || '本').substring(0, 1))
                .fontSize('34lpx')
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
            }
            .width('88lpx')
            .height('88lpx')
            .borderRadius('44lpx')
            .backgroundColor('#3D4C58')

            Text(this.model.localCard.hasVideo ? '本机视频准备中' : '本机')
              .fontSize('20lpx')
              .fontColor('#95A7B7')
          }
        }

        Column() {
          Blank()
          Text(this.model.localCard.displayName || this.model.localCard.number || '本机')
            .width('100%')
            .fontSize('25lpx')
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: '18lpx', right: '18lpx', top: '10lpx', bottom: '10lpx' })
            .backgroundColor('#88000000')
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('236lpx')
      .backgroundColor('#151D25')
    }
    .width('100%')
  }

  @Builder
  private SideCallCard(call: RtcHostCallUiItem) {
    Row({ space: '16lpx' }) {
      Row({ space: '16lpx' }) {
        Row()
          .width('5lpx')
          .height('72lpx')
          .borderRadius('3lpx')
          .backgroundColor(this.getStatusColor(call))

        this.Avatar(call, '66lpx', '26lpx')

        Column({ space: '8lpx' }) {
          Text(this.getPeerName(call))
            .fontSize('25lpx')
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: '8lpx' }) {
            Text()
              .width('10lpx')
              .height('10lpx')
              .borderRadius('5lpx')
              .backgroundColor(this.getStatusColor(call))
            Text(call.statusText)
              .fontSize('20lpx')
              .fontColor('#C5D0D9')
              .maxLines(1)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onSelect?.(call.sessionKey)
      })

      Stack() {
        Image($r('app.media.rtc_call_hangup'))
          .width('25lpx')
          .height('25lpx')
          .objectFit(ImageFit.Contain)
      }
        .width('46lpx')
        .height('46lpx')
        .backgroundColor('#C84141')
        .borderRadius('23lpx')
        .onClick(() => {
          this.onHangup?.(call.sessionKey)
        })
    }
    .width('100%')
    .height('104lpx')
    .padding({ left: '18lpx', right: '16lpx' })
    .backgroundColor(this.getCardBackground(call))
    .border({
      width: call.isSelected ? '3lpx' : '1lpx',
      color: call.isSelected ? '#78B9E6' : '#303D47'
    })
    .borderRadius('6lpx')
  }

  build() {
    if (this.model.visible && this.model.activeCall) {
      Row() {
        Column() {
          Row() {
            Text(this.model.localCard.displayName || this.model.localCard.number || '护士站')
              .fontSize('28lpx')
              .fontColor('#E7EFF5')
              .maxLines(1)
              .padding({ left: '24lpx', right: '24lpx', top: '14lpx', bottom: '14lpx' })
          }
          .width('100%')
          .height('62lpx')
          .backgroundColor('#151D25')

          this.ActiveMedia(this.model.activeCall)
          this.ActiveActions(this.model.activeCall)

          if (this.model.volume > 0) {
            Row() {
              Text('通话音量 ' + this.model.volume + '%')
                .fontSize('18lpx')
                .fontColor('#87D9A2')
            }
            .width('100%')
            .height('30lpx')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#151D25')
          }
        }
        .width('72%')
        .height('100%')

        Column() {
          this.LocalCard()

          Row()
            .width('100%')
            .height('14lpx')
            .backgroundColor('#27343E')

          List({ space: '10lpx' }) {
            ForEach(this.model.sideCalls, (call: RtcHostCallUiItem) => {
              ListItem() {
                this.SideCallCard(call)
              }
            }, (call: RtcHostCallUiItem) => call.sessionKey)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: '12lpx', right: '12lpx', top: '12lpx', bottom: '12lpx' })
          .backgroundColor('#111820')
        }
        .width('28%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#111820')
    }
  }
}
