import { describe, it, expect } from '@ohos/hypium'
import {
  RtcAdminEntryController,
  RtcAdminEntryScheduler
} from '../src/main/ets/core/RtcAdminEntryController'

class MemoryTimer {
  id: number = 0
  callback: () => void = () => {}
  active: boolean = true
}

class MemoryScheduler implements RtcAdminEntryScheduler {
  timers: MemoryTimer[] = []
  nextId: number = 1

  setTimeout(callback: () => void, _delayMs: number): number {
    const timer = new MemoryTimer()
    timer.id = this.nextId
    timer.callback = callback
    this.nextId += 1
    this.timers.push(timer)
    return timer.id
  }

  clearTimeout(timerId: number): void {
    for (let i = 0; i < this.timers.length; i += 1) {
      if (this.timers[i].id === timerId) {
        this.timers[i].active = false
      }
    }
  }

  runNext(): void {
    for (let i = 0; i < this.timers.length; i += 1) {
      if (this.timers[i].active) {
        this.timers[i].active = false
        this.timers[i].callback()
        return
      }
    }
  }
}

export default function rtcAdminEntryControllerTest() {
  describe('RtcAdminEntryController', () => {
    it('pauses startup while pressing and completes admin navigation on long press', 0, () => {
      const scheduler = new MemoryScheduler()
      let adminCount = 0
      const controller = new RtcAdminEntryController({
        scheduler,
        longPressMs: 1000,
        onLongPressComplete: () => {
          adminCount += 1
        }
      })

      controller.touchDown()
      expect(controller.getState().startupPaused).assertEqual(true)
      scheduler.runNext()

      expect(adminCount).assertEqual(1)
      expect(controller.getState().pendingAdminNavigation).assertEqual(true)
      expect(controller.getState().pendingHomeNavigation).assertEqual(false)
    })

    it('delays home navigation after startup check', 0, () => {
      const scheduler = new MemoryScheduler()
      let homeCount = 0
      const controller = new RtcAdminEntryController({
        scheduler,
        startupNavigationDelayMs: 2000,
        onNavigateHome: () => {
          homeCount += 1
        }
      })

      controller.completeStartupCheck()
      expect(controller.getState().pendingHomeNavigation).assertEqual(true)
      expect(homeCount).assertEqual(0)

      scheduler.runNext()
      expect(homeCount).assertEqual(1)
      expect(controller.getState().navigatedHome).assertEqual(true)
    })
  })
}
