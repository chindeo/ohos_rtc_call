import { RtcCallSettingPanel } from './RtcCallSettingPanel'
import { RtcCallSettingPanelActions, RtcCallSettingPanelData } from './RtcCallSettingPanelModel'

/**
 * 音视频设置页外壳：标题栏 + 只读面板。两端只提供数据与运维动作，
 * 颜色和返回行为通过入参注入，避免再各维护一份布局。
 */
@Component
export struct RtcCallSettingPage {
  @Prop data: RtcCallSettingPanelData = new RtcCallSettingPanelData()
  actions?: RtcCallSettingPanelActions
  title: string = '音视频设置'
  headerColor: ResourceColor = '#5A4FCF'
  pageBackground: ResourceColor = Color.White
  onBack?: () => void

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize('32lpx')
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text('✕')
          .fontSize('32lpx')
          .fontColor(Color.White)
          .onClick(() => {
            this.onBack?.()
          })
      }
      .height('70lpx')
      .width('100%')
      .padding({ left: '30lpx', right: '30lpx' })
      .backgroundColor(this.headerColor)

      Scroll() {
        Column() {
          RtcCallSettingPanel({ data: this.data, actions: this.actions })
        }
        .width('100%')
        .padding('30lpx')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBackground)
  }
}
