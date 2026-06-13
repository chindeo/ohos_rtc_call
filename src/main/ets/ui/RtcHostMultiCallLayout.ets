import { RtcHostCallUiModel } from '../model/RtcHostCallUiModel'
import { RtcReferenceCallLayout } from './RtcReferenceCallLayout'

@Component
export struct RtcHostMultiCallLayout {
  @Prop model: RtcHostCallUiModel = new RtcHostCallUiModel()
  @BuilderParam localVideoBuilder?: () => void
  @BuilderParam remoteVideoBuilder?: () => void
  @BuilderParam sessionRemoteVideoBuilder?: (sessionKey: string) => void

  onAccept?: (sessionKey: string) => void
  onHangup?: (sessionKey: string) => void
  onHangupAll?: () => void
  onHold?: (sessionKey: string) => void
  onResume?: (sessionKey: string) => void
  onSelect?: (sessionKey: string) => void
  onMute?: () => void
  onSpeaker?: () => void

  private lastBuildLogKey: string = ''
  private lastAreaLogKey: string = ''

  aboutToAppear(): void {
    console.info('RtcHostMultiCallLayout rtc_host_layout_appear')
  }

  aboutToDisappear(): void {
    console.info('RtcHostMultiCallLayout rtc_host_layout_disappear')
  }

  private logBuild(): boolean {
    const call = this.model.activeCall
    const key = 'visible=' + this.model.visible +
      '|hasActive=' + (call ? 'true' : 'false') +
      '|phase=' + (call?.phase || '') +
      '|mode=' + (call?.mode || '') +
      '|canHangup=' + (call?.canHangup === true) +
      '|canHold=' + (call?.canHold === true) +
      '|sideCount=' + ((this.model.sideCalls || []).length)
    if (this.lastBuildLogKey !== key) {
      this.lastBuildLogKey = key
      console.info('RtcHostMultiCallLayout rtc_host_layout_build ' + key)
      if (this.model.visible && !call) {
        console.warn('RtcHostMultiCallLayout rtc_host_layout_warning visible=true activeCall=false')
      }
    }
    return true
  }

  private logArea(width: number, height: number): void {
    const key = 'width=' + width + '|height=' + height
    if (this.lastAreaLogKey !== key) {
      this.lastAreaLogKey = key
      console.info('RtcHostMultiCallLayout rtc_host_layout_area width=' + width + ' height=' + height)
    }
  }

  private getSessionHash(sessionKey: string): string {
    const key = (sessionKey || '').trim()
    let hash = 0
    for (let i = 0; i < key.length; i += 1) {
      hash = (hash * 33 + key.charCodeAt(i)) % 60466176
    }
    let text = hash.toString(36)
    while (text.length < 6) {
      text = '0' + text
    }
    return text
  }

  private logCallback(actionName: string, sessionKey?: string): void {
    console.info('RtcHostMultiCallLayout rtc_host_callback action=' + actionName +
      ' sidHash=' + this.getSessionHash(sessionKey || ''))
  }

  build() {
    if (this.logBuild()) {
      Stack() {
        RtcReferenceCallLayout({
          model: this.model,
          localVideoBuilder: this.localVideoBuilder,
          remoteVideoBuilder: this.remoteVideoBuilder,
          sessionRemoteVideoBuilder: this.sessionRemoteVideoBuilder,
          onAccept: (sessionKey: string) => {
            this.logCallback('accept', sessionKey)
            this.onAccept?.(sessionKey)
          },
          onHangup: (sessionKey: string) => {
            this.logCallback('hangup', sessionKey)
            this.onHangup?.(sessionKey)
          },
          onHangupAll: () => {
            this.logCallback('hangup_all')
            this.onHangupAll?.()
          },
          onHold: (sessionKey: string) => {
            this.logCallback('hold', sessionKey)
            this.onHold?.(sessionKey)
          },
          onResume: (sessionKey: string) => {
            this.logCallback('resume', sessionKey)
            this.onResume?.(sessionKey)
          },
          onSelect: (sessionKey: string) => {
            this.logCallback('select', sessionKey)
            this.onSelect?.(sessionKey)
          },
          onMute: () => {
            this.logCallback('mute')
            this.onMute?.()
          },
          onSpeaker: () => {
            this.logCallback('speaker')
            this.onSpeaker?.()
          }
        })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.logArea(Number(newArea.width), Number(newArea.height))
      })
    }
  }
}
