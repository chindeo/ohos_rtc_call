import { RtcAdminEntryCountdownNotifier } from '../model/RtcAdminEntryCountdown'

export interface RtcAdminEntryScheduler {
  setTimeout(callback: () => void, delayMs: number): number
  clearTimeout(timer: number): void
}

export interface RtcAdminEntryControllerOptions {
  longPressMs?: number
  startupNavigationDelayMs?: number
  countdownLabel?: string
  scheduler?: RtcAdminEntryScheduler
  onLongPressComplete?: () => void
  onNavigateHome?: () => void
  onPauseStartup?: () => void
  onResumeStartup?: () => void
}

export class RtcAdminEntryState {
  pressing: boolean = false
  startupPaused: boolean = false
  startupReady: boolean = false
  pendingAdminNavigation: boolean = false
  pendingHomeNavigation: boolean = false
  navigatedHome: boolean = false
}

class RtcDefaultAdminEntryScheduler implements RtcAdminEntryScheduler {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs)
  }

  clearTimeout(timer: number): void {
    clearTimeout(timer)
  }
}

export class RtcAdminEntryController {
  private options: RtcAdminEntryControllerOptions
  private scheduler: RtcAdminEntryScheduler
  private state: RtcAdminEntryState = new RtcAdminEntryState()
  private longPressTimer: number = -1
  private homeTimer: number = -1

  constructor(options?: RtcAdminEntryControllerOptions) {
    this.options = options || {}
    this.scheduler = this.options.scheduler || new RtcDefaultAdminEntryScheduler()
  }

  touchDown(): void {
    if (this.state.pendingAdminNavigation || this.state.navigatedHome) {
      return
    }
    this.clearLongPressTimer()
    this.pauseStartup()
    this.state.pressing = true
    RtcAdminEntryCountdownNotifier.start(this.getLongPressMs(), this.options.countdownLabel || '进入管理员设置界面')
    this.longPressTimer = this.scheduler.setTimeout(() => {
      this.completeLongPress()
    }, this.getLongPressMs())
  }

  touchUp(): void {
    if (!this.state.pressing) {
      return
    }
    this.cancelPress()
  }

  touchCancel(): void {
    this.cancelPress()
  }

  completeStartupCheck(): void {
    this.state.startupReady = true
    this.scheduleHomeNavigation()
  }

  pauseStartup(): void {
    if (this.state.startupPaused) {
      return
    }
    this.state.startupPaused = true
    this.clearHomeTimer()
    this.options.onPauseStartup?.()
  }

  resumeStartup(): void {
    if (!this.state.startupPaused) {
      return
    }
    this.state.startupPaused = false
    this.options.onResumeStartup?.()
    this.scheduleHomeNavigation()
  }

  markNavigationComplete(): void {
    this.state.pendingAdminNavigation = false
    this.state.pendingHomeNavigation = false
    this.clearLongPressTimer()
    this.clearHomeTimer()
  }

  dispose(): void {
    this.clearLongPressTimer()
    this.clearHomeTimer()
    RtcAdminEntryCountdownNotifier.cancel()
  }

  getState(): RtcAdminEntryState {
    const copy = new RtcAdminEntryState()
    copy.pressing = this.state.pressing
    copy.startupPaused = this.state.startupPaused
    copy.startupReady = this.state.startupReady
    copy.pendingAdminNavigation = this.state.pendingAdminNavigation
    copy.pendingHomeNavigation = this.state.pendingHomeNavigation
    copy.navigatedHome = this.state.navigatedHome
    return copy
  }

  private cancelPress(): void {
    this.state.pressing = false
    this.clearLongPressTimer()
    RtcAdminEntryCountdownNotifier.cancel()
    this.resumeStartup()
  }

  private completeLongPress(): void {
    if (!this.state.pressing) {
      return
    }
    this.state.pressing = false
    this.state.pendingAdminNavigation = true
    this.clearLongPressTimer()
    this.clearHomeTimer()
    RtcAdminEntryCountdownNotifier.complete()
    this.options.onLongPressComplete?.()
  }

  private scheduleHomeNavigation(): void {
    if (!this.state.startupReady || this.state.startupPaused || this.state.pendingAdminNavigation ||
      this.state.pendingHomeNavigation || this.state.navigatedHome) {
      return
    }
    this.state.pendingHomeNavigation = true
    this.homeTimer = this.scheduler.setTimeout(() => {
      this.navigateHome()
    }, this.getStartupNavigationDelayMs())
  }

  private navigateHome(): void {
    if (this.state.startupPaused || this.state.pendingAdminNavigation || this.state.navigatedHome) {
      this.state.pendingHomeNavigation = false
      return
    }
    this.state.pendingHomeNavigation = false
    this.state.navigatedHome = true
    this.options.onNavigateHome?.()
  }

  private getLongPressMs(): number {
    return Math.max(this.options.longPressMs || 3000, 500)
  }

  private getStartupNavigationDelayMs(): number {
    return Math.max(this.options.startupNavigationDelayMs || 2000, 0)
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimer >= 0) {
      this.scheduler.clearTimeout(this.longPressTimer)
      this.longPressTimer = -1
    }
  }

  private clearHomeTimer(): void {
    if (this.homeTimer >= 0) {
      this.scheduler.clearTimeout(this.homeTimer)
      this.homeTimer = -1
    }
    this.state.pendingHomeNavigation = false
  }
}
