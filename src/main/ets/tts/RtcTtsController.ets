import sherpa from 'libsherpa_onnx.so'
import media from '@ohos.multimedia.media'
import fs from '@ohos.file.fs'
import hilog from '@ohos.hilog'
import common from '@ohos.app.ability.common'
import { normalizeTtsText } from './RtcTtsText'

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

const DEFAULT_MODEL_DIR = 'matcha-icefall-zh-baker'
const DEFAULT_ACOUSTIC = 'model-steps-3.onnx'
const DEFAULT_VOCODER = 'vocos-22khz-univ.onnx'
const DEFAULT_LEXICON = 'lexicon.txt'
const DEFAULT_TOKENS = 'tokens.txt'
// 床号、体温这类短数字交给 sherpa 的文本规整；时刻和编号要先在端上转成汉字，
// 因为 number.fst 排在最前会把所有数字串按基数读掉，date/phone 两条永远轮不到。
// 注意开关名：TTS 用的是 rule_fsts，ASR 才叫 rule-fsts，传错会直接 exit(-1)。
const RULE_FSTS = ['number.fst', 'date.fst', 'phone.fst']
// espeak-ng 的音库目录：只有中英混读模型带它，纯中文模型没有这个目录。
const ESPEAK_DIR = 'espeak-ng-data'
const DEFAULT_NOISE_SCALE = 0.2
const DEFAULT_LENGTH_SCALE = 1.0
const DEFAULT_NUM_THREADS = 4
// 语速固定 1.0，不做可调倍率：.61 实测 speed=0.85 时同一条"21床,正在呼叫。"会合成出
// "211床正在呼呼叫"这种叠字和多余音素。sherpa 的 speed 是靠拉长 duration 实现的，
// 这个模型被拉长后对齐就崩，所以宁可快一点，也不要念不清。

let activePlayer: media.AVPlayer | undefined = undefined

async function ensureModelFiles(ctx: common.Context, modelDir: string): Promise<string> {
  const base = `${ctx.filesDir}/${modelDir}`
  if (!fs.accessSync(base)) {
    fs.mkdirSync(base, true)
  }
  const names = [DEFAULT_ACOUSTIC, DEFAULT_VOCODER, DEFAULT_LEXICON, DEFAULT_TOKENS].concat(RULE_FSTS)
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

function ruleFstsArg(base: string): string {
  const present = RULE_FSTS.filter((name: string): boolean => fs.accessSync(`${base}/${name}`))
  return present.map((name: string): string => `${base}/${name}`).join(',')
}

function writeWav(path: string, samples: Float32Array, sampleRate: number): void {
  const n = samples.length
  const dataBytes = n * 2
  const headerSize = 44
  const total = headerSize + dataBytes
  const buf = new ArrayBuffer(total)
  const view = new DataView(buf)
  const wr = (off: number, s: string): void => {
    for (let i = 0; i < s.length; i++) {
      view.setUint8(off + i, s.charCodeAt(i))
    }
  }
  wr(0, 'RIFF')
  view.setUint32(4, total - 8, true)
  wr(8, 'WAVE')
  wr(12, 'fmt ')
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * 2, true)
  view.setUint16(32, 2, true)
  view.setUint16(34, 16, true)
  wr(36, 'data')
  view.setUint32(40, dataBytes, true)
  let off = 44
  for (let i = 0; i < n; i++) {
    let v = samples[i]
    if (v > 1.0) v = 1.0
    if (v < -1.0) v = -1.0
    const int16 = v < 0 ? Math.round(v * 32768) : Math.round(v * 32767)
    view.setInt16(off, int16, true)
    off += 2
  }
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
  fs.writeSync(file.fd, buf)
  fs.closeSync(file)
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

  init(ctx: common.Context, cfg: RtcTtsConfig = {}): Promise<void> {
    if (this.ready) {
      return this.ready
    }
    const modelDir = cfg.modelDir ?? DEFAULT_MODEL_DIR
    const threads = cfg.numThreads ?? DEFAULT_NUM_THREADS
    const noiseScale = cfg.noiseScale ?? DEFAULT_NOISE_SCALE
    this.wavPath = `${ctx.filesDir}/tts-out.wav`
    this.ready = (async (): Promise<void> => {
      const startedAt = Date.now()
      const base = await ensureModelFiles(ctx, modelDir)
      const fsts = ruleFstsArg(base)
      const h = await sherpa.createAsync({
        acousticModel: cfg.acousticModel ?? `${base}/${DEFAULT_ACOUSTIC}`,
        vocoder: cfg.vocoder ?? `${base}/${DEFAULT_VOCODER}`,
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
        const generated = await sherpa.generateAsync(this.handle, fed, 0, 1.0)
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
        writeWav(this.wavPath, generated.samples, generated.sampleRate)
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
