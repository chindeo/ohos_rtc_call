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

  constructor(label: string, summary: string) {
    this.label = label
    this.summary = summary
  }
}

/**
 * 选项行的渲染参数。@Builder 只有"传入单一对象字面量"时才会在状态变化时刷新，
 * 所以选中态必须打包成对象，不能按位置传布尔值。
 */
export interface RtcCallSettingOptionRowParam {
  option: RtcCallSettingOptionItem
  selected: boolean
}

/**
 * 音视频设置面板的数据快照。界面只读：分辨率、音量一律以服务器为准，
 * 本机唯一能改的是"清除本机覆盖"。数据来源与持久化留给宿主 App，
 * 这样两台设备共用一份界面。
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
  cacheClearable: boolean = true
  recordingClearable: boolean = false
  notImplementedTip: string = '当前版本未开放'
  emptyResolutionTip: string = '服务器未下发可选分辨率'
}

export interface RtcCallSettingPanelActions {
  onClearCache(): void
  onClearRecording(): void
}
