import { describe, it, expect } from '@ohos/hypium'
import {
  RtcRingtoneChannel,
  RtcRingtoneController,
  RtcRingtoneDriver
} from '../src/main/ets/audio/RtcRingtoneController'

class UrlDriver implements RtcRingtoneDriver {
  incomingCalls: number = 0
  urlCalls: string[] = []

  async playIncoming(): Promise<boolean> {
    this.incomingCalls += 1
    return true
  }

  async playUrl(url: string): Promise<boolean> {
    this.urlCalls.push(url)
    return true
  }

  async stop(): Promise<void> {
  }
}

class LocalOnlyDriver implements RtcRingtoneDriver {
  async playIncoming(): Promise<boolean> {
    return true
  }

  async stop(): Promise<void> {
  }
}

class RefusingDriver implements RtcRingtoneDriver {
  async playIncoming(): Promise<boolean> {
    return false
  }

  async playUrl(_url: string): Promise<boolean> {
    return false
  }

  async stop(): Promise<void> {
  }
}

function controllerWithLogger(logs: string[]): RtcRingtoneController {
  const controller = new RtcRingtoneController()
  controller.configureLogger((message: string) => logs.push(message))
  return controller
}

export default function rtcRingtoneControllerTest() {
  describe('RtcRingtoneController gate reasons', () => {
    it('reports policyDisabled for URL playback while external url gate is closed', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      controller.configureDriver(new UrlDriver())
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m === 'ring_url_gate result=skip reason=policyDisabled channel=webrtc'))
        .assertEqual(true)
    })

    it('reports emptyUrl when the url argument is blank', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true })
      controller.configureDriver(new UrlDriver())
      await controller.playUrl('', RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m.indexOf('reason=emptyUrl') >= 0)).assertEqual(true)
    })

    it('reports noDriver when no driver is configured', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      await controller.playIncoming(RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m.indexOf('ring_local_gate result=skip reason=noDriver') >= 0))
        .assertEqual(true)
    })

    it('reports driverNoUrl when the driver cannot play urls', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true })
      controller.configureDriver(new LocalOnlyDriver())
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m.indexOf('reason=driverNoUrl') >= 0)).assertEqual(true)
    })

    it('logs play and binds the active channel on a successful url playback', 0, async () => {
      const logs: string[] = []
      const driver = new UrlDriver()
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true })
      controller.configureDriver(driver)
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m === 'ring_url_gate result=play channel=webrtc')).assertEqual(true)
      expect(driver.urlCalls.length).assertEqual(1)
      expect(controller.getActiveChannel()).assertEqual(RtcRingtoneChannel.WEBRTC)
    })

    it('logs driverRefused when the playback never started', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      controller.configureDriver(new RefusingDriver())
      await controller.playIncoming(RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m.indexOf('ring_local_gate result=driverRefused') >= 0)).assertEqual(true)
      expect(controller.getActiveChannel() === undefined).assertEqual(true)
    })

    it('reports busy when a playback is already active', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      controller.configureDriver(new UrlDriver())
      controller.configurePolicy({ externalUrlEnabled: true })
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      logs.length = 0
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m.indexOf('reason=busy') >= 0)).assertEqual(true)
    })
  })
}
