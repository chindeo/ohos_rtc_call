import { describe, it, expect } from '@ohos/hypium'
import webrtc from '../src/main/ets/webrtc/OhosWebRtc'
import {
  VideoRenderController,
  VideoRendererAdapter
} from '../src/main/ets/webrtc/ohos/VideoRenderController'

class MemoryNativeVideoRenderer implements VideoRendererAdapter {
  surfaceId: string = ''
  releaseCount: number = 0

  init(surfaceId: string): void {
    this.surfaceId = surfaceId
  }

  setVideoTrack(_track: webrtc.MediaStreamTrack | null): void {
  }

  setMirror(_mirror: boolean): void {
  }

  setMirrorVertically(_mirrorVertically: boolean): void {
  }

  setScalingMode(_mode: number): void {
  }

  release(): void {
    this.releaseCount += 1
  }
}

class FailingDetachVideoRenderer extends MemoryNativeVideoRenderer {
  setVideoTrack(_track: webrtc.MediaStreamTrack | null): void {
    throw new Error('detach failed')
  }
}

export default function rtcVideoRenderControllerTest() {
  describe('RtcVideoRenderController', () => {
    it('ignores stale surface destroy and releases each renderer once', 0, () => {
      const renderers: MemoryNativeVideoRenderer[] = []
      const controller = new VideoRenderController(() => {
        const renderer = new MemoryNativeVideoRenderer()
        renderers.push(renderer)
        return renderer
      })

      controller.onSurfaceCreated('surface-a')
      controller.onSurfaceCreated('surface-b')
      expect(renderers.length).assertEqual(2)
      expect(renderers[0].releaseCount).assertEqual(1)
      expect(renderers[1].releaseCount).assertEqual(0)

      controller.onSurfaceDestroyed('surface-a')
      expect(renderers[1].releaseCount).assertEqual(0)

      controller.onSurfaceDestroyed('surface-b')
      controller.onSurfaceDestroyed('surface-b')
      controller.deactivate()
      expect(renderers[1].releaseCount).assertEqual(1)
    })

    it('releases renderer after detach failure', 0, () => {
      const renderer = new FailingDetachVideoRenderer()
      const controller = new VideoRenderController(() => renderer)

      controller.onSurfaceCreated('surface-a')
      controller.deactivate()

      expect(renderer.releaseCount).assertEqual(1)
    })
  })
}
