import fs from '@ohos.file.fs'

/**
 * 单声道 16bit PCM 的最小 WAV 封装：端上合成的提示音先落文件，再交给 AVPlayer 播放。
 * 离线 TTS 那份在 `@chindeo/ohos-tts-sherpa` 里，两个包各自带一份同一个头部拼装。
 */
export function writeWavFile(path: string, samples: Float32Array, sampleRate: number): void {
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
