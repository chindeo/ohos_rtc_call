import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallDirection } from '../model/RtcCallViewState'
import { RtcCallTarget } from './RtcCallService'

export type RtcIncomingCallQueuePhase = 'incoming' | 'outgoing' | 'accepted' | 'ended'

export interface RtcIncomingCallQueueOptions {
  maxSize?: number
}

export interface RtcIncomingCallQueueItemOptions {
  callId?: string
  uid?: string
  peerNumber?: string
  sessionKey?: string
  target: RtcCallTarget
  mode?: RtcCallMode
  autoAnswer?: boolean
  isHold?: boolean
  status?: string
  direction?: RtcCallDirection
  phase?: RtcIncomingCallQueuePhase
  sortWeight?: number
  receivedAt?: number
}

export interface RtcIncomingCallQueueFocusOptions {
  focus?: boolean
}

export class RtcIncomingCallRecord {
  callId: string = ''
  uid: string = ''
  key: string = ''
  sessionKey: string = ''
  peerNumber: string = ''
  target: RtcCallTarget = { number: '' }
  mode: RtcCallMode = RtcCallMode.AUDIO
  phase: RtcIncomingCallQueuePhase = 'incoming'
  autoAnswer: boolean = false
  isHold: boolean = false
  status: string = ''
  direction: RtcCallDirection = RtcCallDirection.INCOMING
  sortWeight: number = 999999
  receivedAt: number = 0
  connectedAt: number = 0
  updatedAt: number = 0
  visible: boolean = true
  endReason: string = ''
}

export class RtcIncomingCallQueueSnapshot {
  calls: RtcIncomingCallRecord[] = []
  activeCallId: string = ''
  selectedCallId: string = ''
  pendingCount: number = 0
}

export type RtcIncomingCallQueueListener = (snapshot: RtcIncomingCallQueueSnapshot) => void

export class RtcIncomingCallQueue {
  private calls: RtcIncomingCallRecord[] = []
  private activeCallId: string = ''
  private selectedCallId: string = ''
  private maxSize: number
  private listeners: RtcIncomingCallQueueListener[] = []

  constructor(options?: RtcIncomingCallQueueOptions) {
    this.maxSize = options?.maxSize || 12
  }

  upsert(options: RtcIncomingCallQueueItemOptions): RtcIncomingCallRecord {
    const now = options.receivedAt || Date.now()
    const key = RtcIncomingCallQueue.resolveKey(options)
    let record = this.calls.find((item: RtcIncomingCallRecord) => item.key === key)
    const isNewRecord = !record
    if (!record) {
      record = new RtcIncomingCallRecord()
      record.key = key
      record.callId = options.callId || key
      record.uid = options.uid || ''
      record.receivedAt = now
      this.calls.push(record)
    }

    record.uid = options.uid || record.uid
    record.sessionKey = options.sessionKey || record.uid || record.callId
    record.peerNumber = options.peerNumber || options.target.number || record.peerNumber
    record.target = RtcIncomingCallQueue.copyTarget(options.target)
    record.mode = options.mode || RtcCallMode.AUDIO
    record.autoAnswer = options.autoAnswer === true
    record.isHold = options.isHold === true
    record.status = options.status || record.status
    record.direction = options.direction || record.direction
    record.sortWeight = options.sortWeight !== undefined ? options.sortWeight : record.sortWeight
    if (isNewRecord || record.phase === 'ended') {
      record.phase = options.phase || 'incoming'
    }
    record.visible = true
    record.endReason = ''
    record.updatedAt = now
    if (!this.selectedCallId) {
      this.selectedCallId = record.callId
    }

    this.trim()
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  accept(callId: string, options?: RtcIncomingCallQueueFocusOptions): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    if (!record) {
      return undefined
    }
    record.phase = 'accepted'
    record.status = 'accepted'
    record.visible = true
    record.updatedAt = Date.now()
    if (options?.focus !== false) {
      this.activeCallId = record.callId
      this.selectedCallId = record.callId
    }
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  select(callId: string): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    if (!record) {
      return undefined
    }
    this.selectedCallId = record.callId
    record.updatedAt = Date.now()
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  markHold(callId: string, isHold: boolean): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    if (!record) {
      return undefined
    }
    record.isHold = isHold
    record.status = isHold ? 'hold' : (record.phase === 'accepted' ? 'accepted' : record.status)
    record.updatedAt = Date.now()
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  markConnected(
    callId: string,
    connectedAt: number = Date.now(),
    options?: RtcIncomingCallQueueFocusOptions
  ): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    if (!record) {
      return undefined
    }
    record.phase = 'accepted'
    record.status = 'accepted'
    record.isHold = false
    if (!record.connectedAt) {
      record.connectedAt = connectedAt
    }
    record.updatedAt = Date.now()
    if (options?.focus !== false) {
      this.activeCallId = record.callId
    }
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  end(callId: string, reason: string = 'ended'): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    if (!record) {
      return undefined
    }
    record.phase = 'ended'
    record.status = reason
    record.visible = false
    record.endReason = reason
    record.updatedAt = Date.now()
    if (this.activeCallId === record.callId) {
      this.activeCallId = ''
    }
    if (this.selectedCallId === record.callId) {
      this.selectedCallId = this.resolveNextVisibleCallId(record.callId)
    }
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  remove(callId: string): void {
    const record = this.find(callId)
    if (!record) {
      return
    }
    const removingActive = record.callId === this.activeCallId
    const removingSelected = record.callId === this.selectedCallId
    this.calls = this.calls.filter((item: RtcIncomingCallRecord) => item.callId !== record.callId)
    if (removingActive) {
      this.activeCallId = ''
    }
    if (removingSelected) {
      this.selectedCallId = this.resolveNextVisibleCallId(callId)
    }
    this.emit()
  }

  clearEnded(): void {
    this.calls = this.calls.filter((item: RtcIncomingCallRecord) => item.phase !== 'ended')
    this.emit()
  }

  clear(): void {
    this.calls = []
    this.activeCallId = ''
    this.selectedCallId = ''
    this.emit()
  }

  getCall(callId: string): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    return record ? RtcIncomingCallQueue.copyRecord(record) : undefined
  }

  getPending(): RtcIncomingCallRecord[] {
    return this.calls
      .filter((item: RtcIncomingCallRecord) => item.phase === 'incoming')
      .map((item: RtcIncomingCallRecord) => RtcIncomingCallQueue.copyRecord(item))
  }

  getSnapshot(): RtcIncomingCallQueueSnapshot {
    const snapshot = new RtcIncomingCallQueueSnapshot()
    snapshot.calls = this.calls
      .slice()
      .sort((left: RtcIncomingCallRecord, right: RtcIncomingCallRecord) => {
        if (left.sortWeight !== right.sortWeight) {
          return left.sortWeight - right.sortWeight
        }
        return right.receivedAt - left.receivedAt
      })
      .map((item: RtcIncomingCallRecord) => RtcIncomingCallQueue.copyRecord(item))
    snapshot.activeCallId = this.activeCallId
    snapshot.selectedCallId = this.selectedCallId
    snapshot.pendingCount = snapshot.calls.filter((item: RtcIncomingCallRecord) => item.phase === 'incoming').length
    return snapshot
  }

  onChange(listener: RtcIncomingCallQueueListener): () => void {
    this.listeners.push(listener)
    listener(this.getSnapshot())
    return () => {
      this.listeners = this.listeners.filter((item: RtcIncomingCallQueueListener) => item !== listener)
    }
  }

  private find(callId: string): RtcIncomingCallRecord | undefined {
    const key = (callId || '').trim()
    if (!key) {
      return undefined
    }
    const exact = this.calls.find((item: RtcIncomingCallRecord) =>
      item.callId === key || item.key === key || item.uid === key || item.sessionKey === key)
    if (exact) {
      return exact
    }
    const peerMatches = this.calls.filter((item: RtcIncomingCallRecord) => item.peerNumber === key)
    return peerMatches.length === 1 ? peerMatches[0] : undefined
  }

  private trim(): void {
    if (this.calls.length <= this.maxSize) {
      return
    }
    this.calls = this.calls
      .sort((left: RtcIncomingCallRecord, right: RtcIncomingCallRecord) => left.receivedAt - right.receivedAt)
      .slice(this.calls.length - this.maxSize)
  }

  private emit(): void {
    const snapshot = this.getSnapshot()
    this.listeners.forEach((listener: RtcIncomingCallQueueListener) => {
      listener(snapshot)
    })
  }

  private resolveNextVisibleCallId(excludeCallId: string): string {
    const next = this.calls.find((item: RtcIncomingCallRecord) => item.callId !== excludeCallId && item.visible)
    return next?.callId || ''
  }

  private static resolveKey(options: RtcIncomingCallQueueItemOptions): string {
    if (options.callId) {
      return options.callId
    }
    if (options.uid) {
      return options.uid
    }
    if (options.sessionKey) {
      return options.sessionKey
    }
    const target = options.target
    const identity = target.identity || target.locId || target.deviceIp || target.ip || ''
    return `${target.number}|${identity}|${target.clientType || ''}|${options.mode || RtcCallMode.AUDIO}`
  }

  private static copyRecord(record: RtcIncomingCallRecord): RtcIncomingCallRecord {
    const copy = new RtcIncomingCallRecord()
    copy.callId = record.callId
    copy.uid = record.uid
    copy.key = record.key
    copy.sessionKey = record.sessionKey
    copy.peerNumber = record.peerNumber
    copy.target = RtcIncomingCallQueue.copyTarget(record.target)
    copy.mode = record.mode
    copy.phase = record.phase
    copy.autoAnswer = record.autoAnswer
    copy.isHold = record.isHold
    copy.status = record.status
    copy.direction = record.direction
    copy.sortWeight = record.sortWeight
    copy.receivedAt = record.receivedAt
    copy.connectedAt = record.connectedAt
    copy.updatedAt = record.updatedAt
    copy.visible = record.visible
    copy.endReason = record.endReason
    return copy
  }

  private static copyTarget(target: RtcCallTarget): RtcCallTarget {
    return {
      number: target.number,
      displayName: target.displayName,
      clientType: target.clientType,
      identity: target.identity,
      ip: target.ip,
      locId: target.locId,
      hospitalId: target.hospitalId,
      deviceIp: target.deviceIp
    }
  }

  private static matches(record: RtcIncomingCallRecord, callId: string): boolean {
    return record.callId === callId ||
      record.key === callId ||
      record.uid === callId ||
      record.sessionKey === callId ||
      record.peerNumber === callId
  }
}
