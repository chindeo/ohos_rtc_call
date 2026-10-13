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
  // 一个页面里同时存在本地预览、共享远端和每路会话远端三类渲染器，
  // 不带标签的日志无法判断轨交给了哪一个。
  private readonly label: string

  constructor(rendererFactory?: () => VideoRendererAdapter, label: string = 'video') {
    super()
    this.rendererFactory = rendererFactory || (() => new NativeVideoRenderer())
    this.label = label
  }

  private describe(message: string): string {
    return '[' + this.label + '] ' + message
  }

  setVideoTrack(track: MediaStreamTrack | null): void {
    this.track = track
    Logging.d(TAG, this.describe('setVideoTrack surfaceReady=' + this.surfaceReady +
      ' generation=' + this.surfaceGeneration +
      ' readyState=' + (track?.readyState || '') +
      ' id=' + (track?.id || '')))
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
      Logging.d(TAG, this.describe('ignore duplicate onSurfaceCreated surfaceId: ' + surfaceId))
      return
    }
    this.deactivate()
    const generation = this.surfaceGeneration + 1
    this.surfaceGeneration = generation
    Logging.d(TAG, this.describe('onSurfaceCreated surfaceId: ' + surfaceId + ' generation=' + generation))
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
      Logging.d(TAG, this.describe('rebind cached track after surface created readyState=' +
        (this.track.readyState || '') +
        ' id=' + (this.track.id || '')))
      renderer.setVideoTrack(this.track)
    } else if (this.track) {
      Logging.w(TAG, this.describe('skip rebind ended track after surface created readyState=' +
        (this.track.readyState || '') +
        ' id=' + (this.track.id || '')))
    }
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    Logging.d(TAG, this.describe('onSurfaceChanged surfaceId: ' + surfaceId))
    Logging.d(TAG, this.describe('onSurfaceChanged rect: ' + rect))
  }

  onSurfaceDestroyed(surfaceId: string): void {
    if (!this.surfaceReady || surfaceId !== this.activeSurfaceId) {
      Logging.d(TAG, this.describe('ignore stale onSurfaceDestroyed surfaceId: ' + surfaceId +
        ' activeSurfaceId=' + this.activeSurfaceId +
        ' generation=' + this.surfaceGeneration))
      return
    }
    Logging.d(TAG, this.describe('onSurfaceDestroyed surfaceId: ' + surfaceId +
      ' generation=' + this.surfaceGeneration))
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
    } catch (error) {
      Logging.w(TAG, this.describe('deactivate detach track failed generation=' + generation +
        ' error=' + JSON.stringify(error)))
    }
    try {
      renderer?.release()
    } catch (error) {
      Logging.w(TAG, this.describe('deactivate release failed generation=' + generation +
        ' error=' + JSON.stringify(error)))
    }
    Logging.d(TAG, this.describe('deactivate renderer generation=' + generation))
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
