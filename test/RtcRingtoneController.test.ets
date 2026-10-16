import { describe, it, expect } from '@ohos/hypium'
import {
  RtcRingtoneChannel,
  RtcRingtoneController,
  RtcRingtoneDriver,
  RtcRingtoneUrlResult
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

/** 回报一个固定结果的驱动，用来模拟外链真的出声或真的失败。 */
class ReportingDriver implements RtcRingtoneDriver {
  incomingCalls: number = 0
  stopCalls: number = 0
  private readonly outcome: RtcRingtoneUrlResult

  constructor(outcome: RtcRingtoneUrlResult) {
    this.outcome = outcome
  }

  async playIncoming(): Promise<boolean> {
    this.incomingCalls += 1
    return true
  }

  async playUrl(_url: string, onResult?: (result: RtcRingtoneUrlResult) => void): Promise<boolean> {
    setTimeout((): void => {
      if (onResult) {
        onResult(this.outcome)
      }
    }, 10)
    return true
  }

  async stop(): Promise<void> {
    this.stopCalls += 1
  }
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms)
  })
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

  describe('RtcRingtoneController url fallback', () => {
    it('falls back to the local ring when the driver reports the url player went idle', 0, async () => {
      const logs: string[] = []
      const driver = new ReportingDriver(RtcRingtoneUrlResult.IDLE)
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true, urlFallbackEnabled: true, urlFallbackTimeoutMs: 400 })
      controller.configureDriver(driver)
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      await delay(60)
      expect(logs.some((m: string) => m === 'ring_url_gate result=fallback reason=io channel=webrtc'))
        .assertEqual(true)
      expect(driver.stopCalls).assertEqual(1)
      expect(driver.incomingCalls).assertEqual(1)
    })

    it('does not fall back when the driver reports the url actually reached playing', 0, async () => {
      const logs: string[] = []
      const driver = new ReportingDriver(RtcRingtoneUrlResult.PLAYING)
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true, urlFallbackEnabled: true, urlFallbackTimeoutMs: 400 })
      controller.configureDriver(driver)
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      await delay(120)
      expect(logs.some((m: string) => m.indexOf('result=fallback') >= 0)).assertEqual(false)
      expect(driver.incomingCalls).assertEqual(0)
    })

    it('falls back on timeout when a silent driver never reports any outcome', 0, async () => {
      const logs: string[] = []
      const driver = new UrlDriver()
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true, urlFallbackEnabled: true, urlFallbackTimeoutMs: 40 })
      controller.configureDriver(driver)
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      await delay(140)
      expect(logs.some((m: string) => m === 'ring_url_gate result=fallback reason=timeout channel=webrtc'))
        .assertEqual(true)
      expect(driver.incomingCalls).assertEqual(1)
    })

    it('keeps the old behaviour when fallback is not opted in', 0, async () => {
      const logs: string[] = []
      const driver = new ReportingDriver(RtcRingtoneUrlResult.IDLE)
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true, urlFallbackTimeoutMs: 40 })
      controller.configureDriver(driver)
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      await delay(140)
      expect(logs.some((m: string) => m.indexOf('result=fallback') >= 0)).assertEqual(false)
      expect(driver.incomingCalls).assertEqual(0)
    })

    it('falls back immediately when the driver refuses the url playback', 0, async () => {
      const logs: string[] = []
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true, urlFallbackEnabled: true, urlFallbackTimeoutMs: 400 })
      controller.configureDriver(new RefusingDriver())
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      expect(logs.some((m: string) => m === 'ring_url_gate result=fallback reason=refused channel=webrtc'))
        .assertEqual(true)
    })

    it('keeps a late idle report after stop from ringing again', 0, async () => {
      const logs: string[] = []
      const driver = new ReportingDriver(RtcRingtoneUrlResult.IDLE)
      const controller = controllerWithLogger(logs)
      controller.configurePolicy({ externalUrlEnabled: true, urlFallbackEnabled: true, urlFallbackTimeoutMs: 400 })
      controller.configureDriver(driver)
      await controller.playUrl('https://host/ring.mp3', RtcRingtoneChannel.WEBRTC)
      await controller.stop()
      await delay(120)
      expect(logs.some((m: string) => m.indexOf('result=fallback') >= 0)).assertEqual(false)
      expect(driver.incomingCalls).assertEqual(0)
    })
  })
}
