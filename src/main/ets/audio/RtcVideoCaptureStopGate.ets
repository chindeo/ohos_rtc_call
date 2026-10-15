export const RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS: number = 1500

interface RtcVideoCaptureStopWaiter {
  resolve: (result: string) => void
  timerId: number
}

/**
 * Records whether a released native video source has confirmed that capture actually stopped.
 *
 * `arm()` opens a window, `settle(token)` closes it when native dispatches
 * `oncapturerstopped`, and `wait()` lets a caller that is about to create the next video source
 * resume as soon as that confirmation arrives. A firmware or native build that never dispatches
 * the event degrades to a bounded `timeout` result instead of blocking the next capture forever,
 * and the pending window survives the timeout so logs still report an unconfirmed release.
 *
 * A newer `arm()` replaces the pending window, so a late callback from an earlier release can
 * never settle the current one: `settle()` only accepts the matching token.
 */
export class RtcVideoCaptureStopGate {
  private pendingToken: number = 0
  private issuedToken: number = 0
  private pendingSinceMs: number = 0
  private waiters: RtcVideoCaptureStopWaiter[] = []

  isPending(): boolean {
    return this.pendingToken !== 0
  }

  pendingAgeMs(): number {
    if (this.pendingToken === 0) {
      return 0
    }
    return Date.now() - this.pendingSinceMs
  }

  arm(): number {
    this.issuedToken += 1
    this.pendingToken = this.issuedToken
    this.pendingSinceMs = Date.now()
    return this.pendingToken
  }

  settle(token: number): boolean {
    if (this.pendingToken === 0 || this.pendingToken !== token) {
      return false
    }
    this.pendingToken = 0
    this.releaseWaiters('stopped')
    return true
  }

  wait(timeoutMs: number = RTC_VIDEO_CAPTURE_STOP_TIMEOUT_MS): Promise<string> {
    if (this.pendingToken === 0) {
      return Promise.resolve('quiesced')
    }
    return new Promise<string>((resolve: (result: string) => void) => {
      const waiter: RtcVideoCaptureStopWaiter = {
        resolve: resolve,
        timerId: setTimeout(() => {
          this.expireWaiter(waiter)
        }, timeoutMs)
      }
      this.waiters.push(waiter)
    })
  }

  private expireWaiter(waiter: RtcVideoCaptureStopWaiter): void {
    const index: number = this.waiters.indexOf(waiter)
    if (index < 0) {
      return
    }
    this.waiters.splice(index, 1)
    waiter.resolve('timeout')
  }

  private releaseWaiters(result: string): void {
    const pending: RtcVideoCaptureStopWaiter[] = this.waiters.slice()
    this.waiters = []
    pending.forEach((waiter: RtcVideoCaptureStopWaiter) => {
      clearTimeout(waiter.timerId)
      waiter.resolve(result)
    })
  }
}
