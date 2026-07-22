import { MediaStreamTrack, NativeVideoRenderer } from 'libohos_webrtc.so'
import { Logging } from './Logging'

const TAG: string = '[RtcVideoRenderController]'

export enum ScalingMode { Fill, AspectFill, AspectFit }

export interface VideoRendererAdapter {
  init(surfaceId: string): void
  setVideoTrack(track: MediaStreamTrack | null): void
  setMirror(mirror: boolean): void
  setMirrorVertically(mirrorVertically: boolean): void
  setScalingMode(mode: number): void
  release(): void
}

export class VideoRenderController extends XComponentController {
  private renderer: VideoRendererAdapter | null = null
  private rendererFactory: () => VideoRendererAdapter
  private track: MediaStreamTrack | null = null
  private surfaceReady: boolean = false
  private activeSurfaceId: string = ''
  private surfaceGeneration: number = 0
  private mirror: boolean | null = null
  private mirrorVertically: boolean | null = null
  private scalingMode: ScalingMode | null = null

  constructor(rendererFactory?: () => VideoRendererAdapter) {
    super()
    this.rendererFactory = rendererFactory || (() => new NativeVideoRenderer())
  }

  setVideoTrack(track: MediaStreamTrack | null): void {
    this.track = track
    Logging.d(TAG, 'setVideoTrack surfaceReady=' + this.surfaceReady +
      ' readyState=' + (track?.readyState || '') +
      ' id=' + (track?.id || ''))
    if (this.surfaceReady && this.renderer) {
      this.renderer.setVideoTrack(track)
    }
  }

  setMirror(mirror: boolean): void {
    this.mirror = mirror
    this.renderer?.setMirror(mirror)
  }

  setMirrorVertically(mirrorVertically: boolean): void {
    this.mirrorVertically = mirrorVertically
    this.renderer?.setMirrorVertically(mirrorVertically)
  }

  setScalingMode(mode: ScalingMode): void {
    this.scalingMode = mode
    this.renderer?.setScalingMode(mode)
  }

  onSurfaceCreated(surfaceId: string): void {
    if (this.surfaceReady && this.activeSurfaceId === surfaceId) {
      Logging.d(TAG, 'ignore duplicate onSurfaceCreated surfaceId: ' + surfaceId)
      return
    }
    this.deactivate()
    const generation = this.surfaceGeneration + 1
    this.surfaceGeneration = generation
    Logging.d(TAG, 'onSurfaceCreated surfaceId: ' + surfaceId + ' generation=' + generation)
    const renderer = this.rendererFactory()
    try {
      renderer.init(surfaceId)
    } catch (error) {
      renderer.release()
      throw error
    }
    this.renderer = renderer
    this.activeSurfaceId = surfaceId
    this.surfaceReady = true
    this.applyRendererSettings()
    if (this.track && this.track.readyState === 'live') {
      Logging.d(TAG, 'rebind cached track after surface created readyState=' +
        (this.track.readyState || '') +
        ' id=' + (this.track.id || ''))
      renderer.setVideoTrack(this.track)
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
    if (!this.surfaceReady || surfaceId !== this.activeSurfaceId) {
      Logging.d(TAG, 'ignore stale onSurfaceDestroyed surfaceId: ' + surfaceId +
        ' activeSurfaceId=' + this.activeSurfaceId +
        ' generation=' + this.surfaceGeneration)
      return
    }
    Logging.d(TAG, 'onSurfaceDestroyed surfaceId: ' + surfaceId +
      ' generation=' + this.surfaceGeneration)
    this.deactivate()
  }

  deactivate(): void {
    const renderer = this.renderer
    if (!renderer && !this.surfaceReady && !this.activeSurfaceId) {
      return
    }
    const generation = this.surfaceGeneration
    this.renderer = null
    this.surfaceReady = false
    this.activeSurfaceId = ''
    try {
      renderer?.setVideoTrack(null)
    } finally {
      renderer?.release()
      Logging.d(TAG, 'deactivate renderer generation=' + generation)
    }
  }

  private applyRendererSettings(): void {
    const renderer = this.renderer
    if (!renderer) {
      return
    }
    if (this.mirror !== null) {
      renderer.setMirror(this.mirror)
    }
    if (this.mirrorVertically !== null) {
      renderer.setMirrorVertically(this.mirrorVertically)
    }
    if (this.scalingMode !== null) {
      renderer.setScalingMode(this.scalingMode)
    }
  }
}
