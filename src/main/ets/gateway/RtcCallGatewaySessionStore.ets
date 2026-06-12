import { RtcCallMode } from '../model/RtcCallConfig'
import {
  RTC_CALL_GATEWAY_CHANNEL_PUBLISH,
  RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE,
  RtcCallGatewayCallSession,
  RtcCallGatewayChannelType,
  RtcCallGatewayOpenActivityOptions,
  RtcCallGatewayOperationResult,
  RtcCallGatewayPeerSession,
  RtcCallGatewayPhase,
  RtcCallGatewaySnapshot
} from './RtcCallGatewayTypes'

export class RtcCallGatewaySessionStore {
  private calls: Map<string, RtcCallGatewayCallSession> = new Map()
  private peers: Map<string, RtcCallGatewayPeerSession> = new Map()
  private selectedUid: string = ''

  upsertOpenActivity(options: RtcCallGatewayOpenActivityOptions): RtcCallGatewayCallSession | undefined {
    const uid = this.normalizeUid(options.uid)
    if (!uid) {
      return undefined
    }
    const now = Date.now()
    const existing = this.calls.get(uid)
    const phase: RtcCallGatewayPhase = options.isOut ? 'outgoing' : 'incoming'
    const session: RtcCallGatewayCallSession = {
      uid,
      number: options.num || existing?.number || '',
      name: options.name || existing?.name || '',
      direction: options.isOut ? 'outgoing' : 'incoming',
      phase: existing?.phase === 'answered' ? 'answered' : phase,
      mode: options.isVideo === true ? RtcCallMode.VIDEO : (existing?.mode || RtcCallMode.AUDIO),
      isSelected: existing?.isSelected === true,
      uplinkMuted: existing?.uplinkMuted !== false,
      lastUpdatedAt: now
    }
    this.calls.set(uid, session)
    if (!this.selectedUid) {
      this.selectedUid = uid
      session.isSelected = true
    }
    this.syncSelectedFlags()
    return this.copyCall(session)
  }

  upsertPeer(
    uid: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    from: string,
    to: string
  ): RtcCallGatewayPeerSession | undefined {
    const signalUid = this.normalizeUid(uid)
    const rtcUid = (rtcUID || '').trim()
    const channel = RtcCallGatewaySessionStore.normalizeChannelType(channelType)
    if (!signalUid || !rtcUid) {
      return undefined
    }
    const key = RtcCallGatewaySessionStore.peerKey(signalUid, rtcUid, channel)
    const peer: RtcCallGatewayPeerSession = {
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

  markPhase(uid: string, phase: RtcCallGatewayPhase, uplinkMuted?: boolean): boolean {
    const session = this.calls.get(this.normalizeUid(uid))
    if (!session) {
      return false
    }
    session.phase = phase
    if (uplinkMuted !== undefined) {
      session.uplinkMuted = uplinkMuted
    }
    session.lastUpdatedAt = Date.now()
    return true
  }

  select(uid: string): boolean {
    const id = this.normalizeUid(uid)
    if (!id || !this.calls.has(id)) {
      return false
    }
    this.selectedUid = id
    this.syncSelectedFlags()
    return true
  }

  remove(uid: string): boolean {
    const id = this.normalizeUid(uid)
    if (!id) {
      return false
    }
    const removed = this.calls.delete(id)
    const peerKeys: string[] = []
    this.peers.forEach((peer: RtcCallGatewayPeerSession, key: string) => {
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

  get(uid: string): RtcCallGatewayCallSession | undefined {
    const session = this.calls.get(this.normalizeUid(uid))
    return session ? this.copyCall(session) : undefined
  }

  resolveUid(uid: string, operation: string, allowSingleCallFallback: boolean = false): RtcCallGatewayOperationResult {
    const id = this.normalizeUid(uid)
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

  snapshot(): RtcCallGatewaySnapshot {
    return {
      selectedUid: this.selectedUid,
      calls: this.listCalls(),
      peers: this.listPeers()
    }
  }

  listCalls(): RtcCallGatewayCallSession[] {
    const calls: RtcCallGatewayCallSession[] = []
    this.calls.forEach((session: RtcCallGatewayCallSession) => calls.push(this.copyCall(session)))
    calls.sort((left: RtcCallGatewayCallSession, right: RtcCallGatewayCallSession) => left.lastUpdatedAt - right.lastUpdatedAt)
    return calls
  }

  listPeers(): RtcCallGatewayPeerSession[] {
    const peers: RtcCallGatewayPeerSession[] = []
    this.peers.forEach((peer: RtcCallGatewayPeerSession) => peers.push(this.copyPeer(peer)))
    peers.sort((left: RtcCallGatewayPeerSession, right: RtcCallGatewayPeerSession) => left.lastUpdatedAt - right.lastUpdatedAt)
    return peers
  }

  static peerKey(uid: string, rtcUID: string, channelType: RtcCallGatewayChannelType): string {
    return uid + ':' + channelType + ':' + rtcUID
  }

  static normalizeChannelType(channelType?: string): RtcCallGatewayChannelType {
    return channelType === RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE ?
      RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE : RTC_CALL_GATEWAY_CHANNEL_PUBLISH
  }

  private normalizeUid(uid?: string): string {
    return (uid || '').trim()
  }

  private syncSelectedFlags(): void {
    this.calls.forEach((session: RtcCallGatewayCallSession) => {
      session.isSelected = !!this.selectedUid && session.uid === this.selectedUid
    })
  }

  private copyCall(session: RtcCallGatewayCallSession): RtcCallGatewayCallSession {
    return {
      uid: session.uid,
      number: session.number,
      name: session.name,
      direction: session.direction,
      phase: session.phase,
      mode: session.mode,
      isSelected: session.isSelected,
      uplinkMuted: session.uplinkMuted,
      lastUpdatedAt: session.lastUpdatedAt
    }
  }

  private copyPeer(peer: RtcCallGatewayPeerSession): RtcCallGatewayPeerSession {
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
