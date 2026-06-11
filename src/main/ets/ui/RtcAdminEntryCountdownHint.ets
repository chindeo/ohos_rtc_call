@Component
export struct RtcAdminEntryCountdownHint {
  @StorageLink('rtcAdminEntryCountdownVisible') visible: boolean = false
  @StorageLink('rtcAdminEntryCountdownText') text: string = ''
  @StorageLink('rtcAdminEntryCountdownUpdatedAt') updatedAt: number = 0

  build() {
    if (this.visible && this.text.length > 0) {
      Row() {
        Text(this.text)
          .fontSize('16lpx')
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .constraintSize({ maxWidth: '420lpx', minHeight: '34lpx' })
      .padding({ left: '14lpx', right: '14lpx', top: '8lpx', bottom: '8lpx' })
      .backgroundColor('#AA000000')
      .borderRadius('6lpx')
      .alignItems(VerticalAlign.Center)
      .position({ right: '24lpx', bottom: '76lpx' })
      .zIndex(2100)
    }
  }
}
