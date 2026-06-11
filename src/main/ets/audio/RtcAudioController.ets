import webrtc from '@ohos/webrtc'
import audio from '@ohos.multimedia.audio'
import fs from '@ohos.file.fs'
import { RtcCallDiagnosticsOptions } from '../model/RtcCallConfig'
import { RtcWebRtcVideoSourceOptions } from '../webrtc/RtcWebRtcConfig'

export interface RtcLocalAudioOptions {
  trackId: string
  echoCancellation?: boolean
  noiseSuppression?: boolean
}

export interface RtcLocalVideoOptions extends RtcWebRtcVideoSourceOptions {
  trackId: string
  isScreencast?: boolean
}

export interface RtcLocalMediaOptions {
  audio: RtcLocalAudioOptions
  video?: RtcLocalVideoOptions
}

export interface RtcVideoRendererAdapter {
  setVideoTrack(videoTrack: webrtc.MediaStreamTrack | null): void
}

export interface RtcAudioSampleStats {
  count: number
  sampleRate: number
  channelCount: number
  audioFormat: number
  byteLength: number
  nonZeroBytes: number
}

export interface RtcMediaDiagnosticsOptions extends RtcCallDiagnosticsOptions {
  aecDumpDirectory?: string
  aecDumpFilePrefix?: string
  onAudioSampleStats?: (stats: RtcAudioSampleStats) => void
  onLog?: (message: string) => void
  onError?: (message: string) => void
}

export interface RtcMediaResourceSnapshot {
  ready: boolean
  hasAudioDeviceModule: boolean
  hasPeerConnectionFactory: boolean
  hasLocalAudioTrack: boolean
  hasLocalVideoTrack: boolean
  hasRemoteAudioTrack: boolean
  hasRemoteVideoTrack: boolean
  localAudioTrackId: string
  localVideoTrackId: string
  remoteAudioTrackId: string
  remoteVideoTrackId: string
  muted: boolean
  aecDumpStarted: boolean
  aecDumpPath: string
  audioSampleCount: number
}

export class RtcAudioController {
  private adm?: webrtc.AudioDeviceModule
  private pcf?: webrtc.PeerConnectionFactory
  private localAudioSource?: webrtc.AudioSource
  private localAudioTrack?: webrtc.MediaStreamTrack
  private localVideoSource?: webrtc.VideoSource
  private localVideoTrack?: webrtc.MediaStreamTrack
  private remoteAudioTrack?: webrtc.MediaStreamTrack
  private remoteVideoTrack?: webrtc.MediaStreamTrack
  private localVideoRenderer?: RtcVideoRendererAdapter
  private remoteVideoRenderer?: RtcVideoRendererAdapter
  private muted: boolean = false
  private diagnostics: RtcMediaDiagnosticsOptions = {}
  private aecDumpFile?: fs.File
  private aecDumpPath: string = ''
  private audioSampleCount: number = 0

  configureDiagnostics(options: RtcMediaDiagnosticsOptions): void {
    this.diagnostics = options
    if (this.adm) {
      this.bindDiagnostics()
    }
  }

  ensureReady(): boolean {
    this.createAudioDeviceModule()
    this.createPeerConnectionFactory()
    return !!this.pcf
  }

  getPeerConnectionFactory(): webrtc.PeerConnectionFactory | undefined {
    this.ensureReady()
    return this.pcf
  }

  getLocalAudioTrack(): webrtc.MediaStreamTrack | undefined {
    return this.localAudioTrack
  }

  getLocalVideoTrack(): webrtc.MediaStreamTrack | undefined {
    return this.localVideoTrack
  }

  getRemoteAudioTrack(): webrtc.MediaStreamTrack | undefined {
    return this.remoteAudioTrack
  }

  getRemoteVideoTrack(): webrtc.MediaStreamTrack | undefined {
    return this.remoteVideoTrack
  }

  getAudioDeviceModule(): webrtc.AudioDeviceModule | undefined {
    return this.adm
  }

  getSnapshot(): RtcMediaResourceSnapshot {
    return {
      ready: !!this.pcf,
      hasAudioDeviceModule: !!this.adm,
      hasPeerConnectionFactory: !!this.pcf,
      hasLocalAudioTrack: !!this.localAudioTrack,
      hasLocalVideoTrack: !!this.localVideoTrack,
      hasRemoteAudioTrack: !!this.remoteAudioTrack,
      hasRemoteVideoTrack: !!this.remoteVideoTrack,
      localAudioTrackId: this.localAudioTrack?.id || '',
      localVideoTrackId: this.localVideoTrack?.id || '',
      remoteAudioTrackId: this.remoteAudioTrack?.id || '',
      remoteVideoTrackId: this.remoteVideoTrack?.id || '',
      muted: this.muted,
      aecDumpStarted: !!this.aecDumpFile,
      aecDumpPath: this.aecDumpPath,
      audioSampleCount: this.audioSampleCount
    }
  }

  prepareLocalAudio(options: RtcLocalAudioOptions): webrtc.MediaStreamTrack | undefined {
    if (!this.pcf) {
      this.ensureReady()
    }
    if (!this.pcf) {
      return undefined
    }
    if (this.localAudioTrack && this.localAudioTrack.readyState !== 'live') {
      this.releaseLocalAudio()
    }
    this.localAudioSource = this.pcf.createAudioSource({
      echoCancellation: options.echoCancellation !== false,
      noiseSuppression: options.noiseSuppression !== false
    })
    this.localAudioTrack = this.pcf.createAudioTrack(options.trackId, this.localAudioSource)
    this.applyMute()
    return this.localAudioTrack
  }

  prepareLocalVideo(options: RtcLocalVideoOptions): webrtc.MediaStreamTrack | undefined {
    if (!this.pcf) {
      this.ensureReady()
    }
    if (!this.pcf) {
      return undefined
    }
    if (this.localVideoTrack && this.localVideoTrack.readyState !== 'live') {
      this.releaseLocalVideo()
    }
    this.localVideoSource = this.pcf.createVideoSource({
      width: options.width,
      height: options.height,
      frameRate: options.frameRate,
      facingMode: options.facingMode
    }, options.isScreencast === true)
    this.localVideoTrack = this.pcf.createVideoTrack(options.trackId, this.localVideoSource)
    this.localVideoTrack.enabled = true
    this.bindLocalVideoRenderer(this.localVideoRenderer)
    return this.localVideoTrack
  }

  prepareLocalMedia(options: RtcLocalMediaOptions): boolean {
    const audioTrack = this.prepareLocalAudio(options.audio)
    if (!audioTrack) {
      return false
    }
    if (options.video) {
      return !!this.prepareLocalVideo(options.video)
    }
    return true
  }

  setMuted(muted: boolean): void {
    this.muted = muted
    this.applyMute()
  }

  isMuted(): boolean {
    return this.muted
  }

  bindLocalVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    this.localVideoRenderer = renderer
    if (!renderer) {
      return
    }
    try {
      renderer.setVideoTrack(this.localVideoTrack || null)
    } catch (error) {
      this.logError('bind local video renderer error: ' + JSON.stringify(error))
    }
  }

  bindRemoteVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    this.remoteVideoRenderer = renderer
    if (!renderer) {
      return
    }
    try {
      renderer.setVideoTrack(this.remoteVideoTrack || null)
    } catch (error) {
      this.logError('bind remote video renderer error: ' + JSON.stringify(error))
    }
  }

  setRemoteAudioTrack(track?: webrtc.MediaStreamTrack): void {
    this.remoteAudioTrack = track
  }

  setRemoteVideoTrack(track?: webrtc.MediaStreamTrack): void {
    this.remoteVideoTrack = track
    if (!this.remoteVideoRenderer) {
      return
    }
    try {
      this.remoteVideoRenderer.setVideoTrack(track || null)
    } catch (error) {
      this.logError('bind remote video track error: ' + JSON.stringify(error))
    }
  }

  addLocalTracks(peerConnection: webrtc.RTCPeerConnection): number {
    let count = 0
    if (this.localAudioTrack) {
      peerConnection.addTrack(this.localAudioTrack)
      count += 1
    }
    if (this.localVideoTrack) {
      peerConnection.addTrack(this.localVideoTrack)
      count += 1
    }
    return count
  }

  releaseLocalAudio(): void {
    const track = this.localAudioTrack
    if (track) {
      try {
        track.enabled = false
        track.stop()
      } catch (_error) {
      }
    }
    this.localAudioTrack = undefined
    if (this.localAudioSource) {
      this.localAudioSource = undefined
    }
  }

  releaseLocalVideo(): void {
    const track = this.localVideoTrack
    if (track) {
      try {
        track.enabled = false
        track.stop()
      } catch (_error) {
      }
    }
    this.localVideoTrack = undefined
    if (this.localVideoSource) {
      this.localVideoSource = undefined
    }
    if (this.localVideoRenderer) {
      try {
        this.localVideoRenderer.setVideoTrack(null)
      } catch (_error) {
      }
    }
  }

  releaseLocalMedia(): void {
    this.releaseLocalAudio()
    this.releaseLocalVideo()
  }

  clearRemoteMedia(): void {
    this.remoteAudioTrack = undefined
    this.remoteVideoTrack = undefined
    if (this.remoteVideoRenderer) {
      try {
        this.remoteVideoRenderer.setVideoTrack(null)
      } catch (_error) {
      }
    }
  }

  startAecDump(reason: string = 'manual'): boolean {
    if (!this.diagnostics.enableAecDump || !this.pcf || this.aecDumpFile) {
      return false
    }
    if (!this.diagnostics.aecDumpDirectory) {
      this.logError('start aec dump skipped: empty directory')
      return false
    }
    try {
      const prefix = this.diagnostics.aecDumpFilePrefix || 'rtc_call_debug'
      const path = `${this.diagnostics.aecDumpDirectory}/${prefix}_${Date.now()}.aecdump`
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      const ok = this.pcf.startAecDump(file.fd, -1)
      if (!ok) {
        fs.closeSync(file)
        this.logError(`start aec dump failed reason=${reason} path=${path}`)
        return false
      }
      this.aecDumpFile = file
      this.aecDumpPath = path
      this.log(`start aec dump reason=${reason} path=${path}`)
      return true
    } catch (error) {
      this.logError(`start aec dump error reason=${reason}: ${JSON.stringify(error)}`)
      return false
    }
  }

  stopAecDump(reason: string = 'manual'): void {
    const file = this.aecDumpFile
    if (!file) {
      return
    }
    const path = this.aecDumpPath
    try {
      this.pcf?.stopAecDump()
    } catch (error) {
      this.logError(`stop aec dump error reason=${reason} path=${path}: ${JSON.stringify(error)}`)
    }
    try {
      fs.closeSync(file)
    } catch (error) {
      this.logError(`close aec dump error reason=${reason} path=${path}: ${JSON.stringify(error)}`)
    }
    this.aecDumpFile = undefined
    this.aecDumpPath = ''
    this.log(`stop aec dump reason=${reason} path=${path}`)
  }

  cleanupRtcCallResources(reason: string = 'cleanup'): void {
    this.releaseAll(reason)
  }

  releaseAll(reason: string = 'release all'): void {
    this.releaseLocalMedia()
    this.clearRemoteMedia()
    this.stopAecDump(reason)
    if (this.adm) {
      this.clearDiagnostics()
      try {
        this.adm.release()
      } catch (_error) {
      }
      this.adm = undefined
    }
    this.pcf = undefined
    this.audioSampleCount = 0
  }

  private createAudioDeviceModule(): void {
    if (this.adm) {
      return
    }
    this.adm = new webrtc.AudioDeviceModule({
      useStereoInput: false,
      useStereoOutput: false,
      rendererUsage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION
    })
    this.bindDiagnostics()
  }

  private createPeerConnectionFactory(): void {
    if (this.pcf) {
      return
    }
    const audioProcessingFactory = new webrtc.AudioProcessingFactory()
    const audioProcessing = audioProcessingFactory.create()
    this.pcf = new webrtc.PeerConnectionFactory({
      adm: this.adm,
      audioProcessing: audioProcessing
    })
    webrtc.PeerConnectionFactory.setDefault(this.pcf)
    this.startAecDump('create pcf')
  }

  private applyMute(): void {
    if (this.localAudioTrack) {
      this.localAudioTrack.enabled = !this.muted
    }
    if (!this.adm) {
      return
    }
    try {
      this.adm.setMicrophoneMute(this.muted)
    } catch (_error) {
    }
  }

  private bindDiagnostics(): void {
    if (!this.adm) {
      return
    }
    this.adm.oncapturererror = (event: webrtc.AudioErrorEvent) => {
      this.logError('audio capturer error: ' + JSON.stringify(event))
    }
    this.adm.oncapturerstatechange = (event: webrtc.AudioStateChangeEvent) => {
      this.log('audio capturer state=' + event.state)
    }
    this.adm.onrenderererror = (event: webrtc.AudioErrorEvent) => {
      this.logError('audio renderer error: ' + JSON.stringify(event))
    }
    this.adm.onrendererstatechange = (event: webrtc.AudioStateChangeEvent) => {
      this.log('audio renderer state=' + event.state)
    }
    if (this.diagnostics.enableAudioSampleStats) {
      this.adm.oncapturersamplesready = (event: webrtc.AudioCapturerSamplesReadyEvent) => {
        this.audioSampleCount += 1
        const samples = event.samples
        const stats: RtcAudioSampleStats = {
          count: this.audioSampleCount,
          sampleRate: samples.sampleRate,
          channelCount: samples.channelCount,
          audioFormat: samples.audioFormat,
          byteLength: samples.data.byteLength,
          nonZeroBytes: RtcAudioController.countNonZeroArrayBufferBytes(samples.data)
        }
        this.diagnostics.onAudioSampleStats?.(stats)
        if (stats.count <= 5 || stats.count % 50 === 0) {
          this.log(`audio capturer samples count=${stats.count} sampleRate=${stats.sampleRate}` +
            ` channels=${stats.channelCount} format=${stats.audioFormat}` +
            ` bytes=${stats.byteLength} nonZeroBytes=${stats.nonZeroBytes}`)
        }
      }
    } else {
      this.adm.oncapturersamplesready = (_event: webrtc.AudioCapturerSamplesReadyEvent) => {}
    }
  }

  private clearDiagnostics(): void {
    if (!this.adm) {
      return
    }
    this.adm.oncapturererror = (_event: webrtc.AudioErrorEvent) => {}
    this.adm.oncapturerstatechange = (_event: webrtc.AudioStateChangeEvent) => {}
    this.adm.oncapturersamplesready = (_event: webrtc.AudioCapturerSamplesReadyEvent) => {}
    this.adm.onrenderererror = (_event: webrtc.AudioErrorEvent) => {}
    this.adm.onrendererstatechange = (_event: webrtc.AudioStateChangeEvent) => {}
  }

  static countNonZeroArrayBufferBytes(data?: ArrayBuffer): number {
    if (!data) {
      return 0
    }
    const bytes = new Uint8Array(data)
    let count = 0
    for (let i = 0; i < bytes.length; i += 1) {
      if (bytes[i] !== 0) {
        count += 1
      }
    }
    return count
  }

  private log(message: string): void {
    this.diagnostics.onLog?.(message)
  }

  private logError(message: string): void {
    this.diagnostics.onError?.(message)
  }
}
