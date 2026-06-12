import { RtcCallMode } from '../model/RtcCallConfig'
import { RtcCallTarget } from './RtcCallService'

export interface RtcCallSessionStoreUpsertOptions {
  uid?: string
  peerNumber?: string
  displayName?: string
  from?: string
  to?: string
  status?: string
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
  status: string = ''
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
    session.status = options.status !== undefined ? options.status : session.status
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
    copy.status = session.status
    copy.isHold = session.isHold
    copy.mode = session.mode
    copy.updatedAt = session.updatedAt
    return copy
  }
}
