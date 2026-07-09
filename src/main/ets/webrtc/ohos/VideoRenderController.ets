import { MediaStreamTrack, NativeVideoRenderer } from 'libohos_webrtc.so'
import { Logging } from './Logging'

const TAG: string = '[RtcVideoRenderController]'

export enum ScalingMode { Fill, AspectFill, AspectFit }

export class VideoRenderController extends XComponentController {
  private renderer: NativeVideoRenderer = new NativeVideoRenderer()
  private track: MediaStreamTrack | null = null
  private surfaceReady: boolean = false

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
    this.renderer.setMirror(mirror)
  }

  setMirrorVertically(mirrorVertically: boolean): void {
    this.renderer.setMirrorVertically(mirrorVertically)
  }

  setScalingMode(mode: ScalingMode): void {
    this.renderer.setScalingMode(mode)
  }

  onSurfaceCreated(surfaceId: string): void {
    Logging.d(TAG, 'onSurfaceCreated surfaceId: ' + surfaceId)
    this.renderer.init(surfaceId)
    this.surfaceReady = true
    if (this.track) {
      Logging.d(TAG, 'rebind cached track after surface created readyState=' +
        (this.track.readyState || '') +
        ' id=' + (this.track.id || ''))
      this.renderer.setVideoTrack(this.track)
    }
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    Logging.d(TAG, 'onSurfaceChanged surfaceId: ' + surfaceId)
    Logging.d(TAG, 'onSurfaceChanged rect: ' + rect)
  }

  onSurfaceDestroyed(surfaceId: string): void {
    Logging.d(TAG, 'onSurfaceDestroyed surfaceId: ' + surfaceId)
    this.surfaceReady = false
    this.renderer.release()
  }
}
