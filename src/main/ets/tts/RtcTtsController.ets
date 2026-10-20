import sherpa from 'libsherpa_onnx.so'
import media from '@ohos.multimedia.media'
import fs from '@ohos.file.fs'
import hilog from '@ohos.hilog'
import common from '@ohos.app.ability.common'
import { normalizeTtsText } from './RtcTtsText'
import { clampSpeechRate, DEFAULT_SPEECH_RATE } from './RtcSpeechRate'
import { writeWavFile } from '../audio/RtcWavFile'

const TAG = 'RtcTts'

/**
 * 播报取证锚点。只加日志不改行为：没有这几条，"没出声"、"播了但听不见"和"队列卡住"
 * 在日志上是同一个样子，验收清单里 RTF 和长时间不失效两项也无从判定。
 */
function perf(message: string): void {
  hilog.info(0, TAG, `rtc_tts_perf ${message}`)
}

let speakSeq: number = 0
let queuedCount: number = 0

export interface RtcTtsConfig {
  modelDir?: string
  acousticModel?: string
  vocoder?: string
  lexicon?: string
  tokens?: string
  noiseScale?: number
  lengthScale?: number
  numThreads?: number
}

const DEFAULT_MODEL_DIR = 'matcha-icefall-zh-en'
const DEFAULT_ACOUSTIC = 'model-steps-3.onnx'
const DEFAULT_LEXICON = 'lexicon.txt'
const DEFAULT_TOKENS = 'tokens.txt'
// 床号、体温这类短数字交给 sherpa 的文本规整；时刻和编号要先在端上转成汉字，
// 因为 number.fst 排在最前会把所有数字串按基数读掉，date/phone 两条永远轮不到。
// 注意开关名：TTS 用的是 rule_fsts，ASR 才叫 rule-fsts，传错会直接 exit(-1)。
// espeak-ng 的音库目录：只有中英混读模型带它，纯中文模型没有这个目录。
const ESPEAK_DIR = 'espeak-ng-data'
const DEFAULT_LENGTH_SCALE = 1.0
const DEFAULT_NUM_THREADS = 4

/**
 * 两档模型的声码器、fst 文件名、扩散噪声和"能不能调速"都不一样，混用会直接念错内容：
 * zh-en 用 baker 那套 noise_scale=0.2 会把「21床正在呼叫」念成「二十一床正呼叫」、
 * 「体温36.5度」念成「三十四点五度」（2026-10-20 扫参复现，与现场反馈逐条对得上）；
 * 反过来 zh-en 一调速（speed=0.9）数字又错回去，所以它那档把语速锁死。
 * 选档只看宿主 rawfile 里放的是哪个目录，不再需要同时改三处常量。
 */
interface RtcTtsProfile {
  vocoder: string
  fsts: string[]
  noiseScale: number
  speedAdjustable: boolean
}

const PROFILE_ZH_EN: RtcTtsProfile = {
  vocoder: 'vocos-16khz-univ.onnx',
  fsts: ['number-zh.fst', 'date-zh.fst', 'phone-zh.fst'],
  noiseScale: 1.0,
  speedAdjustable: false
}

const PROFILE_BAKER: RtcTtsProfile = {
  vocoder: 'vocos-22khz-univ.onnx',
  fsts: ['number.fst', 'date.fst', 'phone.fst'],
  noiseScale: 0.2,
  speedAdjustable: true
}

function profileFor(modelDir: string): RtcTtsProfile {
  return modelDir === DEFAULT_MODEL_DIR ? PROFILE_ZH_EN : PROFILE_BAKER
}

let activePlayer: media.AVPlayer | undefined = undefined

async function ensureModelFiles(ctx: common.Context, modelDir: string, profile: RtcTtsProfile): Promise<string> {
  const base = `${ctx.filesDir}/${modelDir}`
  if (!fs.accessSync(base)) {
    fs.mkdirSync(base, true)
  }
  const names = [DEFAULT_ACOUSTIC, profile.vocoder, DEFAULT_LEXICON, DEFAULT_TOKENS].concat(profile.fsts)
  for (const name of names) {
    const dest = `${base}/${name}`
    if (fs.accessSync(dest)) {
      continue
    }
    // 没打进包的老宿主工程可以不带 fst，缺文件只影响数字读法，不能让引擎起不来。
    let content: Uint8Array | undefined = undefined
    try {
      content = await ctx.resourceManager.getRawFileContent(`${modelDir}/${name}`)
    } catch (_error) {
      continue
    }
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    fs.writeSync(file.fd, content.buffer as ArrayBuffer)
    fs.closeSync(file)
  }
  let espeakFiles = 0
  try {
    espeakFiles = await ensureEspeakTree(ctx, modelDir, base)
  } catch (_error) {
    espeakFiles = -1
  }
  perf(`stage=extract model=${modelDir} espeak_files=${espeakFiles}`)
  return base
}

// getRawFileListSync 返回的是 string[]，没有 isDir；rawfile 也 stat 不了，
// 所以只能"读得到就是文件、读不到就是目录"来分流。
async function ensureRawTree(ctx: common.Context, rawDir: string, destDir: string): Promise<number> {
  const entries: string[] = ctx.resourceManager.getRawFileListSync(rawDir)
  if (!fs.accessSync(destDir)) {
    fs.mkdirSync(destDir, true)
  }
  let written = 0
  for (const name of entries) {
    const rawChild = `${rawDir}/${name}`
    const destChild = `${destDir}/${name}`
    let content: Uint8Array | undefined = undefined
    try {
      content = await ctx.resourceManager.getRawFileContent(rawChild)
    } catch (_error) {
      written += await ensureRawTree(ctx, rawChild, destChild)
      continue
    }
    if (fs.accessSync(destChild)) {
      continue
    }
    const file = fs.openSync(destChild, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    fs.writeSync(file.fd, content.buffer as ArrayBuffer)
    fs.closeSync(file)
    written += 1
  }
  return written
}

// espeak-ng-data 有 355 个文件，逐个 getRawFileContent 再判存在太费，
// 解过一次就落一个标记文件；espeak 只按自己的文件名表读目录，多个陌生文件不影响它。
async function ensureEspeakTree(ctx: common.Context, modelDir: string, base: string): Promise<number> {
  const tree = `${base}/${ESPEAK_DIR}`
  const marker = `${tree}/.extracted`
  if (fs.accessSync(marker)) {
    return -2
  }
  const written = await ensureRawTree(ctx, `${modelDir}/${ESPEAK_DIR}`, tree)
  if (written > 0) {
    const file = fs.openSync(marker, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    fs.writeSync(file.fd, 'ok')
    fs.closeSync(file)
  }
  return written
}

function ruleFstsArg(base: string, fsts: string[]): string {
  const present = fsts.filter((name: string): boolean => fs.accessSync(`${base}/${name}`))
  return present.map((name: string): string => `${base}/${name}`).join(',')
}

async function stopActivePlayer(): Promise<void> {
  const p = activePlayer
  activePlayer = undefined
  if (!p) {
    return
  }
  try {
    await p.stop()
  } catch (_error) {
  }
  try {
    await p.release()
  } catch (_error) {
  }
}

// 返回 false 只代表看门狗到点（渲染器没起来），需要重试；正常播完或被主动停止都返回 true。
async function playOnce(path: string, durationMs: number): Promise<boolean> {
  await stopActivePlayer()
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
  const player = await media.createAVPlayer()
  activePlayer = player
  let settled = false
  let timedOut = false
  let watchdog = 0
  const finish = (): void => {
    if (settled) {
      return
    }
    settled = true
    if (watchdog !== 0) {
      clearTimeout(watchdog)
      watchdog = 0
    }
    try {
      fs.closeSync(file)
    } catch (_error) {
    }
  }
  try {
    // AVPlayer 只能在 initialized 态 prepare、prepared 态 play，顺序写死，否则报
    // "current state is not stopped or initialized, unsupport prepare operation"。
    await new Promise<void>((resolve, reject) => {
      const done = (): void => {
        finish()
        resolve()
      }
      // 这块板子的渲染器偶发起不来（HDI 报 AudioRenderProxyStart -1），播放器会停在 playing
      // 一百多秒才自己 drain 出 completed。按音频时长兜底，不能让一条把整个播报挂死。
      watchdog = setTimeout((): void => {
        hilog.warn(0, TAG, `playWav watchdog fired, durationMs=${durationMs}, player stuck`)
        timedOut = true
        done()
      }, Math.max(3000, durationMs + 4000))
      player.on('stateChange', (state: string) => {
        if (settled) {
          return
        }
        if (state === 'initialized') {
          player.prepare().catch((err: Error) => {
            finish()
            reject(err)
          })
          return
        }
        if (state === 'prepared') {
          player.play().catch((err: Error) => {
            finish()
            reject(err)
          })
          return
        }
        if (state === 'completed') {
          done()
          return
        }
        // stop()/release() 之后不会再有 completed，必须在这里收尾，否则 speak() 永远挂着。
        if (state === 'stopped' || state === 'idle') {
          done()
        }
      })
      player.on('error', (err: Error) => {
        finish()
        reject(err)
      })
      player.fdSrc = { fd: file.fd, length: fs.statSync(path).size }
    })
  } finally {
    finish()
    if (activePlayer === player) {
      await stopActivePlayer()
    } else {
      try {
        await player.release()
      } catch (_error) {
      }
    }
  }
  return !timedOut
}

const PLAY_ATTEMPTS = 2

// 返回实际用的尝试次数：>1 就说明这块板子的渲染器起不来过一次。
async function playWav(path: string, durationMs: number): Promise<number> {
  for (let attempt = 1; attempt <= PLAY_ATTEMPTS; attempt++) {
    if (await playOnce(path, durationMs) || attempt === PLAY_ATTEMPTS) {
      return attempt
    }
    hilog.warn(0, TAG, `playWav retry, attempt=${attempt + 1}`)
  }
  return PLAY_ATTEMPTS
}

export class RtcTtsController {
  private handle: number = 0
  private ready: Promise<void> | undefined = undefined
  private speaking: Promise<void> | undefined = undefined
  private generation: number = 0
  private wavPath: string = ''
  private speed: number = DEFAULT_SPEECH_RATE
  private speedAdjustable: boolean = true

  /**
   * 语速在真正合成那一刻取值：排在队列里还没轮到的那条，会按改后的值念。
   * 中英档不认这个旋钮（0.9 会把「体温36.5度」念成「先三六点五度」），所以只记日志不生效，
   * 并且一定要打出来：否则现场看到后台填了 0.9 而播报没变，会当成参数没下发去查链路。
   */
  setSpeed(value: number): void {
    const requested = clampSpeechRate(value)
    if (!this.speedAdjustable) {
      perf(`stage=speed value=${this.speed} requested=${requested} model_locked=true`)
      return
    }
    if (requested === this.speed) {
      return
    }
    this.speed = requested
    perf(`stage=speed value=${requested}`)
  }

  /** 当前生效的语速，给宿主测试页只读显示用（不是它设置的那个值，而是引擎真正在用的）。 */
  getSpeed(): number {
    return this.speed
  }

  init(ctx: common.Context, cfg: RtcTtsConfig = {}): Promise<void> {
    if (this.ready) {
      return this.ready
    }
    const modelDir = cfg.modelDir ?? DEFAULT_MODEL_DIR
    const threads = cfg.numThreads ?? DEFAULT_NUM_THREADS
    const profile = profileFor(modelDir)
    const noiseScale = cfg.noiseScale ?? profile.noiseScale
    this.speedAdjustable = profile.speedAdjustable
    if (!profile.speedAdjustable) {
      // 初始化前可能就收到过后台语速（宿主先拿到 /config/list），锁档时把它清回常速。
      this.speed = DEFAULT_SPEECH_RATE
    }
    this.wavPath = `${ctx.filesDir}/tts-out.wav`
    this.ready = (async (): Promise<void> => {
      const startedAt = Date.now()
      const base = await ensureModelFiles(ctx, modelDir, profile)
      const fsts = ruleFstsArg(base, profile.fsts)
      const h = await sherpa.createAsync({
        acousticModel: cfg.acousticModel ?? `${base}/${DEFAULT_ACOUSTIC}`,
        vocoder: cfg.vocoder ?? `${base}/${profile.vocoder}`,
        lexicon: cfg.lexicon ?? `${base}/${DEFAULT_LEXICON}`,
        tokens: cfg.tokens ?? `${base}/${DEFAULT_TOKENS}`,
        // 真机取证：sherpa 检查的是 <data_dir>/phontab，所以要指到 espeak-ng-data
        // 本身，指到它的父目录会得到 "phontab does not exist" 然后 create 返回 null。
        // 纯中文模型不带这个目录，就不传（空串在 shim 里等价于不设 data_dir）。
        dataDir: fs.accessSync(`${base}/${ESPEAK_DIR}/phontab`) ? `${base}/${ESPEAK_DIR}` : '',
        ruleFsts: fsts,
        noiseScale: noiseScale,
        lengthScale: cfg.lengthScale ?? DEFAULT_LENGTH_SCALE,
        numThreads: threads
      })
      if (h === 0) {
        perf(`stage=fail reason=create_zero elapsed_ms=${Date.now() - startedAt} fsts=${fsts === '' ? '0' : String(fsts.split(',').length)}`)
        throw new Error('RtcTtsController: sherpa.createAsync failed')
      }
      this.handle = h
      perf(`stage=init ok=true create_ms=${Date.now() - startedAt} threads=${threads}` +
        ` noiseScale=${noiseScale} fsts=${fsts === '' ? '0' : String(fsts.split(',').length)}`)
    })()
    return this.ready
  }

  async speak(text: string): Promise<void> {
    if (!text) {
      return
    }
    if (!this.ready) {
      perf('stage=fail reason=not_initialized')
      throw new Error('RtcTtsController: not initialized')
    }
    speakSeq += 1
    const seq = speakSeq
    queuedCount += 1
    // fed= 是真正喂给引擎的规整后文本：现场报"漏字"时先看这里，就能分清是端上规整吃掉的
    // 还是 espeak/词表没这个音。
    const fed = normalizeTtsText(text)
    perf(`stage=enqueue seq=${seq} queue=${queuedCount} text=${text} fed=${fed}`)
    // 多条播报排队念完，不互相打断：这里不能先 stop，否则新呼叫会把上一条的播报掐掉。
    const prev = this.speaking ?? Promise.resolve()
    this.speaking = prev.catch(() => undefined).then(async (): Promise<void> => {
      await this.ready
      queuedCount -= 1
      // 代次只在真正轮到这条时取：stop() 只掐正在播的那一条，排在后面的照常播。
      const generation = this.generation
      const synthStartedAt = Date.now()
      try {
        const generated = await sherpa.generateAsync(this.handle, fed, 0, this.speed)
        const synthMs = Date.now() - synthStartedAt
        if (generation !== this.generation) {
          perf(`stage=skip seq=${seq} reason=cancelled synth_ms=${synthMs}`)
          return
        }
        if (!generated || generated.sampleRate === 0 || generated.samples.length === 0) {
          perf(`stage=fail seq=${seq} reason=empty_audio synth_ms=${synthMs}`)
          return
        }
        const audioMs = generated.samples.length / generated.sampleRate * 1000
        perf(`stage=synth seq=${seq} ok=true synth_ms=${synthMs} audio_ms=${Math.round(audioMs)} queue=${queuedCount}`)
        writeWavFile(this.wavPath, generated.samples, generated.sampleRate)
        const playStartedAt = Date.now()
        const attempts = await playWav(this.wavPath, audioMs)
        // rtf 只算合成耗时与音频时长之比，验收清单里 RTF<=2.0 看这个数，不看墙钟。
        perf(`stage=play seq=${seq} play_ms=${Date.now() - playStartedAt} attempts=${attempts}` +
          ` rtf=${(synthMs / audioMs).toFixed(2)} queue=${queuedCount}`)
      } catch (error) {
        perf(`stage=fail seq=${seq} reason=exception elapsed_ms=${Date.now() - synthStartedAt}` +
          ` error=${String(error)}`)
        throw error
      }
    })
    return this.speaking
  }

  async stop(): Promise<void> {
    this.generation++
    perf(`stage=stop generation=${this.generation} queue=${queuedCount}`)
    await stopActivePlayer()
  }

  async release(): Promise<void> {
    this.generation++
    await stopActivePlayer()
    if (this.handle !== 0) {
      sherpa.destroy(this.handle)
      this.handle = 0
    }
    this.ready = undefined
    this.speaking = undefined
  }

  isReady(): boolean {
    return this.handle !== 0
  }
}
