import {
  RTC_CALL_LIFECYCLE_CHANNEL_SUBSCRIBE,
  RtcCallLifecycleChannelType,
  RtcCallLifecycleDirection,
  RtcCallLifecyclePeerSession,
  RtcCallLifecyclePhase,
  RtcCallLifecycleSession,
  RtcCallLifecycleStore
} from '../core/RtcCallLifecycleStore'
import { RtcCallMode } from '../model/RtcCallConfig'
import {
  RTC_CALL_GATEWAY_CHANNEL_PUBLISH,
  RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE,
  RtcCallGatewayCallSession,
  RtcCallGatewayChannelType,
  RtcCallGatewayDirection,
  RtcCallGatewayOpenActivityOptions,
  RtcCallGatewayOperationResult,
  RtcCallGatewayPeerSession,
  RtcCallGatewayPhase,
  RtcCallGatewaySnapshot
} from './RtcCallGatewayTypes'

export class RtcCallGatewaySessionStore {
  private lifecycle: RtcCallLifecycleStore = new RtcCallLifecycleStore()

  upsertOpenActivity(options: RtcCallGatewayOpenActivityOptions): RtcCallGatewayCallSession | undefined {
    const phase: RtcCallLifecyclePhase = options.isOut ? 'outgoing' : 'incoming'
    const session = this.lifecycle.upsertCall({
      uid: options.uid,
      number: options.num,
      name: options.name,
      direction: options.isOut ? 'outgoing' : 'incoming',
      phase,
      mode: options.isVideo === true ? RtcCallMode.VIDEO : undefined,
      uplinkMuted: true
    })
    return session ? this.toGatewayCall(session) : undefined
  }

  upsertPeer(
    uid: string,
    rtcUID: string,
    channelType: RtcCallGatewayChannelType,
    from: string,
    to: string
  ): RtcCallGatewayPeerSession | undefined {
    const peer = this.lifecycle.upsertPeer(
      uid,
      rtcUID,
      RtcCallGatewaySessionStore.normalizeChannelType(channelType),
      from,
      to
    )
    return peer ? this.toGatewayPeer(peer) : undefined
  }

  markPhase(uid: string, phase: RtcCallGatewayPhase, uplinkMuted?: boolean): boolean {
    return this.lifecycle.markPhase(uid, phase, uplinkMuted)
  }

  select(uid: string): boolean {
    return this.lifecycle.select(uid)
  }

  remove(uid: string): boolean {
    return this.lifecycle.remove(uid)
  }

  clear(): void {
    this.lifecycle.clear()
  }

  get(uid: string): RtcCallGatewayCallSession | undefined {
    const session = this.lifecycle.get(uid)
    return session ? this.toGatewayCall(session) : undefined
  }

  resolveUid(uid: string, operation: string, allowSingleCallFallback: boolean = false): RtcCallGatewayOperationResult {
    return this.lifecycle.resolveUid(uid, operation, allowSingleCallFallback)
  }

  snapshot(): RtcCallGatewaySnapshot {
    const snapshot = this.lifecycle.snapshot()
    return {
      selectedUid: snapshot.selectedUid,
      calls: this.listCalls(),
      peers: this.listPeers()
    }
  }

  listCalls(): RtcCallGatewayCallSession[] {
    return this.lifecycle.listCalls().map((session: RtcCallLifecycleSession) => this.toGatewayCall(session))
  }

  listPeers(): RtcCallGatewayPeerSession[] {
    return this.lifecycle.listPeers().map((peer: RtcCallLifecyclePeerSession) => this.toGatewayPeer(peer))
  }

  static peerKey(uid: string, rtcUID: string, channelType: RtcCallGatewayChannelType): string {
    return RtcCallLifecycleStore.peerKey(uid, rtcUID, RtcCallGatewaySessionStore.normalizeChannelType(channelType))
  }

  static normalizeChannelType(channelType?: string): RtcCallGatewayChannelType {
    return channelType === RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE ?
      RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE : RTC_CALL_GATEWAY_CHANNEL_PUBLISH
  }

  private toGatewayCall(session: RtcCallLifecycleSession): RtcCallGatewayCallSession {
    return {
      uid: session.uid,
      number: session.number,
      name: session.name,
      direction: this.toGatewayDirection(session.direction),
      phase: this.toGatewayPhase(session.phase),
      mode: session.mode,
      isSelected: session.isSelected,
      uplinkMuted: session.uplinkMuted,
      lastUpdatedAt: session.lastUpdatedAt
    }
  }

  private toGatewayPeer(peer: RtcCallLifecyclePeerSession): RtcCallGatewayPeerSession {
    return {
      key: peer.key,
      uid: peer.uid,
      rtcUID: peer.rtcUID,
      channelType: this.toGatewayChannel(peer.channelType),
      from: peer.from,
      to: peer.to,
      lastUpdatedAt: peer.lastUpdatedAt
    }
  }

  private toGatewayDirection(direction: RtcCallLifecycleDirection): RtcCallGatewayDirection {
    return direction === 'outgoing' ? 'outgoing' : 'incoming'
  }

  private toGatewayPhase(phase: RtcCallLifecyclePhase): RtcCallGatewayPhase {
    if (phase === 'answering' || phase === 'answered' || phase === 'held' || phase === 'ended') {
      return phase
    }
    if (phase === 'outgoing') {
      return 'outgoing'
    }
    return 'incoming'
  }

  private toGatewayChannel(channelType: RtcCallLifecycleChannelType): RtcCallGatewayChannelType {
    return channelType === RTC_CALL_LIFECYCLE_CHANNEL_SUBSCRIBE ?
      RTC_CALL_GATEWAY_CHANNEL_SUBSCRIBE : RTC_CALL_GATEWAY_CHANNEL_PUBLISH
  }
}
