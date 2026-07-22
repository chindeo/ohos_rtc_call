import { describe, it, expect } from '@ohos/hypium'
import {
  RtcWebRtcSignalRandomSource,
  RtcWebRtcSignalScheduler,
  RtcWebRtcSignalSession,
  RtcWebRtcSignalSocket,
  RtcWebRtcSignalSocketFactory
} from '../src/main/ets/signaling/RtcWebRtcSignalSession'

class MemoryTimer {
  id: number = 0
  callback: () => void = () => {}
  delayMs: number = 0
  active: boolean = true
}

class MemorySignalScheduler implements RtcWebRtcSignalScheduler {
  timers: MemoryTimer[] = []
  nextId: number = 1
  currentTime: number = 1000

  setTimeout(callback: () => void, delayMs: number): number {
    const timer = new MemoryTimer()
    timer.id = this.nextId
    timer.callback = callback
    timer.delayMs = delayMs
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

  now(): number {
    return this.currentTime
  }

  activeCount(): number {
    return this.timers.filter((timer: MemoryTimer) => timer.active).length
  }

  runNext(): void {
    for (let i = 0; i < this.timers.length; i += 1) {
      if (!this.timers[i].active) {
        continue
      }
      this.timers[i].active = false
      this.currentTime += this.timers[i].delayMs
      this.timers[i].callback()
      return
    }
  }
}

class FixedSignalRandomSource implements RtcWebRtcSignalRandomSource {
  next(): number {
    return 0.5
  }
}

class TestSignalSocket implements RtcWebRtcSignalSocket {
  connectCallback: (error: Object | undefined, success: boolean) => void = () => {}
  openCallback: () => void = () => {}
  closeCallback: () => void = () => {}
  errorCallback: (error: Object) => void = () => {}
  messageCallback: (error: Object | undefined, data: string | ArrayBuffer) => void = () => {}
  closed: boolean = false
  listenersCleared: boolean = false

  connect(_url: string, callback: (error: Object | undefined, success: boolean) => void): void {
    this.connectCallback = callback
  }

  close(): void {
    this.closed = true
  }

  send(_message: string, callback: (error: Object | undefined, success: boolean) => void): void {
    callback(undefined, true)
  }

  onOpen(callback: () => void): void {
    this.openCallback = callback
  }

  onClose(callback: () => void): void {
    this.closeCallback = callback
  }

  onError(callback: (error: Object) => void): void {
    this.errorCallback = callback
  }

  onMessage(callback: (error: Object | undefined, data: string | ArrayBuffer) => void): void {
    this.messageCallback = callback
  }

  clearListeners(): void {
    this.listenersCleared = true
    this.openCallback = () => {}
    this.closeCallback = () => {}
    this.errorCallback = () => {}
    this.messageCallback = () => {}
  }

  emitOpen(): void {
    this.openCallback()
  }

  emitClose(): void {
    this.closeCallback()
  }

  emitError(message: string): void {
    this.errorCallback(new Error(message))
  }

  emitRegister(status: number = 200): void {
    this.messageCallback(undefined, JSON.stringify({
      eventName: 'c__register',
      status,
      result: status === 200 ? '' : 'register failed',
      data: status === 200 ? JSON.stringify({
        serveNumber: 'serve-1',
        serveIp: '127.0.0.1',
        serveDisplayName: 'serve'
      }) : ''
    }))
  }
}

class TestSignalSocketFactory implements RtcWebRtcSignalSocketFactory {
  sockets: TestSignalSocket[] = []

  create(): RtcWebRtcSignalSocket {
    const socket = new TestSignalSocket()
    this.sockets.push(socket)
    return socket
  }
}

function createSession(
  scheduler: MemorySignalScheduler,
  socketFactory: TestSignalSocketFactory
): RtcWebRtcSignalSession {
  return new RtcWebRtcSignalSession({
    scheduler,
    socketFactory,
    randomSource: new FixedSignalRandomSource()
  })
}

function connectSession(session: RtcWebRtcSignalSession): void {
  session.connect({
    serverUrl: 'ws://rtc.example.com/websocket',
    appVersion: 'test',
    identity: {
      number: '1000',
      identity: 'device-1000',
      clientType: 'bed'
    }
  })
}

export default function rtcWebRtcSignalSessionTest() {
  describe('RtcWebRtcSignalSession', () => {
    it('schedules one reconnect and creates a fresh socket after close', 0, () => {
      const scheduler = new MemorySignalScheduler()
      const factory = new TestSignalSocketFactory()
      const session = createSession(scheduler, factory)
      let scheduledCount = 0
      session.setListener({
        onReconnectScheduled: () => {
          scheduledCount += 1
        }
      })
      connectSession(session)
      factory.sockets[0].emitOpen()
      factory.sockets[0].emitRegister()
      factory.sockets[0].emitClose()

      expect(scheduledCount).assertEqual(1)
      expect(session.getState().reconnecting).assertEqual(true)
      expect(session.getState().reconnectAttempt).assertEqual(1)
      expect(scheduler.activeCount()).assertEqual(1)

      scheduler.runNext()
      expect(factory.sockets.length).assertEqual(2)
      expect(session.getState().connecting).assertEqual(true)
    })

    it('deduplicates error and stale close callbacks', 0, () => {
      const scheduler = new MemorySignalScheduler()
      const factory = new TestSignalSocketFactory()
      const session = createSession(scheduler, factory)
      let scheduledCount = 0
      session.setListener({
        onReconnectScheduled: () => {
          scheduledCount += 1
        }
      })
      connectSession(session)
      const first = factory.sockets[0]
      const staleClose = first.closeCallback
      first.emitError('network down')
      staleClose()

      expect(scheduledCount).assertEqual(1)
      expect(scheduler.activeCount()).assertEqual(1)
    })

    it('does not reconnect after explicit close', 0, () => {
      const scheduler = new MemorySignalScheduler()
      const factory = new TestSignalSocketFactory()
      const session = createSession(scheduler, factory)
      connectSession(session)
      factory.sockets[0].emitError('network down')
      session.close()

      expect(scheduler.activeCount()).assertEqual(0)
      scheduler.runNext()
      expect(factory.sockets.length).assertEqual(1)
      expect(session.getState().url).assertEqual('')
    })

    it('retries connect and register timeouts', 0, () => {
      const connectScheduler = new MemorySignalScheduler()
      const connectFactory = new TestSignalSocketFactory()
      const connectSessionValue = createSession(connectScheduler, connectFactory)
      connectSession(connectSessionValue)
      connectScheduler.runNext()
      expect(connectSessionValue.getState().reconnecting).assertEqual(true)

      const registerScheduler = new MemorySignalScheduler()
      const registerFactory = new TestSignalSocketFactory()
      const registerSession = createSession(registerScheduler, registerFactory)
      connectSession(registerSession)
      registerFactory.sockets[0].emitOpen()
      registerScheduler.runNext()
      expect(registerSession.getState().reconnecting).assertEqual(true)
    })

    it('keeps escalating across short flaps and resets after stable registration', 0, () => {
      const scheduler = new MemorySignalScheduler()
      const factory = new TestSignalSocketFactory()
      const session = createSession(scheduler, factory)
      connectSession(session)
      factory.sockets[0].emitError('network down')
      scheduler.runNext()
      factory.sockets[1].emitOpen()
      factory.sockets[1].emitRegister()
      expect(session.getState().reconnectAttempt).assertEqual(1)

      factory.sockets[1].emitClose()
      expect(session.getState().reconnectAttempt).assertEqual(2)
      scheduler.runNext()
      factory.sockets[2].emitOpen()
      factory.sockets[2].emitRegister()
      scheduler.runNext()

      expect(session.getState().registered).assertEqual(true)
      expect(session.getState().reconnectAttempt).assertEqual(0)
    })
  })
}
