export class RtcCallSettingToggleItem {
  label: string = ''
  value: boolean = false
  implemented: boolean = false

  constructor(label: string, value: boolean, implemented: boolean) {
    this.label = label
    this.value = value
    this.implemented = implemented
  }
}

export class RtcCallSettingOptionItem {
  label: string = ''
  summary: string = ''
  selectable: boolean = true

  constructor(label: string, summary: string, selectable: boolean = true) {
    this.label = label
    this.summary = summary
    this.selectable = selectable
  }
}

/**
 * 选项行的渲染参数。@Builder 只有"传入单一对象字面量"时才会在状态变化时刷新，
 * 所以选中态必须打包成对象，不能按位置传布尔值。
 */
export interface RtcCallSettingOptionRowParam {
  option: RtcCallSettingOptionItem
  selected: boolean
  onSelect: (label: string) => void
}

/**
 * 音视频设置面板的数据快照。UI 只负责渲染，数据来源与持久化留给宿主 App，
 * 这样两台设备共用一份界面，各自决定哪些控件真正可用。
 */
export class RtcCallSettingPanelData {
  toggles: RtcCallSettingToggleItem[] = []
  sampleRateOptions: RtcCallSettingOptionItem[] = []
  selectedSampleRate: string = ''
  resolutionOptions: RtcCallSettingOptionItem[] = []
  selectedResolutionLabel: string = ''
  answerPercent: number = 90
  overrideVolume: boolean = false
  statusLines: string[] = []
  resolutionEditable: boolean = true
  volumeEditable: boolean = true
  cacheClearable: boolean = true
  recordingClearable: boolean = false
  notImplementedTip: string = '当前版本未开放'
  emptyResolutionTip: string = '服务器未下发可选分辨率'
}

export interface RtcCallSettingPanelActions {
  onToggle(index: number): void
  onSelectSampleRate(label: string): void
  onSelectResolution(label: string): void
  onAnswerPercentChange(percent: number): void
  onOverrideVolumeToggled(enabled: boolean): void
  onClearCache(): void
  onClearRecording(): void
  onSave(): void
}
