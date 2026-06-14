import { RtcCallMode } from '../model/RtcCallConfig'

export const RTC_CALL_LIFECYCLE_CHANNEL_PUBLISH = 'publish'
export const RTC_CALL_LIFECYCLE_CHANNEL_SUBSCRIBE = 'subscribe'

export type RtcCallLifecycleChannelType = 'publish' | 'subscribe'
export type RtcCallLifecycleDirection = 'incoming' | 'outgoing' | 'none'
export type RtcCallLifecyclePhase = 'incoming' | 'outgoing' | 'answering' | 'answered' | 'held' | 'ended' | 'error'

export interface RtcCallLifecycleStateTimes {
  incoming?: number
  outgoing?: number
  answering?: number
  answered?: number
  held?: number
  ended?: number
  error?: number
}

export interface RtcCallLifecycleUpsertOptions {
  uid: string
  number?: string
  name?: string
  direction?: RtcCallLifecycleDirection
  phase?: RtcCallLifecyclePhase
  mode?: RtcCallMode
  uplinkMuted?: boolean
  from?: string
  to?: string
  fromName?: string
  toName?: string
  clientType?: string
  locId?: string
  hospitalId?: string
  isCalling?: boolean
}

export interface RtcCallLifecycleSession {
  uid: string
  number: string
  name: string
  direction: RtcCallLifecycleDirection
  phase: RtcCallLifecyclePhase
  mode: RtcCallMode
  isSelected: boolean
  uplinkMuted: boolean
  from: string
  to: string
  fromName: string
  toName: string
  clientType: string
  locId: string
  hospitalId: string
  errorMessage: string
  offline: boolean
  isCalling: boolean
  stateTimes: RtcCallLifecycleStateTimes
  lastUpdatedAt: number
}

export interface RtcCallLifecyclePeerSession {
  key: string
  uid: string
  rtcUID: string
  channelType: RtcCallLifecycleChannelType
  from: string
  to: string
  lastUpdatedAt: number
}

export interface RtcCallLifecycleSnapshot {
  selectedUid: string
  calls: RtcCallLifecycleSession[]
  peers: RtcCallLifecyclePeerSession[]
}

export interface RtcCallLifecycleResolveResult {
  handled: boolean
  reason: string
  uid: string
}

export class RtcCallLifecycleStore {
  private calls: Map<string, RtcCallLifecycleSession> = new Map()
  private peers: Map<string, RtcCallLifecyclePeerSession> = new Map()
  private selectedUid: string = ''

  upsertCall(options: RtcCallLifecycleUpsertOptions): RtcCallLifecycleSession | undefined {
    const uid = RtcCallLifecycleStore.normalizeUid(options.uid)
    if (!uid) {
      return undefined
    }
    const now = Date.now()
    const existing = this.calls.get(uid)
    const phase = this.resolvePhase(options, existing)
    const session: RtcCallLifecycleSession = existing || {
      uid,
      number: '',
      name: '',
      direction: 'none',
      phase,
      mode: RtcCallMode.AUDIO,
      isSelected: false,
      uplinkMuted: true,
      from: '',
      to: '',
      fromName: '',
      toName: '',
      clientType: '',
      locId: '',
      hospitalId: '',
      errorMessage: '',
      offline: false,
      isCalling: false,
      stateTimes: {},
      lastUpdatedAt: now
    }

    session.number = options.number || session.number
    session.name = options.name || session.name
    session.direction = options.direction || session.direction
    session.phase = phase
    session.mode = options.mode || session.mode
    if (options.uplinkMuted !== undefined) {
      session.uplinkMuted = options.uplinkMuted
    }
    session.from = options.from || session.from
    session.to = options.to || session.to
    session.fromName = options.fromName || session.fromName
    session.toName = options.toName || session.toName
    session.clientType = options.clientType || session.clientType
    session.locId = options.locId || session.locId
    session.hospitalId = options.hospitalId || session.hospitalId
    if (options.isCalling !== undefined) {
      session.isCalling = options.isCalling
    }
    session.offline = false
    session.lastUpdatedAt = now
    session.stateTimes[session.phase] = now

    this.calls.set(uid, session)
    if (!this.selectedUid) {
      this.selectedUid = uid
    }
    this.syncSelectedFlags()
    return this.copyCall(session)
  }

  upsertPeer(
    uid: string,
    rtcUID: string,
    channelType: RtcCallLifecycleChannelType,
    from: string,
    to: string
  ): RtcCallLifecyclePeerSession | undefined {
    const signalUid = RtcCallLifecycleStore.normalizeUid(uid)
    const rtcUid = RtcCallLifecycleStore.normalizeUid(rtcUID)
    const channel = RtcCallLifecycleStore.normalizeChannelType(channelType)
    if (!signalUid || !rtcUid) {
      return undefined
    }
    const key = RtcCallLifecycleStore.peerKey(signalUid, rtcUid, channel)
    const peer: RtcCallLifecyclePeerSession = {
      key,
      uid: signalUid,
      rtcUID: rtcUid,
      channelType: channel,
      from,
      to,
      lastUpdatedAt: Date.now()
    }
    this.peers.set(key, peer)
    return this.copyPeer(peer)
  }

  markPhase(uid: string, phase: RtcCallLifecyclePhase, uplinkMuted?: boolean): boolean {
    const session = this.calls.get(RtcCallLifecycleStore.normalizeUid(uid))
    if (!session) {
      return false
    }
    session.phase = phase
    if (uplinkMuted !== undefined) {
      session.uplinkMuted = uplinkMuted
    }
    session.offline = phase === 'error' ? session.offline : false
    session.lastUpdatedAt = Date.now()
    session.stateTimes[phase] = session.lastUpdatedAt
    return true
  }

  markOffline(uid: string, message: string = 'offline'): boolean {
    const session = this.calls.get(RtcCallLifecycleStore.normalizeUid(uid))
    if (!session) {
      return false
    }
    session.phase = 'error'
    session.offline = true
    session.errorMessage = message
    session.lastUpdatedAt = Date.now()
    session.stateTimes.error = session.lastUpdatedAt
    return true
  }

  select(uid: string): boolean {
    const id = RtcCallLifecycleStore.normalizeUid(uid)
    if (!id || !this.calls.has(id)) {
      return false
    }
    this.selectedUid = id
    this.syncSelectedFlags()
    return true
  }

  remove(uid: string): boolean {
    const id = RtcCallLifecycleStore.normalizeUid(uid)
    if (!id) {
      return false
    }
    const removed = this.calls.delete(id)
    const peerKeys: string[] = []
    this.peers.forEach((peer: RtcCallLifecyclePeerSession, key: string) => {
      if (peer.uid === id) {
        peerKeys.push(key)
      }
    })
    peerKeys.forEach((key: string) => this.peers.delete(key))
    if (this.selectedUid === id) {
      const remaining = this.listCalls()
      this.selectedUid = remaining.length > 0 ? remaining[0].uid : ''
    }
    this.syncSelectedFlags()
    return removed
  }

  clear(): void {
    this.calls.clear()
    this.peers.clear()
    this.selectedUid = ''
  }

  get(uid: string): RtcCallLifecycleSession | undefined {
    const session = this.calls.get(RtcCallLifecycleStore.normalizeUid(uid))
    return session ? this.copyCall(session) : undefined
  }

  resolveUid(uid: string, operation: string, allowSingleCallFallback: boolean = false):
    RtcCallLifecycleResolveResult {
    const id = RtcCallLifecycleStore.normalizeUid(uid)
    if (id && this.calls.has(id)) {
      return { handled: true, reason: operation, uid: id }
    }
    if (id) {
      return { handled: false, reason: 'unknown uid', uid: id }
    }
    const calls = this.listCalls()
    if (allowSingleCallFallback && calls.length === 1) {
      return { handled: true, reason: operation + ' by single call fallback', uid: calls[0].uid }
    }
    return { handled: false, reason: calls.length > 1 ? 'ambiguous uid' : 'missing uid', uid: '' }
  }

  resolveUidOrUniqueNumber(uid: string, number: string, operation: string, allowNumberFallback: boolean = true):
    RtcCallLifecycleResolveResult {
    const resolved = this.resolveUid(uid, operation, false)
    if (resolved.handled || resolved.uid) {
      return resolved
    }
    if (!allowNumberFallback) {
      return resolved
    }
    const target = (number || '').trim()
    if (!target) {
      return resolved
    }
    const matches = this.listCalls().filter((session: RtcCallLifecycleSession) => session.number === target)
    if (matches.length === 1) {
      return { handled: true, reason: operation + ' by unique number fallback', uid: matches[0].uid }
    }
    return { handled: false, reason: matches.length > 1 ? 'ambiguous number' : 'unknown number', uid: '' }
  }

  snapshot(): RtcCallLifecycleSnapshot {
    return {
      selectedUid: this.selectedUid,
      calls: this.listCalls(),
      peers: this.listPeers()
    }
  }

  listCalls(): RtcCallLifecycleSession[] {
    const calls: RtcCallLifecycleSession[] = []
    this.calls.forEach((session: RtcCallLifecycleSession) => calls.push(this.copyCall(session)))
    calls.sort((left: RtcCallLifecycleSession, right: RtcCallLifecycleSession) =>
      left.lastUpdatedAt - right.lastUpdatedAt)
    return calls
  }

  listPeers(): RtcCallLifecyclePeerSession[] {
    const peers: RtcCallLifecyclePeerSession[] = []
    this.peers.forEach((peer: RtcCallLifecyclePeerSession) => peers.push(this.copyPeer(peer)))
    peers.sort((left: RtcCallLifecyclePeerSession, right: RtcCallLifecyclePeerSession) =>
      left.lastUpdatedAt - right.lastUpdatedAt)
    return peers
  }

  static peerKey(uid: string, rtcUID: string, channelType: RtcCallLifecycleChannelType): string {
    return uid + ':' + channelType + ':' + rtcUID
  }

  static normalizeChannelType(channelType?: string): RtcCallLifecycleChannelType {
    return channelType === RTC_CALL_LIFECYCLE_CHANNEL_SUBSCRIBE ?
      RTC_CALL_LIFECYCLE_CHANNEL_SUBSCRIBE : RTC_CALL_LIFECYCLE_CHANNEL_PUBLISH
  }

  static normalizeUid(uid?: string): string {
    return (uid || '').trim()
  }

  private resolvePhase(
    options: RtcCallLifecycleUpsertOptions,
    existing?: RtcCallLifecycleSession
  ): RtcCallLifecyclePhase {
    const next = options.phase || (options.direction === 'outgoing' ? 'outgoing' : 'incoming')
    if (existing?.phase === 'answered' && (next === 'incoming' || next === 'outgoing')) {
      return 'answered'
    }
    return next
  }

  private syncSelectedFlags(): void {
    this.calls.forEach((session: RtcCallLifecycleSession) => {
      session.isSelected = !!this.selectedUid && session.uid === this.selectedUid
    })
  }

  private copyCall(session: RtcCallLifecycleSession): RtcCallLifecycleSession {
    return {
      uid: session.uid,
      number: session.number,
      name: session.name,
      direction: session.direction,
      phase: session.phase,
      mode: session.mode,
      isSelected: session.isSelected,
      uplinkMuted: session.uplinkMuted,
      from: session.from,
      to: session.to,
      fromName: session.fromName,
      toName: session.toName,
      clientType: session.clientType,
      locId: session.locId,
      hospitalId: session.hospitalId,
      errorMessage: session.errorMessage,
      offline: session.offline,
      isCalling: session.isCalling,
      stateTimes: {
        incoming: session.stateTimes.incoming,
        outgoing: session.stateTimes.outgoing,
        answering: session.stateTimes.answering,
        answered: session.stateTimes.answered,
        held: session.stateTimes.held,
        ended: session.stateTimes.ended,
        error: session.stateTimes.error
      },
      lastUpdatedAt: session.lastUpdatedAt
    }
  }

  private copyPeer(peer: RtcCallLifecyclePeerSession): RtcCallLifecyclePeerSession {
    return {
      key: peer.key,
      uid: peer.uid,
      rtcUID: peer.rtcUID,
      channelType: peer.channelType,
      from: peer.from,
      to: peer.to,
      lastUpdatedAt: peer.lastUpdatedAt
    }
  }
}
