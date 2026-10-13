import {
  RtcCallSettingOptionItem,
  RtcCallSettingOptionRowParam,
  RtcCallSettingPanelActions,
  RtcCallSettingPanelData,
  RtcCallSettingToggleItem
} from '../ui/RtcCallSettingPanelModel'

/**
 * 音视频设置面板，结构对齐安卓同名页面：开关组 / 采样率 / 视频分辨率 /
 * 音视频音量 / 清除缓存·清理录音 / 当前状态。
 * 界面只读：服务器是唯一配置来源，控件不接受点击后假装生效。
 */
@Component
export struct RtcCallSettingPanel {
  @Prop data: RtcCallSettingPanelData = new RtcCallSettingPanelData()
  actions?: RtcCallSettingPanelActions

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize('24lpx')
      .fontColor('#333')
      .margin({ top: '20lpx', bottom: '10lpx' })
  }

  @Builder
  private tipChip(text: string) {
    Text(text)
      .fontSize('20lpx')
      .fontColor(Color.White)
      .backgroundColor('#CCCCCC')
      .borderRadius('18lpx')
      .padding({ left: '18lpx', right: '18lpx', top: '6lpx', bottom: '6lpx' })
  }

  @Builder
  private toggleChip(item: RtcCallSettingToggleItem) {
    Row() {
      Text(item.label)
        .fontSize('22lpx')
        .fontColor(item.implemented ? '#333' : '#999')
        .layoutWeight(1)
      Text(item.implemented ? (item.value ? '已开启' : '未开启') : this.data.notImplementedTip)
        .fontSize('20lpx')
        .fontColor(Color.White)
        .padding({ left: '18lpx', right: '18lpx', top: '6lpx', bottom: '6lpx' })
        .backgroundColor(item.implemented ? (item.value ? '#5A4FCF' : '#B0AED1') : '#CCCCCC')
        .borderRadius('18lpx')
    }
    .width('32%')
    .padding({ left: '16lpx', right: '16lpx' })
    .height('56lpx')
    .margin({ bottom: '12lpx' })
    .backgroundColor('#EEF0F8')
    .borderRadius('10lpx')
  }

  @Builder
  private optionRow(param: RtcCallSettingOptionRowParam) {
    Row() {
      if (param.selected) {
        Text('当前')
          .fontSize('18lpx')
          .fontColor(Color.White)
          .backgroundColor('#E24A6F')
          .borderRadius('14lpx')
          .padding({ left: '12lpx', right: '12lpx', top: '4lpx', bottom: '4lpx' })
      }
      Text(param.option.label)
        .fontSize('22lpx')
        .fontColor(param.selected ? '#333' : '#999')
        .margin({ left: param.selected ? '8lpx' : '0' })
      Text(param.option.summary)
        .fontSize('18lpx')
        .fontColor('#888')
        .margin({ left: '12lpx' })
    }
    .width('32%')
    .margin({ bottom: '10lpx' })
  }

  build() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.data.toggles, (item: RtcCallSettingToggleItem) => {
          this.toggleChip(item)
        }, (item: RtcCallSettingToggleItem) => `${item.label}_${item.value ? 1 : 0}`)
      }
      .width('100%')

      this.sectionTitle('采样率设置')
      if (this.data.sampleRateOptions.length === 0) {
        Row({ space: '16lpx' }) {
          Text('8000 / 16000 / 32000 / 44100 / 48000')
            .fontSize('22lpx')
            .fontColor('#999')
          this.tipChip(this.data.notImplementedTip)
        }
        .width('100%')
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.sampleRateOptions, (option: RtcCallSettingOptionItem) => {
            this.optionRow({
              option: option,
              selected: option.label === this.data.selectedSampleRate
            })
          }, (option: RtcCallSettingOptionItem) =>
            `${option.label}_${option.label === this.data.selectedSampleRate ? 1 : 0}`)
        }
        .width('100%')
      }

      this.sectionTitle('视频分辨率设置')
      if (this.data.resolutionOptions.length === 0) {
        Text(this.data.emptyResolutionTip)
          .fontSize('22lpx')
          .fontColor('#999')
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.resolutionOptions, (option: RtcCallSettingOptionItem) => {
            this.optionRow({
              option: option,
              selected: option.label === this.data.selectedResolutionLabel
            })
          }, (option: RtcCallSettingOptionItem) =>
            `${option.label}_${option.label === this.data.selectedResolutionLabel ? 1 : 0}`)
        }
        .width('100%')
      }

      this.sectionTitle('音视频音量设置')
      Row() {
        Text('生效应答音量')
          .fontSize('22lpx')
          .fontColor('#333')
          .layoutWeight(1)
        Text(`${this.data.answerPercent}%`)
          .fontSize('24lpx')
          .fontColor('#E24A6F')
      }
      .width('100%')

      Row() {
        Text('本机音量覆盖')
          .fontSize('22lpx')
          .fontColor('#333')
          .layoutWeight(1)
        Text(this.data.overrideVolume ? '启用中，清除缓存可恢复服务器值' : '未启用')
          .fontSize('20lpx')
          .fontColor('#999')
      }
      .width('100%')
      .margin({ top: '8lpx' })

      Row({ space: '20lpx' }) {
        Button('清除缓存')
          .height('60lpx')
          .fontSize('22lpx')
          .backgroundColor(this.data.cacheClearable ? '#5A4FCF' : '#CCCCCC')
          .borderRadius('30lpx')
          .enabled(this.data.cacheClearable)
          .onClick(() => {
            this.actions?.onClearCache()
          })
        Button('清理录音')
          .height('60lpx')
          .fontSize('22lpx')
          .backgroundColor(this.data.recordingClearable ? '#5A4FCF' : '#CCCCCC')
          .borderRadius('30lpx')
          .enabled(this.data.recordingClearable)
          .onClick(() => {
            this.actions?.onClearRecording()
          })
      }
      .margin({ top: '24lpx' })

      this.sectionTitle('当前状态')
      ForEach(this.data.statusLines, (line: string) => {
        Text(line)
          .fontSize('20lpx')
          .fontColor('#666')
          .margin({ bottom: '6lpx' })
          .width('100%')
      }, (line: string) => line)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
