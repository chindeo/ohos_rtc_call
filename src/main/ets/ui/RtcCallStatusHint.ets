import { RtcCallStatusLevel } from '../model/RtcCallStatusMessage'

@Component
export struct RtcCallStatusHint {
  @StorageLink('rtcCallStatusMessage') @Watch('onStatusChanged') message: string = ''
  @StorageLink('rtcCallStatusLevel') level: string = RtcCallStatusLevel.INFO
  @StorageLink('rtcCallStatusUpdatedAt') @Watch('onStatusChanged') updatedAt: number = 0
  @State private visible: boolean = false
  private hideTimer: number = -1

  aboutToAppear(): void {
    this.syncVisible()
  }

  aboutToDisappear(): void {
    this.clearHideTimer()
  }

  private onStatusChanged(): void {
    this.syncVisible()
  }

  private syncVisible(): void {
    this.clearHideTimer()
    this.visible = (this.message || '').trim().length > 0
    if (!this.visible) {
      return
    }
    this.hideTimer = setTimeout(() => {
      this.visible = false
    }, 6000)
  }

  private clearHideTimer(): void {
    if (this.hideTimer > 0) {
      clearTimeout(this.hideTimer)
      this.hideTimer = -1
    }
  }

  private getAccentColor(): string {
    switch (this.level) {
      case RtcCallStatusLevel.SUCCESS:
        return '#36D66B'
      case RtcCallStatusLevel.WARNING:
        return '#F4B740'
      case RtcCallStatusLevel.ERROR:
        return '#FF6B6B'
      default:
        return '#6FB7FF'
    }
  }

  build() {
    if (this.visible) {
      Row() {
        Rect()
          .width('4lpx')
          .height('28lpx')
          .fill(this.getAccentColor())
          .borderRadius('2lpx')
        Text(this.message)
          .fontSize('16lpx')
          .fontColor('#FFFFFF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: '10lpx' })
      }
      .constraintSize({ maxWidth: '520lpx', minHeight: '36lpx' })
      .padding({ left: '12lpx', right: '14lpx', top: '8lpx', bottom: '8lpx' })
      .backgroundColor('#99000000')
      .borderRadius('6lpx')
      .alignItems(VerticalAlign.Center)
      .position({ right: '24lpx', bottom: '24lpx' })
      .zIndex(2000)
    }
  }
}
