import webrtc from '@ohos/webrtc'
import audio from '@ohos.multimedia.audio'
import { RtcCallDiagnosticsOptions } from '../model/RtcCallConfig'

export interface RtcLocalAudioOptions {
  trackId: string
  echoCancellation?: boolean
  noiseSuppression?: boolean
}

export class RtcAudioController {
  private adm?: webrtc.AudioDeviceModule
  private pcf?: webrtc.PeerConnectionFactory
  private localAudioSource?: webrtc.AudioSource
  private localAudioTrack?: webrtc.MediaStreamTrack
  private muted: boolean = false
  private diagnostics: RtcCallDiagnosticsOptions = {}

  configureDiagnostics(options: RtcCallDiagnosticsOptions): void {
    this.diagnostics = options
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

  setMuted(muted: boolean): void {
    this.muted = muted
    this.applyMute()
  }

  isMuted(): boolean {
    return this.muted
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
    this.localAudioSource = undefined
  }

  releaseAll(): void {
    this.releaseLocalAudio()
    if (this.adm) {
      this.clearDiagnostics()
      try {
        this.adm.release()
      } catch (_error) {
      }
      this.adm = undefined
    }
    this.pcf = undefined
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
    this.adm.oncapturererror = (_event: webrtc.AudioErrorEvent) => {}
    this.adm.oncapturerstatechange = (_event: webrtc.AudioStateChangeEvent) => {}
    if (this.diagnostics.enableAudioSampleStats) {
      this.adm.oncapturersamplesready = (_event: webrtc.AudioCapturerSamplesReadyEvent) => {}
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
}
