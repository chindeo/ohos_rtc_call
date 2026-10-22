import webrtc from '../webrtc/OhosWebRtc'
import audio from '@ohos.multimedia.audio'
import fs from '@ohos.file.fs'
import { RtcCallDiagnosticsOptions } from '../model/RtcCallConfig'
import { RtcWebRtcVideoSourceOptions } from '../webrtc/RtcWebRtcConfig'
import { RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS, RtcVideoCaptureStopGate } from './RtcVideoCaptureStopGate'
import { RtcDeviceVendorResolver } from '../device/RtcDeviceVendor'

export interface RtcLocalAudioOptions {
  trackId: string
  echoCancellation?: boolean
  noiseSuppression?: boolean
}

export interface RtcLocalVideoOptions extends RtcWebRtcVideoSourceOptions {
  trackId: string
  isScreencast?: boolean
  externalNv21?: boolean
}

export interface RtcLocalMediaOptions {
  audio: RtcLocalAudioOptions
  video?: RtcLocalVideoOptions
}

export interface RtcVideoRendererAdapter {
  setVideoTrack(videoTrack: webrtc.MediaStreamTrack | null): void
  deactivate?(): void
}

export interface RtcAudioSampleStats {
  count: number
  sampleRate: number
  channelCount: number
  audioFormat: number
  byteLength: number
  nonZeroBytes: number
}

export interface RtcVideoCapturerFailure {
  code: number
  stage: string
  message: string
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
  private localVideoUsesExternalFrames: boolean = false
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
  private localVideoCapturerFailureHandler?: (failure: RtcVideoCapturerFailure) => void
  private localVideoCapturerReadyHandler?: () => void
  private localVideoGeneration: number = 0
  private localVideoStopGate: RtcVideoCaptureStopGate = new RtcVideoCaptureStopGate()

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

  setLocalVideoCapturerFailureHandler(
    handler?: (failure: RtcVideoCapturerFailure) => void
  ): void {
    this.localVideoCapturerFailureHandler = handler
  }

  setLocalVideoCapturerReadyHandler(handler?: () => void): void {
    this.localVideoCapturerReadyHandler = handler
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
      // NS 必须同时给到约束这一层：只改 APM 工厂会被引擎用这里的值写回（webrtc_voice_engine.cc:615），
      // 实测 CONFIG 事件证实过。.so 现在把 NS 等级默认成 kVeryHigh，这里只负责"开"。
      noiseSuppression: options.noiseSuppression !== false,
      // 引擎在没人指定时默认开 AGC（webrtc_voice_engine.cc:443）。床旁外放时 AGC 会在对方
      // 静音段抬增益、把房间里的回声整段放大，而且它会让"APM 输入/输出电平比"再也读不出
      // 消除量。取证和听感都要它关掉，所以在这里显式压掉，不能靠默认值。
      autoGainControl: false
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
    if (this.localVideoTrack?.readyState === 'live') {
      this.log('reuse_video_track trackId=' + (this.localVideoTrack.id || ''))
      return this.localVideoTrack
    }
    const sourceType = options.externalNv21 === true ? 'external-nv21' : 'camera-kit'
    const generation = this.localVideoGeneration + 1
    this.localVideoGeneration = generation
    this.log('create_video_source begin sourceType=' + sourceType +
      ' generation=' + generation +
      ' deviceId=' + (options.deviceId || '') + ' width=' + options.width +
      ' height=' + options.height + ' frameRate=' + options.frameRate +
      ' previousStopPending=' + this.localVideoStopGate.isPending() +
      ' previousStopAgeMs=' + this.localVideoStopGate.pendingAgeMs())
    if (options.externalNv21 === true) {
      this.localVideoSource = this.pcf.createExternalVideoSource(options.frameRate)
      this.localVideoUsesExternalFrames = true
    } else {
      const constraints: webrtc.MediaTrackConstraints = {
        width: options.width,
        height: options.height,
        frameRate: options.frameRate
      }
      if (options.facingMode) {
        constraints.facingMode = options.facingMode
      }
      if (options.deviceId) {
        constraints.deviceId = options.deviceId
      }
      this.localVideoSource = this.pcf.createVideoSource(constraints, options.isScreencast === true)
      this.localVideoUsesExternalFrames = false
    }
    const source = this.localVideoSource
    source.oncapturerstarted = (event: webrtc.VideoCapturerStartedEvent) => {
      if (this.localVideoSource !== source || this.localVideoGeneration !== generation) {
        this.log('ignore stale video_capturer_started generation=' + generation +
          ' currentGeneration=' + this.localVideoGeneration)
        return
      }
      if (event.success) {
        this.log('video_capturer_started success=true generation=' + generation)
        this.localVideoCapturerReadyHandler?.()
        return
      }
      const failure: RtcVideoCapturerFailure = {
        code: event.code ?? -1,
        stage: event.stage || 'unknown',
        message: event.message || 'Video capturer failed'
      }
      this.logError('video_capturer_started success=false code=' + failure.code +
        ' stage=' + failure.stage + ' generation=' + generation + ' message=' + failure.message)
      setTimeout(() => {
        if (this.localVideoSource !== source || this.localVideoGeneration !== generation) {
          this.log('ignore deferred stale video_capturer_failure generation=' + generation +
            ' currentGeneration=' + this.localVideoGeneration)
          return
        }
        this.localVideoCapturerFailureHandler?.(failure)
      }, 0)
    }
    this.log('create_video_source success sourceType=' + sourceType +
      ' generation=' + generation + ' deviceId=' + (options.deviceId || ''))
    this.log('create_video_track begin trackId=' + options.trackId)
    this.localVideoTrack = this.pcf.createVideoTrack(options.trackId, this.localVideoSource)
    this.log('create_video_track success readyState=' + (this.localVideoTrack.readyState || ''))
    this.localVideoTrack.enabled = true
    this.bindLocalVideoRenderer(this.localVideoRenderer)
    return this.localVideoTrack
  }

  pushLocalVideoNv21Frame(data: Uint8Array, width: number, height: number,
    timestampUs?: number, rotation?: 0 | 90 | 180 | 270): boolean {
    if (!this.localVideoSource || !this.localVideoUsesExternalFrames) {
      return false
    }
    try {
      return this.localVideoSource.pushNv21Frame(data, width, height, timestampUs, rotation)
    } catch (error) {
      this.logError('push external NV21 frame error: ' + JSON.stringify(error))
      return false
    }
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
    const source = this.localVideoSource
    const usesExternalFrames = this.localVideoUsesExternalFrames
    const generation = this.localVideoGeneration
    this.localVideoGeneration += 1
    this.log('release_video begin trackId=' + (track?.id || '') +
      ' readyState=' + (track?.readyState || 'none') +
      ' sourceType=' + (usesExternalFrames ? 'external-nv21' : 'camera-kit') +
      ' generation=' + generation)
    // Arm the stop gate before stopping the track so a capture-stopped callback dispatched while
    // the native release runs below can settle it. External NV21/UVC sources are owned by the
    // host, so their release policy stays unchanged and the window closes immediately.
    const stopToken: number = this.localVideoStopGate.arm()
    if (!source || usesExternalFrames) {
      this.localVideoStopGate.settle(stopToken)
    } else {
      source.oncapturerstarted = null
      source.oncapturerstopped = () => {
        if (this.localVideoStopGate.settle(stopToken)) {
          this.log('video_capturer_stopped generation=' + generation + ' token=' + stopToken)
        }
      }
    }
    if (track) {
      try {
        track.enabled = false
        track.stop()
      } catch (error) {
        this.logError('release_video track stop failed generation=' + generation +
          ' error=' + JSON.stringify(error))
      }
    }
    this.localVideoTrack = undefined
    let nativeReleased = false
    if (source && !usesExternalFrames) {
      try {
        source.release()
        nativeReleased = true
      } catch (error) {
        this.logError('release_video native release failed generation=' + generation +
          ' error=' + JSON.stringify(error))
      }
    }
    this.localVideoSource = undefined
    this.localVideoUsesExternalFrames = false
    this.clearVideoRenderer(this.localVideoRenderer)
    this.log('release_video complete sourceType=' +
      (usesExternalFrames ? 'external-nv21' : 'camera-kit') +
      ' generation=' + generation + ' nativeReleased=' + nativeReleased)
  }

  /**
   * Releases the local video source and waits, within a bounded deadline, for native capture to
   * report that it actually stopped.
   *
   * Callers that create the next video source immediately after releasing must use this instead
   * of the fire-and-forget `releaseLocalVideo()`: creating while the previous capture is still
   * alive makes CameraKit destroy the old session inside `CreateCaptureSession`, which re-locks a
   * non-recursive mutex and wedges camera_service for every later caller on the device.
   *
   * Returns `stopped` when native confirmed quiescence, `quiesced` when there was nothing to
   * wait for, and `timeout` when the confirmation never arrived.
   */
  async releaseLocalVideoAsync(
    timeoutMs: number = RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS
  ): Promise<string> {
    this.releaseLocalVideo()
    const result: string = await this.localVideoStopGate.wait(timeoutMs)
    this.log('release_video wait result=' + result +
      ' stillPending=' + this.localVideoStopGate.isPending() +
      ' pendingAgeMs=' + this.localVideoStopGate.pendingAgeMs() +
      ' timeoutMs=' + timeoutMs)
    return result
  }

  isLocalVideoCaptureQuiesced(): boolean {
    return !this.localVideoStopGate.isPending()
  }

  /**
   * Waits for the most recently released local video source to confirm that capture stopped,
   * without releasing anything itself. Callers about to create a video source use this so
   * CameraKit never sees a new CreateCaptureSession while the previous session is still alive.
   */
  waitForLocalVideoCaptureQuiesced(
    timeoutMs: number = RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS
  ): Promise<string> {
    return this.localVideoStopGate.wait(timeoutMs)
  }

  localVideoCapturePendingAgeMs(): number {
    return this.localVideoStopGate.pendingAgeMs()
  }

  releaseLocalMedia(): void {
    this.releaseLocalAudio()
    this.releaseLocalVideo()
  }

  clearRemoteMedia(): void {
    this.remoteAudioTrack = undefined
    this.remoteVideoTrack = undefined
    this.clearVideoRenderer(this.remoteVideoRenderer)
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
      // 目录由宿主给，可能是第一次用（取证开关现场才打开），不存在就建出来，别让 dump 静默失败。
      if (!fs.accessSync(this.diagnostics.aecDumpDirectory)) {
        fs.mkdirSync(this.diagnostics.aecDumpDirectory, true)
      }
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
    if (this.pcf) {
      this.log(`release peer connection factory owner deferred reason=${reason}`)
    }
    this.pcf = undefined
    if (this.adm) {
      this.clearDiagnostics()
      try {
        this.adm.release()
      } catch (_error) {
      }
      this.adm = undefined
    }
    this.audioSampleCount = 0
  }

  private clearVideoRenderer(renderer?: RtcVideoRendererAdapter): void {
    if (!renderer) {
      return
    }
    try {
      renderer.setVideoTrack(null)
    } catch (_error) {
    }
    try {
      renderer.deactivate?.()
    } catch (_error) {
    }
  }

  private createAudioDeviceModule(): void {
    if (this.adm) {
      return
    }
    const resamplePermille = RtcDeviceVendorResolver.captureResamplePermille()
    const aecStreamDelayMs = RtcDeviceVendorResolver.aecStreamDelayMs()
    this.log(`rtc_capture_resample permille=${resamplePermille} vendor=${RtcDeviceVendorResolver.getStoredVendor()} align=false stream_delay_ms=${aecStreamDelayMs}`)
    this.adm = new webrtc.AudioDeviceModule({
      // MIC keeps the JHC bedside capture on its negotiated 48 kHz; VOICE_COMMUNICATION falls
      // back to 44.1 kHz. The rescale ratio is a fixed device calibration, not the rate probe:
      // the probe compares two delivery rates, while AEC3 needs the waveform time scale, and
      // re-deciding it every 5 s kept the linear filter from ever converging.
      audioSource: audio.SourceType.SOURCE_TYPE_MIC,
      inputSampleRate: 48000,
      // Native default is 16k (kAudioSampleRate_Default). A 16k renderer means AEC3's reference is
      // upsampled out of a 48k APM and then resampled again by the HAL, so capture and playout are
      // not on the same clock domain. Pin playout to the same 48k the capture and APM already use.
      outputSampleRate: 48000,
      captureRateAlign: false,
      captureResamplePermille: resamplePermille,
      aecStreamDelayMs: aecStreamDelayMs,
      useStereoInput: false,
      useStereoOutput: false,
      rendererUsage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION
    })
    // 平台 3A 是"按音频场景给的"：官方文档说通话/语音聊天场景才会做 AEC/ANS/AGC。
    // 应用侧只能读不能设（SDK 里没有 setAudioScene），所以把场景打出来，
    // 用来判"HPAE 那句 scenetype 不支持"到底是场景没切起来，还是这台机器根本没实现。
    try {
      this.log(`rtc_audio_scene ${audio.getAudioManager().getAudioSceneSync()}`)
    } catch (error) {
      this.logError(`rtc_audio_scene read failed ${(error as Error).message}`)
    }
    this.bindDiagnostics()
  }

  private createPeerConnectionFactory(): void {
    if (this.pcf) {
      return
    }
    const audioProcessingFactory = new webrtc.AudioProcessingFactory()
    // 归因取证：把 WebRTC 内部日志接到 hilog（native 一旦安装就按 LS_VERBOSE 全量输出）。
    // 渲染缓冲实际被对齐到多少块、延迟何时变动，只有 AEC3 自己知道，而这代 aecdump 没有 raw 事件。
    // 只在诊断包里开：通话期间每条 RTC_LOG 都会进 hilog，本身会拖慢音频线程。
    webrtc.NativeLogging.enableLogToDebugOutput(1)
    // Upstream leaves echo_canceller.enabled false and only flips it when the getUserMedia
    // constraint reaches WebRtcVoiceEngine::Apply. State the intent here too, and log what was
    // applied, so "AEC off by config" can be told apart from "AEC on but not converging".
    const audioProcessing = audioProcessingFactory.create({
      echoCancellation: true,
      noiseSuppression: true,
      highPassFilter: true,
      autoGainControl: false,
      logWarningOnDelayChanges: true,
      // Off, per the offline m124 A/B: on a synthetic echo the internal matched filter reaches
      // 54.6 dB while external-delay alignment only manages 21.8 dB, so making the reported
      // delay the alignment is not the fix. Keep the internal estimator and feed it a stable clock.
      useExternalDelayEstimator: false
      // 不要在这里打开 exportLinearAecOutput：12:51 接听瞬间 SIGSEGV 就是它。fork 的
      // EchoCanceller3 构造里把 linear_output_block_/sub_frame_view_ 硬写成 num_bands=1，
      // 而本机 APM 跑在 48k（num_bands=3），ProcessCapture 逐 band 写入就越界踩堆。
      // 要拿 AEC3 线性子块得先在 .so 里按 num_bands_ 分配，再回来开这个开关。
    })
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
