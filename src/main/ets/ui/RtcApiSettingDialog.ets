import { RtcApiConfigStore, RtcApiConfigStoreOptions } from '../core/RtcApiConfigStore'

@CustomDialog
export struct RtcApiSettingDialog {
  controller: CustomDialogController

  @Prop storageKey: string = 'config_json_url_key'
  @Prop preferenceName: string = 'rtcCall'
  @Prop defaultUrl: string = ''
  @Prop mac: string = ''
  @Prop quickOptions: string[] = []
  @Prop title: string = '接口配置'
  @Prop macLabel: string = '设备MAC地址'
  @Prop urlLabel: string = '动态域名配置地址'
  @Prop applyText: string = '应用'
  @Prop clearText: string = '清空配置'

  @State url: string = ''

  onApplied?: (url: string) => void
  onApplyFailed?: (message: string) => void

  aboutToAppear(): void {
    this.loadUrl()
  }

  private loadUrl(): void {
    const options: RtcApiConfigStoreOptions = {
      key: this.storageKey,
      preferenceName: this.preferenceName,
      defaultUrl: this.defaultUrl
    }
    RtcApiConfigStore.getConfigUrl(options)
      .then((url: string) => {
        this.url = url
      })
      .catch((error: Error) => {
        console.error(`RtcApiSettingDialog load url failed: ${JSON.stringify(error)}`)
        this.url = this.defaultUrl
      })
  }

  private applyConfigUrl(): void {
    const options: RtcApiConfigStoreOptions = {
      key: this.storageKey,
      preferenceName: this.preferenceName,
      defaultUrl: this.defaultUrl
    }
    RtcApiConfigStore.setConfigUrl(this.url, options)
      .then((url: string) => {
        this.onApplied?.(url)
        this.controller.close()
      })
      .catch((error: Error) => {
        const message = `保存接口配置失败: ${JSON.stringify(error)}`
        console.error(message)
        this.onApplyFailed?.(message)
      })
  }

  @Builder
  private quickOptionList() {
    Column() {
      ForEach(this.quickOptions, (item: string) => {
        Text(item)
          .width('100%')
          .padding('20lpx')
          .borderRadius('10lpx')
          .backgroundColor('#f5f5f5')
          .margin({ bottom: '10lpx' })
          .onClick(() => {
            this.url = item
          })
      })
    }
    .width('100%')
  }

  build() {
    Column({ space: '30lpx' }) {
      Text(this.title)
        .fontSize('32lpx')
        .fontWeight(FontWeight.Bold)

      Column() {
        Text(this.macLabel)
        TextInput({ text: this.mac })
          .padding('20lpx')
          .backgroundColor('#eee')
          .borderRadius('10lpx')
      }
      .width('100%')

      Column() {
        Text(this.urlLabel)

        Row() {
          TextInput({ text: this.url })
            .width('100%')
            .onChange((value: string) => {
              this.url = value
            })

          Text('x')
            .fontSize('26lpx')
            .fontColor('#666')
            .padding({ left: '14lpx', right: '4lpx' })
            .onClick(() => {
              this.url = ''
            })
        }
        .padding('20lpx')
        .backgroundColor('#eee')
        .borderRadius('10lpx')

        if (this.quickOptions.length > 0) {
          this.quickOptionList()
        }
      }
      .width('100%')

      Button(this.applyText)
        .width('300lpx')
        .onClick(() => {
          this.applyConfigUrl()
        })

      Button(this.clearText)
        .width('300lpx')
        .backgroundColor('#ccc')
        .onClick(() => {
          this.url = ''
        })
    }
    .padding('40lpx')
    .width('750lpx')
    .backgroundColor(Color.White)
    .borderRadius('20lpx')
  }
}
