import { MediaStreamTrack, NativeVideoRenderer } from 'libohos_webrtc.so'
import { Logging } from './Logging'

const TAG: string = '[RtcVideoRenderController]'

export enum ScalingMode { Fill, AspectFill, AspectFit }

export class VideoRenderController extends XComponentController {
  private renderer: NativeVideoRenderer = new NativeVideoRenderer()

  setVideoTrack(track: MediaStreamTrack | null): void {
    this.renderer.setVideoTrack(track)
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
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    Logging.d(TAG, 'onSurfaceChanged surfaceId: ' + surfaceId)
    Logging.d(TAG, 'onSurfaceChanged rect: ' + rect)
  }

  onSurfaceDestroyed(surfaceId: string): void {
    Logging.d(TAG, 'onSurfaceDestroyed surfaceId: ' + surfaceId)
    this.renderer.release()
  }
}
