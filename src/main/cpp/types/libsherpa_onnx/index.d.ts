export interface SherpaTtsConfig {
  acousticModel: string
  vocoder: string
  lexicon: string
  tokens: string
  noiseScale?: number
  lengthScale?: number
  numThreads?: number
  ruleFsts?: string
}

export interface SherpaTtsAudio {
  sampleRate: number
  samples: Float32Array
}

export function create(config: SherpaTtsConfig): number
export function createAsync(config: SherpaTtsConfig): Promise<number>
export function destroy(handle: number): void
export function generate(handle: number, text: string, sid: number, speed: number): SherpaTtsAudio
export function generateAsync(handle: number, text: string, sid: number, speed: number): Promise<SherpaTtsAudio>
export function sampleRate(handle: number): number
export function numSpeakers(handle: number): number
