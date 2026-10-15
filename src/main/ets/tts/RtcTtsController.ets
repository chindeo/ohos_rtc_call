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
const DEFAULT_NOISE_SCALE = 0.33
const DEFAULT_LENGTH_SCALE = 1.0
const DEFAULT_NUM_THREADS = 4

let activePlayer: media.AVPlayer | undefined = undefined

async function ensureModelFiles(ctx: common.Context, modelDir: string): Promise<string> {
  const base = `${ctx.filesDir}/${modelDir}`
  if (!fs.accessSync(base)) {
    fs.mkdirSync(base, true)
  }
  const names = [DEFAULT_ACOUSTIC, DEFAULT_VOCODER, DEFAULT_LEXICON, DEFAULT_TOKENS]
  for (const name of names) {
    const dest = `${base}/${name}`
    if (fs.accessSync(dest)) {
      continue
    }
    const content = await ctx.resourceManager.getRawFileContent(`${modelDir}/${name}`)
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    fs.writeSync(file.fd, content.buffer as ArrayBuffer)
    fs.closeSync(file)
  }
  return base
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
  await new Promise<void>((resolve, reject) => {
    player.on('stateChange', (state: string) => {
      if (state === 'completed') {
        finish()
        resolve()
      }
    })
    player.on('error', (err: Error) => {
      finish()
      reject(err)
    })
    player.url = `fd://${file.fd}`
    player.prepare().catch((err: Error) => {
      finish()
      reject(err)
    })
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
    const prev = this.speaking ?? Promise.resolve()
    this.speaking = prev.catch(() => undefined).then(async (): Promise<void> => {
      await this.ready
      const generated = await sherpa.generateAsync(this.handle, text, 0, 1.0)
      if (!generated || generated.sampleRate === 0 || generated.samples.length === 0) {
        return
      }
      writeWav(this.wavPath, generated.samples, generated.sampleRate)
      await playWav(this.wavPath)
    })
    return this.speaking
  }

  async stop(): Promise<void> {
    await stopActivePlayer()
  }

  async release(): Promise<void> {
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
