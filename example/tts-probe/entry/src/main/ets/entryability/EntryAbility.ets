import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'

const TAG = 'TtsProbe'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // uitest 在这批设备上拿不到布局，人工点不动；留一个启动参数口让取证能指定播第几条。
    const params = want.parameters as Record<string, Object> | undefined
    const raw = params ? params['probeIndex'] : undefined
    const index = typeof raw === 'string' ? Number(raw) : Number(raw)
    if (Number.isFinite(index) && index >= 0) {
      AppStorage.setOrCreate('probeIndex', index)
      hilog.info(0, TAG, `probe will auto-play case index=${index}`)
    }
    hilog.info(0, TAG, 'probe ability created')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err && err.code) {
        hilog.error(0, TAG, `loadContent failed: code=${err.code}`)
        return
      }
      hilog.info(0, TAG, 'loadContent ok')
    })
  }
}
