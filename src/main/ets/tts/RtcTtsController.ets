import sherpa from 'libsherpa_onnx.so'
import media from '@ohos.multimedia.media'
import fs from '@ohos.file.fs'
import common from '@ohos.app.ability.common'

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
// 数字/日期/电话的读法交给 sherpa 的文本规整，不在端上自己拼汉字。
// 注意开关名：TTS 用的是 rule_fsts，ASR 才叫 rule-fsts，传错会直接 exit(-1)。
const RULE_FSTS = ['number.fst', 'date.fst', 'phone.fst']
const DEFAULT_NOISE_SCALE = 0.33
const DEFAULT_LENGTH_SCALE = 1.0
const DEFAULT_NUM_THREADS = 4

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
  return base
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

async function playWav(path: string): Promise<void> {
  await stopActivePlayer()
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
  const player = await media.createAVPlayer()
  activePlayer = player
  let settled = false
  const finish = (): void => {
    if (settled) {
      return
    }
    settled = true
    try {
      fs.closeSync(file)
    } catch (_error) {
    }
  }
  // AVPlayer 只能在 initialized 态 prepare、prepared 态 play，顺序写死，否则报
  // "current state is not stopped or initialized, unsupport prepare operation"。
  await new Promise<void>((resolve, reject) => {
    player.on('stateChange', (state: string) => {
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
        finish()
        resolve()
        return
      }
      // stop()/release() 之后不会再有 completed，必须在这里收尾，否则 speak() 永远挂着。
      if (state === 'stopped' || state === 'idle') {
        finish()
        resolve()
      }
    })
    player.on('error', (err: Error) => {
      finish()
      reject(err)
    })
    player.fdSrc = { fd: file.fd, length: fs.statSync(path).size }
  })
  if (activePlayer === player) {
    await stopActivePlayer()
  } else {
    try {
      await player.release()
    } catch (_error) {
    }
  }
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
    this.wavPath = `${ctx.filesDir}/tts-out.wav`
    this.ready = (async (): Promise<void> => {
      const base = await ensureModelFiles(ctx, modelDir)
      const h = await sherpa.createAsync({
        acousticModel: cfg.acousticModel ?? `${base}/${DEFAULT_ACOUSTIC}`,
        vocoder: cfg.vocoder ?? `${base}/${DEFAULT_VOCODER}`,
        lexicon: cfg.lexicon ?? `${base}/${DEFAULT_LEXICON}`,
        tokens: cfg.tokens ?? `${base}/${DEFAULT_TOKENS}`,
        ruleFsts: ruleFstsArg(base),
        noiseScale: cfg.noiseScale ?? DEFAULT_NOISE_SCALE,
        lengthScale: cfg.lengthScale ?? DEFAULT_LENGTH_SCALE,
        numThreads: cfg.numThreads ?? DEFAULT_NUM_THREADS
      })
      if (h === 0) {
        throw new Error('RtcTtsController: sherpa.createAsync failed')
      }
      this.handle = h
    })()
    return this.ready
  }

  async speak(text: string): Promise<void> {
    if (!text) {
      return
    }
    if (!this.ready) {
      throw new Error('RtcTtsController: not initialized')
    }
    const generation = this.generation
    const prev = this.speaking ?? Promise.resolve()
    this.speaking = prev.catch(() => undefined).then(async (): Promise<void> => {
      // 合成要几秒，期间点"停止"必须真的不出声，所以每个检查点都比一次代次。
      if (generation !== this.generation) {
        return
      }
      await this.ready
      const generated = await sherpa.generateAsync(this.handle, text, 0, 1.0)
      if (generation !== this.generation) {
        return
      }
      if (!generated || generated.sampleRate === 0 || generated.samples.length === 0) {
        return
      }
      writeWav(this.wavPath, generated.samples, generated.sampleRate)
      await playWav(this.wavPath)
    })
    return this.speaking
  }

  async stop(): Promise<void> {
    this.generation++
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
