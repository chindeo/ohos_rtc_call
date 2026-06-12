import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallTarget } from './RtcCallService'

export type RtcIncomingCallQueuePhase = 'incoming' | 'accepted' | 'ended'

export interface RtcIncomingCallQueueOptions {
  maxSize?: number
}

export interface RtcIncomingCallQueueItemOptions {
  callId?: string
  target: RtcCallTarget
  mode?: RtcCallMode
  autoAnswer?: boolean
  receivedAt?: number
}

export class RtcIncomingCallRecord {
  callId: string = ''
  key: string = ''
  target: RtcCallTarget = { number: '' }
  mode: RtcCallMode = RtcCallMode.AUDIO
  phase: RtcIncomingCallQueuePhase = 'incoming'
  autoAnswer: boolean = false
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
      record.receivedAt = now
      this.calls.push(record)
    }

    record.target = RtcIncomingCallQueue.copyTarget(options.target)
    record.mode = options.mode || RtcCallMode.AUDIO
    record.autoAnswer = options.autoAnswer === true
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
    this.calls = this.calls.filter((item: RtcIncomingCallRecord) => item.callId !== callId && item.key !== callId)
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
    snapshot.calls = this.calls.map((item: RtcIncomingCallRecord) => RtcIncomingCallQueue.copyRecord(item))
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
    return this.calls.find((item: RtcIncomingCallRecord) => item.callId === callId || item.key === callId)
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
    const target = options.target
    const identity = target.identity || target.locId || target.deviceIp || target.ip || ''
    return `${target.number}|${identity}|${target.clientType || ''}|${options.mode || RtcCallMode.AUDIO}`
  }

  private static copyRecord(record: RtcIncomingCallRecord): RtcIncomingCallRecord {
    const copy = new RtcIncomingCallRecord()
    copy.callId = record.callId
    copy.key = record.key
    copy.target = RtcIncomingCallQueue.copyTarget(record.target)
    copy.mode = record.mode
    copy.phase = record.phase
    copy.autoAnswer = record.autoAnswer
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
}
