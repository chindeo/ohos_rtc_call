import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallTarget } from './RtcCallService'

export interface RtcCallSessionStoreUpsertOptions {
  uid?: string
  peerNumber?: string
  displayName?: string
  from?: string
  to?: string
  fromName?: string
  toName?: string
  clientType?: string
  locId?: string
  hospitalId?: string
  isCallout?: boolean
  status?: string
  errorMessage?: string
  offline?: boolean
  isCalling?: boolean
  isHold?: boolean
  mode?: RtcCallMode
  target?: RtcCallTarget
}

export class RtcStoredCallSession {
  uid: string = ''
  peerNumber: string = ''
  displayName: string = ''
  from: string = ''
  to: string = ''
  fromName: string = ''
  toName: string = ''
  clientType: string = ''
  locId: string = ''
  hospitalId: string = ''
  isCallout: boolean = false
  status: string = ''
  stateTimes: Record<string, number> = {}
  errorMessage: string = ''
  offline: boolean = false
  isCalling: boolean = false
  isHold: boolean = false
  mode: RtcCallMode = RtcCallMode.AUDIO
  updatedAt: number = 0
}

export class RtcCallSessionStoreSnapshot {
  sessions: RtcStoredCallSession[] = []
  size: number = 0
}

export class RtcCallSessionStore {
  private sessions: RtcStoredCallSession[] = []
  private version: number = 0

  upsert(options: RtcCallSessionStoreUpsertOptions): RtcStoredCallSession | undefined {
    const uid = (options.uid || '').trim()
    const peer = RtcCallSessionStore.normalizePeer(options.peerNumber || options.target?.number || '')
    if (!uid || !peer) {
      return undefined
    }

    let session = this.sessions.find((item: RtcStoredCallSession) => item.uid === uid)
    if (!session) {
      session = new RtcStoredCallSession()
      session.uid = uid
      this.sessions.push(session)
    }

    session.peerNumber = peer
    session.displayName = options.displayName || options.target?.displayName || session.displayName
    session.from = options.from !== undefined ? options.from : session.from
    session.to = options.to !== undefined ? options.to : session.to
    session.fromName = options.fromName !== undefined ? options.fromName : session.fromName
    session.toName = options.toName !== undefined ? options.toName : session.toName
    session.clientType = options.clientType || options.target?.clientType || session.clientType
    session.locId = options.locId || options.target?.locId || session.locId
    session.hospitalId = options.hospitalId || options.target?.hospitalId || session.hospitalId
    session.isCallout = options.isCallout !== undefined ? options.isCallout === true : session.isCallout
    session.status = options.status !== undefined ? options.status : session.status
    if (options.status) {
      session.stateTimes[options.status] = Date.now()
    }
    session.errorMessage = options.errorMessage !== undefined ? options.errorMessage : session.errorMessage
    session.offline = options.offline !== undefined ? options.offline === true : session.offline
    session.isCalling = options.isCalling !== undefined ? options.isCalling === true : session.isCalling
    session.isHold = options.isHold !== undefined ? options.isHold === true : session.isHold
    session.mode = options.mode || session.mode
    this.version += 1
    session.updatedAt = this.version
    return RtcCallSessionStore.copySession(session)
  }

  findByUid(uid?: string): RtcStoredCallSession | undefined {
    const key = (uid || '').trim()
    if (!key) {
      return undefined
    }
    const session = this.sessions.find((item: RtcStoredCallSession) => item.uid === key)
    return session ? RtcCallSessionStore.copySession(session) : undefined
  }

  findByPeer(peerNumber?: string): RtcStoredCallSession | undefined {
    const peer = RtcCallSessionStore.normalizePeer(peerNumber || '')
    if (!peer) {
      return undefined
    }
    const matches = this.sessions
      .filter((item: RtcStoredCallSession) => item.peerNumber === peer)
      .sort((left: RtcStoredCallSession, right: RtcStoredCallSession) => left.updatedAt - right.updatedAt)
    const session = matches.length > 0 ? matches[matches.length - 1] : undefined
    return session ? RtcCallSessionStore.copySession(session) : undefined
  }

  uidForPeer(peerNumber?: string): string {
    return this.findByPeer(peerNumber)?.uid || ''
  }

  sessionKey(uid?: string, peerNumber?: string): string {
    const key = (uid || '').trim()
    if (key) {
      return key
    }
    return this.uidForPeer(peerNumber) || RtcCallSessionStore.normalizePeer(peerNumber || '')
  }

  markHold(uidOrPeer: string, isHold: boolean): RtcStoredCallSession | undefined {
    const session = this.findMutable(uidOrPeer)
    if (!session) {
      return undefined
    }
    session.isHold = isHold
    this.version += 1
    session.updatedAt = this.version
    return RtcCallSessionStore.copySession(session)
  }

  removeUid(uid?: string): void {
    const key = (uid || '').trim()
    if (!key) {
      return
    }
    this.sessions = this.sessions.filter((item: RtcStoredCallSession) => item.uid !== key)
  }

  removePeer(peerNumber?: string): void {
    const peer = RtcCallSessionStore.normalizePeer(peerNumber || '')
    if (!peer) {
      return
    }
    this.sessions = this.sessions.filter((item: RtcStoredCallSession) => item.peerNumber !== peer)
  }

  clear(): void {
    this.sessions = []
    this.version = 0
  }

  snapshot(): RtcCallSessionStoreSnapshot {
    const snapshot = new RtcCallSessionStoreSnapshot()
    snapshot.sessions = this.sessions
      .slice()
      .sort((left: RtcStoredCallSession, right: RtcStoredCallSession) => right.updatedAt - left.updatedAt)
      .map((item: RtcStoredCallSession) => RtcCallSessionStore.copySession(item))
    snapshot.size = snapshot.sessions.length
    return snapshot
  }

  private findMutable(uidOrPeer: string): RtcStoredCallSession | undefined {
    const key = (uidOrPeer || '').trim()
    if (!key) {
      return undefined
    }
    const byUid = this.sessions.find((item: RtcStoredCallSession) => item.uid === key)
    if (byUid) {
      return byUid
    }
    const peer = RtcCallSessionStore.normalizePeer(key)
    const matches = this.sessions
      .filter((item: RtcStoredCallSession) => item.peerNumber === peer)
      .sort((left: RtcStoredCallSession, right: RtcStoredCallSession) => left.updatedAt - right.updatedAt)
    return matches.length > 0 ? matches[matches.length - 1] : undefined
  }

  static normalizePeer(peerNumber: string): string {
    return (peerNumber || '').split(',')[0].trim()
  }

  static resolvePeer(from?: string, to?: string, self?: string, fallback?: string): string {
    const selfNumber = (self || '').trim()
    const fromList = RtcCallSessionStore.splitNumbers(from || '')
    const toList = RtcCallSessionStore.splitNumbers(to || '')
    if (selfNumber && fromList.indexOf(selfNumber) >= 0) {
      return toList[0] || ''
    }
    if (selfNumber && toList.indexOf(selfNumber) >= 0) {
      return fromList[0] || ''
    }
    if (fallback) {
      return fallback.trim()
    }
    return fromList[0] || toList[0] || ''
  }

  private static splitNumbers(value: string): string[] {
    return (value || '').split(',').map((item: string) => item.trim()).filter((item: string) => item.length > 0)
  }

  private static copySession(session: RtcStoredCallSession): RtcStoredCallSession {
    const copy = new RtcStoredCallSession()
    copy.uid = session.uid
    copy.peerNumber = session.peerNumber
    copy.displayName = session.displayName
    copy.from = session.from
    copy.to = session.to
    copy.fromName = session.fromName
    copy.toName = session.toName
    copy.clientType = session.clientType
    copy.locId = session.locId
    copy.hospitalId = session.hospitalId
    copy.isCallout = session.isCallout
    copy.status = session.status
    const stateTimes: Record<string, number> = {}
    Object.keys(session.stateTimes).forEach((key: string) => {
      stateTimes[key] = session.stateTimes[key]
    })
    copy.stateTimes = stateTimes
    copy.errorMessage = session.errorMessage
    copy.offline = session.offline
    copy.isCalling = session.isCalling
    copy.isHold = session.isHold
    copy.mode = session.mode
    copy.updatedAt = session.updatedAt
    return copy
  }
}
