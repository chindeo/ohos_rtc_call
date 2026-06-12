import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallTarget } from './RtcCallService'

export type RtcIncomingCallQueuePhase = 'incoming' | 'accepted' | 'ended'

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
  sortWeight?: number
  receivedAt?: number
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
  sortWeight: number = 999999
  receivedAt: number = 0
  updatedAt: number = 0
  visible: boolean = true
  endReason: string = ''
}

export class RtcIncomingCallQueueSnapshot {
  calls: RtcIncomingCallRecord[] = []
  activeCallId: string = ''
  pendingCount: number = 0
}

export type RtcIncomingCallQueueListener = (snapshot: RtcIncomingCallQueueSnapshot) => void

export class RtcIncomingCallQueue {
  private calls: RtcIncomingCallRecord[] = []
  private activeCallId: string = ''
  private maxSize: number
  private listeners: RtcIncomingCallQueueListener[] = []

  constructor(options?: RtcIncomingCallQueueOptions) {
    this.maxSize = options?.maxSize || 12
  }

  upsert(options: RtcIncomingCallQueueItemOptions): RtcIncomingCallRecord {
    const now = options.receivedAt || Date.now()
    const key = RtcIncomingCallQueue.resolveKey(options)
    let record = this.calls.find((item: RtcIncomingCallRecord) => item.key === key)
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
    record.sortWeight = options.sortWeight !== undefined ? options.sortWeight : record.sortWeight
    record.phase = 'incoming'
    record.visible = true
    record.endReason = ''
    record.updatedAt = now

    this.trim()
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  accept(callId: string): RtcIncomingCallRecord | undefined {
    const record = this.find(callId)
    if (!record) {
      return undefined
    }
    record.phase = 'accepted'
    record.status = record.status || 'accepted'
    record.visible = true
    record.updatedAt = Date.now()
    this.activeCallId = record.callId
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
    this.emit()
    return RtcIncomingCallQueue.copyRecord(record)
  }

  remove(callId: string): void {
    this.calls = this.calls.filter((item: RtcIncomingCallRecord) => !RtcIncomingCallQueue.matches(item, callId))
    if (this.activeCallId === callId) {
      this.activeCallId = ''
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
    this.emit()
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
    return this.calls.find((item: RtcIncomingCallRecord) => RtcIncomingCallQueue.matches(item, callId))
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
    copy.sortWeight = record.sortWeight
    copy.receivedAt = record.receivedAt
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
