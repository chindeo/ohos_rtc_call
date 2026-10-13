import {
  RtcCallSettingOptionItem,
  RtcCallSettingOptionRowParam,
  RtcCallSettingPanelActions,
  RtcCallSettingPanelData,
  RtcCallSettingToggleItem
} from '../ui/RtcCallSettingPanelModel'

/**
 * 音视频设置面板，结构对齐安卓同名页面：开关组 / 采样率 / 视频分辨率 /
 * 音视频音量 / 清除缓存·清理录音 / 当前状态。未实现的控件一律灰显并给出原因，
 * 不接收点击后假装生效。
 */
@Component
export struct RtcCallSettingPanel {
  @Prop @Watch('syncFromData') data: RtcCallSettingPanelData = new RtcCallSettingPanelData()
  actions?: RtcCallSettingPanelActions
  @State private toggles: RtcCallSettingToggleItem[] = []
  @State private selectedResolutionLabel: string = ''
  @State private selectedSampleRate: string = ''
  @State private answerPercent: number = 90
  @State private overrideVolume: boolean = false

  aboutToAppear(): void {
    this.syncFromData()
  }

  syncFromData(): void {
    this.toggles = this.data.toggles
    this.selectedResolutionLabel = this.data.selectedResolutionLabel
    this.selectedSampleRate = this.data.selectedSampleRate
    this.answerPercent = this.data.answerPercent
    this.overrideVolume = this.data.overrideVolume
  }

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
  private toggleChip(item: RtcCallSettingToggleItem, index: number) {
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
    .onClick(() => {
      if (item.implemented) {
        this.actions?.onToggle(index)
      }
    })
  }

  @Builder
  private optionRow(param: RtcCallSettingOptionRowParam) {
    Row() {
      Checkbox()
        .select(param.selected)
        .selectedColor('#E24A6F')
        .enabled(param.option.selectable)
        .onChange((value: boolean) => {
          if (value && param.option.selectable) {
            param.onSelect(param.option.label)
          }
        })
      Text(param.option.label)
        .fontSize('22lpx')
        .fontColor(param.option.selectable ? '#333' : '#999')
        .margin({ left: '8lpx' })
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
        ForEach(this.toggles, (item: RtcCallSettingToggleItem, index: number) => {
          this.toggleChip(item, index)
        }, (item: RtcCallSettingToggleItem) => item.label)
      }

      this.sectionTitle('采样率设置')
      if (this.data.sampleRateOptions.length === 0) {
        Row() {
          Text('8000 / 16000 / 32000 / 44100 / 48000')
            .fontSize('22lpx')
            .fontColor('#999')
          this.tipChip(this.data.notImplementedTip)
        }
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.sampleRateOptions, (option: RtcCallSettingOptionItem) => {
            this.optionRow({
              option: option,
              selected: option.label === this.selectedSampleRate,
              onSelect: (label: string) => {
                this.actions?.onSelectSampleRate(label)
              }
            })
          }, (option: RtcCallSettingOptionItem) =>
            `${option.label}_${option.label === this.selectedSampleRate ? 1 : 0}`)
        }
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
              option: new RtcCallSettingOptionItem(option.label, option.summary, this.data.resolutionEditable),
              selected: option.label === this.selectedResolutionLabel,
              onSelect: (label: string) => {
                this.selectedResolutionLabel = label
                this.actions?.onSelectResolution(label)
              }
            })
          }, (option: RtcCallSettingOptionItem) =>
            `${option.label}_${option.label === this.selectedResolutionLabel ? 1 : 0}`)
        }
      }

      this.sectionTitle('音视频音量设置')
      Row() {
        Slider({ min: 0, max: 100, step: 1, value: this.answerPercent })
          .layoutWeight(1)
          .blockColor('#5A4FCF')
          .enabled(this.data.volumeEditable)
          .onChange((value: number) => {
            if (!this.data.volumeEditable) {
              return
            }
            this.answerPercent = Math.round(value)
            this.overrideVolume = true
            this.actions?.onAnswerPercentChange(this.answerPercent)
            this.actions?.onOverrideVolumeToggled(true)
          })
        Text(`${this.answerPercent}%`)
          .fontSize('24lpx')
          .fontColor('#E24A6F')
          .width('100lpx')
          .textAlign(TextAlign.Center)
      }
      .width('100%')

      Row() {
        Checkbox()
          .select(this.overrideVolume)
          .selectedColor('#E24A6F')
          .enabled(this.data.volumeEditable)
          .onChange((value: boolean) => {
            this.overrideVolume = value
            this.actions?.onOverrideVolumeToggled(value)
          })
        Text('用本机设置覆盖服务器音量')
          .fontSize('22lpx')
          .margin({ left: '8lpx' })
      }

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
