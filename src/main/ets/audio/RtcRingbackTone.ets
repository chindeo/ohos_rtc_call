import media from '@ohos.multimedia.media'
import audio from '@ohos.multimedia.audio'
import fs from '@ohos.file.fs'
import hilog from '@ohos.hilog'
import common from '@ohos.app.ability.common'
import { writeWavFile } from './RtcWavFile'

const TAG = 'RtcRingback'

function perf(message: string): void {
  hilog.info(0, TAG, `rtc_ringback ${message}`)
}

// 国内交换机的等待音是 450Hz 单音"响 1 秒、停 4 秒"，端上直接合成，不引入音频素材。
const TONE_HZ = 450
const TONE_ON_SECONDS = 1
const TONE_OFF_SECONDS = 4
const SAMPLE_RATE = 22050
const FADE_SECONDS = 0.005
// 幅度压到 0.2：呼出阶段本机麦克风已经在采集，太响会从扬声器漏进上行，让对端听见嘟嘟声。
const TONE_AMPLITUDE = 0.2

let player: media.AVPlayer | undefined = undefined
let toneFile: fs.File | undefined = undefined
let toneWavPath: string = ''

function buildToneWav(path: string): void {
  const onSamples = TONE_ON_SECONDS * SAMPLE_RATE
  const samples = new Float32Array((TONE_ON_SECONDS + TONE_OFF_SECONDS) * SAMPLE_RATE)
  const fadeSamples = FADE_SECONDS * SAMPLE_RATE
  for (let i = 0; i < onSamples; i++) {
    // 起停各削 5ms，硬切的正弦会在扬声器上留下咔哒声。
    const fade = Math.min(1, i / fadeSamples, (onSamples - i) / fadeSamples)
    samples[i] = Math.sin(2 * Math.PI * TONE_HZ * i / SAMPLE_RATE) * TONE_AMPLITUDE * fade
  }
  writeWavFile(path, samples, SAMPLE_RATE)
}

function ensureToneWav(context: common.Context): void {
  const path = `${context.filesDir}/rtc-ringback.wav`
  if (path !== toneWavPath || !fs.accessSync(path)) {
    buildToneWav(path)
    toneWavPath = path
  }
}

function closeToneFile(): void {
  if (!toneFile) {
    return
  }
  const file = toneFile
  toneFile = undefined
  try {
    fs.closeSync(file)
  } catch (_error) {
  }
}

async function releasePlayer(p: media.AVPlayer): Promise<void> {
  try {
    await p.stop()
  } catch (_error) {
  }
  try {
    await p.release()
  } catch (_error) {
  }
}

/**
 * 主叫侧的本地等待音：发出 invite 起、对端接通或挂断止。
 * 只影响本机扬声器，不进上行；来电铃声用的是另一个播放器，两者不会互抢。
 */
export async function startRingbackTone(context: common.Context): Promise<void> {
  if (player) {
    return
  }
  const p = await media.createAVPlayer()
  // 先占位再装配：装配是异步的，这期间又进来一次 start 不能开出第二个播放器。
  player = p
  p.on('stateChange', (state: string): void => {
    if (state === 'initialized') {
      p.audioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_RINGTONE,
        rendererFlags: 0
      }
      p.prepare()
    } else if (state === 'prepared') {
      p.loop = true
      p.play().then((): void => {
        perf('stage=play ok=true')
      }).catch((error: Error): void => {
        perf(`stage=fail reason=play error=${String(error)}`)
      })
    }
  })
  p.on('error', (error: Error): void => {
    perf(`stage=fail reason=playerError error=${String(error)}`)
    stopRingbackTone()
  })
  ensureToneWav(context)
  toneFile = fs.openSync(toneWavPath, fs.OpenMode.READ_ONLY)
  p.fdSrc = { fd: toneFile.fd }
  if (player !== p) {
    // 装配期间已经被 stop 过（例如秒接），当场收掉，不留一个没人管的播放器。
    await releasePlayer(p)
  }
}

export async function stopRingbackTone(): Promise<void> {
  const p = player
  player = undefined
  if (p) {
    // 先放播放器再关 fd：装配中途关掉它正在读的 fd 会让 AVPlayer 在 prepare 里报错。
    await releasePlayer(p)
  }
  closeToneFile()
  if (p) {
    perf('stage=stop')
  }
}
