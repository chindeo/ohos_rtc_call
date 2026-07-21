import { MediaStreamTrack, NativeVideoRenderer } from 'libohos_webrtc.so'
import { Logging } from './Logging'

const TAG: string = '[RtcVideoRenderController]'

export enum ScalingMode { Fill, AspectFill, AspectFit }

export class VideoRenderController extends XComponentController {
  private renderer: NativeVideoRenderer = new NativeVideoRenderer()
  private track: MediaStreamTrack | null = null
  private surfaceReady: boolean = false
  private mirror: boolean | null = null
  private mirrorVertically: boolean | null = null
  private scalingMode: ScalingMode | null = null

  setVideoTrack(track: MediaStreamTrack | null): void {
    this.track = track
    Logging.d(TAG, 'setVideoTrack surfaceReady=' + this.surfaceReady +
      ' readyState=' + (track?.readyState || '') +
      ' id=' + (track?.id || ''))
    if (this.surfaceReady) {
      this.renderer.setVideoTrack(track)
    }
  }

  setMirror(mirror: boolean): void {
    this.mirror = mirror
    this.renderer.setMirror(mirror)
  }

  setMirrorVertically(mirrorVertically: boolean): void {
    this.mirrorVertically = mirrorVertically
    this.renderer.setMirrorVertically(mirrorVertically)
  }

  setScalingMode(mode: ScalingMode): void {
    this.scalingMode = mode
    this.renderer.setScalingMode(mode)
  }

  onSurfaceCreated(surfaceId: string): void {
    Logging.d(TAG, 'onSurfaceCreated surfaceId: ' + surfaceId)
    this.renderer.init(surfaceId)
    this.applyRendererSettings()
    this.surfaceReady = true
    if (this.track && this.track.readyState === 'live') {
      Logging.d(TAG, 'rebind cached track after surface created readyState=' +
        (this.track.readyState || '') +
        ' id=' + (this.track.id || ''))
      this.renderer.setVideoTrack(this.track)
    } else if (this.track) {
      Logging.w(TAG, 'skip rebind ended track after surface created readyState=' +
        (this.track.readyState || '') +
        ' id=' + (this.track.id || ''))
    }
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    Logging.d(TAG, 'onSurfaceChanged surfaceId: ' + surfaceId)
    Logging.d(TAG, 'onSurfaceChanged rect: ' + rect)
  }

  onSurfaceDestroyed(surfaceId: string): void {
    Logging.d(TAG, 'onSurfaceDestroyed surfaceId: ' + surfaceId)
    this.surfaceReady = false
    this.renderer.setVideoTrack(null)
    this.renderer.release()
    this.renderer = new NativeVideoRenderer()
  }

  private applyRendererSettings(): void {
    if (this.mirror !== null) {
      this.renderer.setMirror(this.mirror)
    }
    if (this.mirrorVertically !== null) {
      this.renderer.setMirrorVertically(this.mirrorVertically)
    }
    if (this.scalingMode !== null) {
      this.renderer.setScalingMode(this.scalingMode)
    }
  }
}
