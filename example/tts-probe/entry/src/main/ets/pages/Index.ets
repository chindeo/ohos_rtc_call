import { common } from '@kit.AbilityKit'
import { audio } from '@kit.AudioKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { RtcTtsController } from '@chindeo/ohos-rtc-call'

const TAG = 'TtsProbe'

function mediaVolumeState(phase: string): string {
  try {
    const group = audio.getAudioManager().getVolumeManager()
      .getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
    const type = audio.AudioVolumeType.MEDIA
    const line = `media_volume ${phase} ${group.getVolumeSync(type)}/${group.getMaxVolumeSync(type)}`
    hilog.info(0, TAG, line)
    return line
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    hilog.error(0, TAG, `media_volume ${phase} readFailed: ${msg}`)
    return `读取音量失败: ${msg}`
  }
}

interface ProbeCase {
  label: string
  text: string
}

// 覆盖这几轮定下来的判据点：字母（espeak 分号逐个枚举）、带小数的数字（number-zh.fst，
// 已确认加分隔符只会更糟）、轻声音节、以及需要端上自动插逗号切分的无标点长句。
const CASES: ProbeCase[] = [
  { label: '字母 + 床号', text: 'ICU三床请到护士站' },
  { label: '字母 + 数字床号', text: 'A10床正在呼叫' },
  { label: '小数体温', text: '体温36.5度' },
  { label: '轻声音节', text: '为您自动接听' },
  { label: '短数字句（基线）', text: '21床正在呼叫' },
  { label: '无逗号长句（已知丢字）', text: '二十一床患者张三呼叫护士站请尽快前往处理' }
]

@Entry
@Component
struct Index {
  @State private status: string = 'TTS 引擎未就绪，正在加载模型（首次要拷 143MB，等十几秒）'
  @State private lastResult: string = '尚未播报'
  @State private busy: boolean = false
  private controller: RtcTtsController = new RtcTtsController()
  private ready: boolean = false

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext
    this.controller.init(context).then((): void => {
      this.ready = true
      this.status = 'TTS 引擎已就绪'
      this.raiseVolume()
      const requested = AppStorage.get<number>('probeIndex')
      if (requested !== undefined && requested >= 0 && requested < CASES.length) {
        hilog.info(0, TAG, `probe auto-play index=${requested}`)
        this.speak(CASES[requested].text)
        return
      }
      hilog.info(0, TAG, 'probe tts ready, waiting for manual test')
    }).catch((err: Error): void => {
      this.status = `TTS 引擎加载失败: ${err.message}`
      hilog.error(0, TAG, `probe tts init failed: ${err.message}`)
    })
  }

  // AudioVolumeGroupManager 只有 getter，可写的 AudioManager.setVolume 自 API 9 就废弃；
  // 顶不上去时至少把档位打在状态行和日志里，别让现场以为探针没跑。
  private raiseVolume(): void {
    const before = mediaVolumeState('before')
    try {
      const group = audio.getAudioManager().getVolumeManager()
        .getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      const target = group.getMaxVolumeSync(audio.AudioVolumeType.MEDIA)
      audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, target).then((): void => {
        this.status = `TTS 引擎已就绪｜${before} → ${mediaVolumeState('after')}`
      }).catch((err: Error): void => {
        this.status = `TTS 引擎已就绪（调音量失败）｜${before}`
        hilog.error(0, TAG, `setVolume failed: ${err.message}`)
      })
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.status = `TTS 引擎已就绪（调音量失败）｜${before}`
      hilog.error(0, TAG, `volume group unavailable: ${msg}`)
    }
  }

  private async speak(text: string): Promise<void> {
    if (!this.ready) {
      this.lastResult = '引擎还没就绪'
      return
    }
    this.busy = true
    const startedAt = Date.now()
    try {
      await this.controller.speak(text)
      this.lastResult = `「${text}」播报完成, 耗时${Date.now() - startedAt}ms`
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.lastResult = `「${text}」播报失败(${Date.now() - startedAt}ms): ${msg}`
      hilog.error(0, TAG, `probe tts speak failed: ${msg}`)
    }
    this.busy = false
  }

  // 「连播全部用例」按钮的实现：按 CASES 顺序播，中间不等待人耳判断。
  private async runAll(): Promise<void> {
    for (let i = 0; i < CASES.length; i++) {
      await this.speak(CASES[i].text)
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('端侧离线 TTS 探针')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
      Text(this.status)
        .fontSize(22)
      Text(this.lastResult)
        .fontSize(22)
        .fontColor('#B00020')
      ForEach(CASES, (item: ProbeCase) => {
        Button(`${item.label}：${item.text}`)
          .fontSize(20)
          .width('86%')
          .enabled(!this.busy)
          .onClick((): void => {
            this.speak(item.text)
          })
      }, (item: ProbeCase): string => item.text)
      Button('连播全部用例')
        .fontSize(20)
        .width('86%')
        .backgroundColor('#1565C0')
        .enabled(!this.busy)
        .onClick((): void => {
          this.runAll()
        })
      Button('停止播报')
        .fontSize(20)
        .width('86%')
        .backgroundColor('#555555')
        .onClick((): void => {
          this.controller.stop().catch((err: Error): void => hilog.warn(0, TAG, `stop: ${err.message}`))
        })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Start)
  }
}
