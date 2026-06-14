import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallViewPhase } from '../model/RtcCallViewState'
import {
  RtcHostCallUiItem,
  RtcHostCallUiModel,
  RtcHostCallUiModelListener,
  RtcHostLocalCard
} from '../model/RtcHostCallUiModel'
import { RtcWebRtcMediaState } from '../webrtc/RtcWebRtcMediaController'
import {
  RtcCallDeviceRole,
  RtcCallUiActionState,
  RtcCallUiPresenter
} from '../ui/RtcCallUiPresenter'
import {
  RtcCallListItem,
  RtcDefaultCallService,
  RtcIncomingCallOptions
} from './RtcDefaultCallService'
import { RtcCallControlCommand } from './RtcCallControlCommand'
import { RtcCallTarget, RtcCallUnsubscribe } from './RtcCallService'

export enum RtcHostCallOperation {
  ACCEPT = 'accept',
  HANGUP = 'hangup',
  HANGUP_ALL = 'hangup_all',
  HOLD = 'hold',
  RESUME = 'resume',
  SELECT = 'select'
}

export class RtcHostCallOperationResult {
  handled: boolean = false
  reason: string = ''
  operation: RtcHostCallOperation = RtcHostCallOperation.SELECT
  sessionKey: string = ''
}

export interface RtcHostMultiCallControllerOptions {
  service: RtcDefaultCallService
  deviceRole?: RtcCallDeviceRole | string
  speakerActionLabel?: string
  speakerActionIsMicSwitch?: boolean
}

export interface RtcHostLocalCardOptions {
  number?: string
  displayName?: string
  clientType?: string
  hasVideo?: boolean
  videoReady?: boolean
}

export class RtcHostMultiCallController {
  private service: RtcDefaultCallService
  private listeners: RtcHostCallUiModelListener[] = []
  private unsubscribeView?: RtcCallUnsubscribe
  private unsubscribeCalls?: RtcCallUnsubscribe
  private localCard: RtcHostLocalCard = new RtcHostLocalCard()
  private muted: boolean = false
  private speakerEnabled: boolean = false
  private volume: number = 0
  private message: string = ''
  private speakerActionLabel: string
  private speakerActionIsMicSwitch: boolean
  private deviceRole: RtcCallDeviceRole | string
  private mediaStates: Map<string, RtcWebRtcMediaState> = new Map()
  private answerReadySessions: Map<string, boolean> = new Map()
  private lastUiModelDebugLogKey: string = ''

  constructor(options: RtcHostMultiCallControllerOptions) {
    this.service = options.service
    this.speakerActionLabel = options.speakerActionLabel || '免提'
    this.speakerActionIsMicSwitch = options.speakerActionIsMicSwitch === true
    this.deviceRole = options.deviceRole || RtcCallDeviceRole.HOST
    this.unsubscribeView = this.service.onViewStateChange(() => this.emit())
    this.unsubscribeCalls = this.service.onIncomingCallsChange(() => this.emit())
  }

  setLocalCard(options: RtcHostLocalCardOptions): void {
    this.localCard.number = options.number !== undefined ? options.number : this.localCard.number
    this.localCard.displayName = options.displayName !== undefined ? options.displayName : this.localCard.displayName
    this.localCard.clientType = options.clientType !== undefined ? options.clientType : this.localCard.clientType
    this.localCard.hasVideo = options.hasVideo !== undefined ? options.hasVideo === true : this.localCard.hasVideo
    this.localCard.videoReady = options.videoReady !== undefined ? options.videoReady === true : this.localCard.videoReady
    this.emit()
  }

  setMediaControlState(muted: boolean, speakerEnabled: boolean, volume: number): void {
    this.muted = muted
    this.speakerEnabled = speakerEnabled
    this.volume = Math.max(0, Math.min(100, volume))
    this.emit()
  }

  setMessage(message: string): void {
    this.message = message
    this.emit()
  }

  setCallMediaState(state: RtcWebRtcMediaState): void {
    const key = this.resolveRegisteredSessionKey(
      state.sessionKey,
      [state.sessionId],
      state.targetNumber
    ) || state.sessionKey
    this.mediaStates.set(key, state)
    this.emit()
  }

  setCallAnswerReady(
    sessionKey: string,
    ready: boolean,
    aliases: string[] = [],
    targetNumber: string = ''
  ): void {
    const key = this.resolveRegisteredSessionKey(sessionKey, aliases, targetNumber) ||
      (sessionKey || '').trim()
    if (!key) {
      return
    }
    this.answerReadySessions.set(key, ready)
    this.emit()
  }

  async receiveIncomingCall(options: RtcIncomingCallOptions): Promise<void> {
    await this.service.receiveIncomingCall(options)
    this.emit()
  }

  async startCall(target: RtcCallTarget, mode: RtcCallMode): Promise<void> {
    await this.service.startCall(target, mode)
    this.emit()
  }

  async accept(sessionKey?: string, command?: RtcCallControlCommand): Promise<RtcHostCallOperationResult> {
    this.logOperationRequested(RtcHostCallOperation.ACCEPT, sessionKey)
    const resolved = this.resolveSession(sessionKey, RtcHostCallOperation.ACCEPT)
    if (!resolved.handled) {
      this.logOperationResolved(resolved)
      return resolved
    }
    const call = this.service.getCallListItems()
      .find((item: RtcCallListItem) => this.getStableKey(item) === resolved.sessionKey)
    if (!call?.canAccept) {
      const result = this.result(false, 'session not acceptable', RtcHostCallOperation.ACCEPT, resolved.sessionKey)
      this.logOperationResolved(result)
      return result
    }
    const activeSessionKey = this.getUiModel().activeCall?.sessionKey || ''
    await this.service.acceptIncomingCall(resolved.sessionKey, command, {
      focus: !activeSessionKey || activeSessionKey === resolved.sessionKey
    })
    this.emit()
    this.logOperationResolved(resolved)
    return resolved
  }

  async hangup(sessionKey?: string, reason: string = 'host single hangup'): Promise<RtcHostCallOperationResult> {
    this.logOperationRequested(RtcHostCallOperation.HANGUP, sessionKey)
    const resolved = this.resolveSession(sessionKey, RtcHostCallOperation.HANGUP)
    if (!resolved.handled) {
      this.logOperationResolved(resolved)
      return resolved
    }
    this.clearSessionState(resolved.sessionKey)
    await this.service.terminateCallById(resolved.sessionKey, reason)
    this.emit()
    this.logOperationResolved(resolved)
    return resolved
  }

  async hangupAll(reason: string = 'host hangup all'): Promise<RtcHostCallOperationResult> {
    const result = this.result(true, 'all calls terminated', RtcHostCallOperation.HANGUP_ALL, '')
    await this.service.terminateAllCalls(reason)
    this.answerReadySessions.clear()
    this.mediaStates.clear()
    this.emit()
    return result
  }

  async hold(sessionKey?: string, command?: RtcCallControlCommand): Promise<RtcHostCallOperationResult> {
    this.logOperationRequested(RtcHostCallOperation.HOLD, sessionKey)
    const resolved = this.resolveSession(sessionKey, RtcHostCallOperation.HOLD)
    if (!resolved.handled) {
      this.logOperationResolved(resolved)
      return resolved
    }
    await this.service.holdCallById(resolved.sessionKey, command)
    this.emit()
    this.logOperationResolved(resolved)
    return resolved
  }

  async resume(sessionKey?: string, command?: RtcCallControlCommand): Promise<RtcHostCallOperationResult> {
    this.logOperationRequested(RtcHostCallOperation.RESUME, sessionKey)
    const resolved = this.resolveSession(sessionKey, RtcHostCallOperation.RESUME)
    if (!resolved.handled) {
      this.logOperationResolved(resolved)
      return resolved
    }
    await this.service.resumeCallById(resolved.sessionKey, command)
    this.emit()
    this.logOperationResolved(resolved)
    return resolved
  }

  select(sessionKey?: string): RtcHostCallOperationResult {
    this.logOperationRequested(RtcHostCallOperation.SELECT, sessionKey)
    const resolved = this.resolveSession(sessionKey, RtcHostCallOperation.SELECT)
    if (!resolved.handled) {
      this.logOperationResolved(resolved)
      return resolved
    }
    if (!this.service.selectCall(resolved.sessionKey)) {
      const result = this.result(false, 'session not selectable', RtcHostCallOperation.SELECT, resolved.sessionKey)
      this.logOperationResolved(result)
      return result
    }
    this.emit()
    this.logOperationResolved(resolved)
    return resolved
  }

  markConnected(sessionKey?: string): RtcHostCallOperationResult {
    const resolved = this.resolveSession(sessionKey, RtcHostCallOperation.SELECT)
    if (!resolved.handled) {
      return resolved
    }
    if (!this.service.markConnectedById(resolved.sessionKey)) {
      return this.result(false, 'session not found', RtcHostCallOperation.SELECT, resolved.sessionKey)
    }
    this.emit()
    return resolved
  }

  markConnectedByMediaState(state: RtcWebRtcMediaState): RtcHostCallOperationResult {
    const resolvedKey = this.resolveMediaStateSessionKey(state)
    if (!resolvedKey) {
      return this.result(false, 'session not found', RtcHostCallOperation.SELECT, state.sessionKey)
    }
    if (!this.service.markConnectedById(resolvedKey)) {
      return this.result(false, 'session not found', RtcHostCallOperation.SELECT, resolvedKey)
    }
    this.emit()
    return this.result(true, 'resolved media session', RtcHostCallOperation.SELECT, resolvedKey)
  }

  applyRemoteHold(sessionKey: string, isHold: boolean): RtcHostCallOperationResult {
    const operation = isHold ? RtcHostCallOperation.HOLD : RtcHostCallOperation.RESUME
    const resolved = this.resolveSession(sessionKey, operation)
    if (!resolved.handled) {
      return resolved
    }
    if (!this.service.applyHoldStateById(resolved.sessionKey, isHold)) {
      return this.result(false, 'session not found', operation, resolved.sessionKey)
    }
    this.emit()
    return resolved
  }

  getUiModel(): RtcHostCallUiModel {
    const viewState = this.service.getViewState()
    const calls = this.service.getCallListItems()
    const model = new RtcHostCallUiModel()
    model.registered = viewState.registered
    model.localCard = this.copyLocalCard()
    model.muted = this.muted
    model.speakerEnabled = this.speakerEnabled
    model.speakerActionLabel = this.speakerActionLabel
    model.speakerActionIsMicSwitch = this.speakerActionIsMicSwitch
    model.deviceRole = this.deviceRole
    model.volume = this.volume
    model.message = this.message || viewState.errorMessage || viewState.registrationErrorMessage

    const mapped = calls
      .filter((item: RtcCallListItem) => this.isDisplayableCall(item))
      .map((item: RtcCallListItem) => this.toUiItem(item))
    model.activeCall = mapped.find((item: RtcHostCallUiItem) => item.isSelected) ||
      mapped.find((item: RtcHostCallUiItem) => item.isActive)
    if (!model.activeCall && mapped.length > 0) {
      model.activeCall = mapped[0]
    }
    model.sideCalls = model.activeCall ?
      mapped.filter((item: RtcHostCallUiItem) => item.sessionKey !== model.activeCall?.sessionKey) : []
    model.visible = mapped.length > 0
    model.showHangupAll = model.visible && mapped.length > 1
    model.videoState.enabled = !!model.activeCall && model.activeCall.mode === RtcCallMode.VIDEO
    model.videoState.localReady = this.localCard.videoReady
    model.videoState.remoteReady = model.activeCall?.hasRemoteVideo === true
    model.videoState.activeSessionKey = model.activeCall?.sessionKey || ''
    const actionModel = RtcCallUiPresenter.present(viewState, {
      role: this.deviceRole,
      participantCount: mapped.length,
      muted: this.muted,
      speakerEnabled: this.speakerEnabled,
      cameraEnabled: this.localCard.videoReady
    })
    model.actions = actionModel.actions.map((action: RtcCallUiActionState) => ({
      action: action.action,
      visible: action.visible,
      enabled: action.enabled,
      active: action.active,
      label: action.label
    }))
    this.logUiModelDebug(model)
    return model
  }

  onUiModelChange(listener: RtcHostCallUiModelListener): RtcCallUnsubscribe {
    this.listeners.push(listener)
    listener(this.getUiModel())
    return () => {
      this.listeners = this.listeners.filter((item: RtcHostCallUiModelListener) => item !== listener)
    }
  }

  dispose(): void {
    this.unsubscribeView?.()
    this.unsubscribeCalls?.()
    this.unsubscribeView = undefined
    this.unsubscribeCalls = undefined
    this.listeners = []
  }

  private resolveSession(sessionKey: string | undefined, operation: RtcHostCallOperation):
    RtcHostCallOperationResult {
    const key = (sessionKey || '').trim()
    const calls = this.service.getCallListItems()
    if (calls.length === 0) {
      return this.result(false, 'no active calls', operation, '')
    }
    if (!key) {
      if (calls.length !== 1) {
        return this.result(false, 'ambiguous session key', operation, '')
      }
      return this.result(true, 'resolved single call', operation, this.getStableKey(calls[0]))
    }

    const exactMatches = calls.filter((item: RtcCallListItem) =>
      item.sessionKey === key || item.uid === key || item.callId === key || item.key === key)
    if (exactMatches.length === 1) {
      return this.result(true, 'resolved exact session', operation, this.getStableKey(exactMatches[0]))
    }
    if (exactMatches.length > 1) {
      return this.result(false, 'ambiguous exact session', operation, key)
    }

    const peerMatches = calls.filter((item: RtcCallListItem) => item.peerNumber === key)
    if (peerMatches.length === 1) {
      return this.result(true, 'resolved unique peer', operation, this.getStableKey(peerMatches[0]))
    }
    return this.result(false, peerMatches.length > 1 ? 'ambiguous peer session' : 'session not found',
      operation, key)
  }

  private getStableKey(item: RtcCallListItem): string {
    return item.sessionKey || item.uid || item.callId || item.key
  }

  private isDisplayableCall(item: RtcCallListItem): boolean {
    return item.phase !== RtcCallViewPhase.ENDED && item.canHangup
  }

  private resolveRegisteredSessionKey(
    sessionKey: string,
    aliases: string[] = [],
    targetNumber: string = ''
  ): string {
    const candidates: string[] = [sessionKey]
    aliases.forEach((alias: string) => candidates.push(alias))
    const calls = this.service.getCallListItems()
    for (let i = 0; i < candidates.length; i += 1) {
      const key = (candidates[i] || '').trim()
      if (!key) {
        continue
      }
      const matches = calls.filter((item: RtcCallListItem) =>
        item.sessionKey === key || item.uid === key || item.callId === key || item.key === key)
      if (matches.length === 1) {
        return this.getStableKey(matches[0])
      }
    }
    const target = (targetNumber || '').trim()
    if (!target) {
      return ''
    }
    const peerMatches = calls.filter((item: RtcCallListItem) => item.peerNumber === target)
    return peerMatches.length === 1 ? this.getStableKey(peerMatches[0]) : ''
  }

  private resolveMediaStateSessionKey(state: RtcWebRtcMediaState): string {
    const aliases: string[] = []
    if (state.sessionId) {
      aliases.push(state.sessionId)
    }
    if (state.uid) {
      aliases.push(state.uid)
    }
    return this.resolveRegisteredSessionKey(
      state.sessionKey,
      aliases,
      state.targetNumber
    )
  }

  private clearSessionState(sessionKey: string): void {
    this.answerReadySessions.delete(sessionKey)
    this.mediaStates.delete(sessionKey)
  }

  private toUiItem(item: RtcCallListItem): RtcHostCallUiItem {
    const mapped = new RtcHostCallUiItem()
    mapped.sessionKey = this.getStableKey(item)
    mapped.callId = item.callId
    mapped.uid = item.uid
    mapped.peerNumber = item.peerNumber
    mapped.displayName = item.displayName || item.peerNumber
    mapped.clientType = item.target.clientType || ''
    mapped.direction = item.direction
    mapped.phase = item.phase
    mapped.mode = item.mode
    mapped.statusText = this.getStatusText(item.phase)
    mapped.isActive = item.isActive
    mapped.isSelected = item.isSelected
    mapped.isHold = item.isHold
    mapped.mediaConnected = item.phase === RtcCallViewPhase.CONNECTED
    mapped.canAccept = item.canAccept
    mapped.canHold = this.canUseHoldControls() && item.canHold
    mapped.canResume = this.canUseHoldControls() && item.canResume
    mapped.canHangup = item.canHangup
    mapped.receivedAt = item.receivedAt
    mapped.connectedAt = item.connectedAt
    mapped.durationText = this.formatDuration(item.connectedAt)
    const media = this.mediaStates.get(mapped.sessionKey)
    if (media) {
      mapped.hasRemoteAudio = media.hasRemoteAudio
      mapped.hasRemoteVideo = media.hasRemoteVideo
      mapped.mediaConnected = media.mediaConnected
    }
    return mapped
  }

  private formatDuration(connectedAt: number): string {
    if (!connectedAt) {
      return ''
    }
    const elapsedSeconds = Math.max(0, Math.floor((Date.now() - connectedAt) / 1000))
    const hours = Math.floor(elapsedSeconds / 3600)
    const minutes = Math.floor((elapsedSeconds % 3600) / 60)
    const seconds = elapsedSeconds % 60
    const minuteText = minutes < 10 ? '0' + minutes : '' + minutes
    const secondText = seconds < 10 ? '0' + seconds : '' + seconds
    return hours > 0 ? hours + ':' + minuteText + ':' + secondText : minuteText + ':' + secondText
  }

  private getStatusText(phase: RtcCallViewPhase): string {
    switch (phase) {
      case RtcCallViewPhase.INCOMING:
        return '待接听'
      case RtcCallViewPhase.OUTGOING:
        return '呼叫中'
      case RtcCallViewPhase.CONNECTING:
        return '连接中'
      case RtcCallViewPhase.CONNECTED:
        return '通话中'
      case RtcCallViewPhase.HELD:
        return '保持中'
      case RtcCallViewPhase.ERROR:
        return '通话异常'
      case RtcCallViewPhase.ENDED:
        return '已结束'
      default:
        return ''
    }
  }

  private copyLocalCard(): RtcHostLocalCard {
    const copy = new RtcHostLocalCard()
    copy.number = this.localCard.number
    copy.displayName = this.localCard.displayName
    copy.clientType = this.localCard.clientType
    copy.hasVideo = this.localCard.hasVideo
    copy.videoReady = this.localCard.videoReady
    return copy
  }

  private canUseHoldControls(): boolean {
    return this.deviceRole === RtcCallDeviceRole.HOST
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

  private logOperationRequested(operation: RtcHostCallOperation, sessionKey?: string): void {
    console.info('RtcHostMultiCallController ' + operation +
      ' requested sidHash=' + this.getSessionHash(sessionKey || ''))
  }

  private logOperationResolved(result: RtcHostCallOperationResult): void {
    console.info('RtcHostMultiCallController ' + result.operation +
      ' resolved sidHash=' + this.getSessionHash(result.sessionKey) +
      ' handled=' + result.handled +
      ' reason=' + result.reason)
  }

  private logUiModelDebug(model: RtcHostCallUiModel): void {
    const active = model.activeCall
    const sideHashes: string[] = []
    const sidePhases: string[] = []
    const sideAccepts: string[] = []
    const sideHangups: string[] = []
    model.sideCalls.forEach((call: RtcHostCallUiItem) => {
      sideHashes.push(this.getSessionHash(call.sessionKey))
      sidePhases.push(call.phase)
      sideAccepts.push(call.canAccept ? '1' : '0')
      sideHangups.push(call.canHangup ? '1' : '0')
    })
    const key = 'visible=' + model.visible +
      '|activeHash=' + this.getSessionHash(active?.sessionKey || '') +
      '|activePhase=' + (active?.phase || '') +
      '|activeCanAccept=' + (active?.canAccept === true) +
      '|activeCanHangup=' + (active?.canHangup === true) +
      '|sideHashes=' + sideHashes.join(',') +
      '|sidePhases=' + sidePhases.join(',') +
      '|sideCanAccept=' + sideAccepts.join(',') +
      '|sideCanHangup=' + sideHangups.join(',')
    if (this.lastUiModelDebugLogKey === key) {
      return
    }
    this.lastUiModelDebugLogKey = key
    console.info('RtcHostMultiCallController ui_model ' + key)
  }

  private emit(): void {
    const model = this.getUiModel()
    this.listeners.forEach((listener: RtcHostCallUiModelListener) => listener(model))
  }

  private result(
    handled: boolean,
    reason: string,
    operation: RtcHostCallOperation,
    sessionKey: string
  ): RtcHostCallOperationResult {
    const result = new RtcHostCallOperationResult()
    result.handled = handled
    result.reason = reason
    result.operation = operation
    result.sessionKey = sessionKey
    return result
  }
}
