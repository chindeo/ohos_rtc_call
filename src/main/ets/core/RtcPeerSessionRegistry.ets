export const RTC_PEER_SESSION_CHANNEL_PUBLISH = 'publish'
export const RTC_PEER_SESSION_CHANNEL_SUBSCRIBE = 'subscribe'
const RTC_PEER_SESSION_CHANNEL_LEGACY = 'legacy'
const RTC_PEER_SESSION_DEFAULT_TARGET = '__default__'

export enum RtcPeerSessionAction {
  CREATE = 'create',
  REUSE = 'reuse',
  RECREATE = 'recreate',
  CACHE_ICE = 'cache_ice',
  DROP_OVERFLOW = 'drop_overflow',
  IGNORE_CLOSING = 'ignore_closing',
  MISS = 'miss'
}

export class RtcPeerSessionRouteResult {
  action: RtcPeerSessionAction = RtcPeerSessionAction.MISS
  key: string = ''
  reason: string = ''
}

class RtcPeerSessionRemoteState {
  key: string
  remoteDescriptionApplied: boolean = false
  pendingIceCount: number = 0

  constructor(key: string) {
    this.key = key
  }
}

export class RtcPeerSession {
  key: string
  uid: string
  target: string
  rtcUid: string
  channelType: string
  closed: boolean = false
  publishConnected: boolean = false
  publishSenders: number = 0
  subscribeConnected: boolean = false
  subscribeReceivers: number = 0
  remoteDescriptionApplied: boolean = false
  pendingIceCount: number = 0
  hold: boolean = false

  constructor(key: string, uid: string, target: string, rtcUid: string, channelType: string) {
    this.key = key
    this.uid = RtcPeerSessionPolicy.trim(uid)
    this.target = RtcPeerSessionPolicy.normalizeTargetNumber(target)
    this.rtcUid = RtcPeerSessionPolicy.trim(rtcUid)
    this.channelType = RtcPeerSessionPolicy.normalizeChannelType(channelType)
  }
}

export class RtcPeerSessionPolicy {
  static isSubscribeChannel(channelType?: string): boolean {
    return RtcPeerSessionPolicy.trim(channelType) === RTC_PEER_SESSION_CHANNEL_SUBSCRIBE
  }

  static normalizeChannelType(channelType?: string): string {
    return RtcPeerSessionPolicy.isSubscribeChannel(channelType) ?
    RTC_PEER_SESSION_CHANNEL_SUBSCRIBE : RTC_PEER_SESSION_CHANNEL_PUBLISH
  }

  static normalizeLegacyChannelType(channelType?: string): string {
    const resolved = RtcPeerSessionPolicy.trim(channelType)
    return resolved || RTC_PEER_SESSION_CHANNEL_LEGACY
  }

  static normalizeTargetNumber(targetNumber?: string): string {
    return RtcPeerSessionPolicy.trim(targetNumber)
  }

  static legacySessionKey(targetNumber?: string, rtcUid?: string, channelType?: string): string {
    const target = RtcPeerSessionPolicy.trim(targetNumber) || RTC_PEER_SESSION_DEFAULT_TARGET
    return target + '|' + RtcPeerSessionPolicy.trim(rtcUid) + '|' +
      RtcPeerSessionPolicy.normalizeLegacyChannelType(channelType)
  }

  static sessionKey(uid?: string, targetNumber?: string, rtcUid?: string, channelType?: string): string {
    const resolvedUid = RtcPeerSessionPolicy.trim(uid)
    if (resolvedUid) {
      const channel = RtcPeerSessionPolicy.normalizeChannelType(channelType)
      if (channel === RTC_PEER_SESSION_CHANNEL_SUBSCRIBE) {
        const target = RtcPeerSessionPolicy.trim(targetNumber) || RTC_PEER_SESSION_DEFAULT_TARGET
        return resolvedUid + '|' + target + '|' + channel
      }
      return resolvedUid + '|' + channel
    }
    return RtcPeerSessionPolicy.legacySessionKey(targetNumber, rtcUid, channelType)
  }

  static sameSessionScope(
    candidateKey: string,
    keepKey: string,
    uid?: string,
    targetNumber?: string,
    channelType?: string
  ): boolean {
    const candidate = RtcPeerSessionPolicy.trim(candidateKey)
    if (!candidate || candidate === RtcPeerSessionPolicy.trim(keepKey)) {
      return false
    }
    const channel = RtcPeerSessionPolicy.normalizeChannelType(channelType)
    const resolvedUid = RtcPeerSessionPolicy.trim(uid)
    const target = RtcPeerSessionPolicy.trim(targetNumber)
    if (resolvedUid) {
      const scopedKey = resolvedUid + '|' + (target || RTC_PEER_SESSION_DEFAULT_TARGET) + '|' + channel
      if (candidate === scopedKey) {
        return true
      }
      const uidOnlyKey = resolvedUid + '|' + channel
      if (candidate === uidOnlyKey && !target) {
        return true
      }
    }
    return !!target && candidate.indexOf(target + '|') === 0 && candidate.endsWith('|' + channel)
  }

  static answeredAudioMatchesPeer(recordedPeerKey?: string, currentPeerKey?: string): boolean {
    const recorded = RtcPeerSessionPolicy.trim(recordedPeerKey)
    const current = RtcPeerSessionPolicy.trim(currentPeerKey)
    if (!recorded) {
      return !!current
    }
    return recorded === current
  }

  static trim(value?: string): string {
    return (value || '').trim()
  }
}

export class RtcPeerSessionRegistry {
  private maxPendingIcePerSession: number
  private sessions: Map<string, RtcPeerSession> = new Map()
  private remoteStates: Map<string, RtcPeerSessionRemoteState> = new Map()
  private answeredAudioPeerKeys: Map<string, string> = new Map()
  private publishConnected: boolean = false
  private publishSenders: number = 0

  constructor(maxPendingIcePerSession: number = 64) {
    this.maxPendingIcePerSession = maxPendingIcePerSession
  }

  routeSubscribeOffer(uid: string, target: string, rtcUid: string, closing: boolean = false): RtcPeerSessionRouteResult {
    const key = this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    if (closing) {
      return this.result(RtcPeerSessionAction.IGNORE_CLOSING, key, 'closing')
    }
    return this.getOrCreateSubscribe(uid, target, rtcUid)
  }

  getOrCreateSubscribe(uid: string, target: string, rtcUid: string): RtcPeerSessionRouteResult {
    const key = this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    if (!RtcPeerSessionPolicy.normalizeTargetNumber(target)) {
      return this.result(RtcPeerSessionAction.MISS, key, 'missing_target')
    }

    const existing = this.findSubscribe(uid, target, rtcUid)
    if (existing && !existing.closed) {
      if (this.rtcUidChanged(existing, rtcUid)) {
        this.removeSession(existing)
        const created = this.createSubscribe(uid, target, rtcUid)
        return this.result(RtcPeerSessionAction.RECREATE, created.key, 'rtc_uid_changed')
      }
      if (!this.sessions.has(key)) {
        this.sessions.set(key, existing)
        this.removeDuplicateMappings(key, existing)
      }
      return this.result(RtcPeerSessionAction.REUSE, key, 'existing')
    }

    if (existing) {
      this.removeSession(existing)
      const created = this.createSubscribe(uid, target, rtcUid)
      return this.result(RtcPeerSessionAction.RECREATE, created.key, 'closed')
    }

    const created = this.createSubscribe(uid, target, rtcUid)
    return this.result(RtcPeerSessionAction.CREATE, created.key, 'missing')
  }

  receiveSubscribeIce(uid: string, target: string, rtcUid: string, closing: boolean = false): RtcPeerSessionRouteResult {
    const key = this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    if (closing) {
      return this.result(RtcPeerSessionAction.IGNORE_CLOSING, key, 'closing')
    }
    const session = this.sessions.get(key)
    if (session && session.remoteDescriptionApplied) {
      return this.result(RtcPeerSessionAction.REUSE, key, 'remote_description_applied')
    }
    let state = this.remoteStates.get(key)
    if (!state) {
      state = new RtcPeerSessionRemoteState(key)
      this.remoteStates.set(key, state)
    }
    if (state.pendingIceCount >= this.maxPendingIcePerSession) {
      return this.result(RtcPeerSessionAction.DROP_OVERFLOW, key, 'pending_ice_overflow')
    }
    state.pendingIceCount += 1
    return this.result(RtcPeerSessionAction.CACHE_ICE, key, 'pending_remote_description')
  }

  markRemoteDescriptionApplied(uid: string, target: string, rtcUid: string): void {
    const key = this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    const session = this.sessions.get(key)
    if (session) {
      session.remoteDescriptionApplied = true
      session.pendingIceCount = 0
    }
    const state = this.remoteStates.get(key)
    if (state) {
      state.remoteDescriptionApplied = true
      state.pendingIceCount = 0
    }
  }

  markPublishState(connected: boolean, senders: number): void {
    this.publishConnected = connected
    this.publishSenders = senders
  }

  markSubscribeState(uid: string, target: string, rtcUid: string, connected: boolean, receivers: number): void {
    const result = this.getOrCreateSubscribe(uid, target, rtcUid)
    const session = this.sessions.get(result.key)
    if (session) {
      session.subscribeConnected = connected
      session.subscribeReceivers = receivers
    }
  }

  markAnsweredAudio(targetOrUid: string, peerKey: string): void {
    const resolved = RtcPeerSessionPolicy.normalizeTargetNumber(targetOrUid)
    if (resolved) {
      this.answeredAudioPeerKeys.set(resolved, RtcPeerSessionPolicy.trim(peerKey))
    }
  }

  markHold(targetOrUid: string, hold: boolean): void {
    const session = this.findByTargetOrUid(targetOrUid)
    if (session) {
      session.hold = hold
    }
  }

  isAnswered(targetOrUid: string): boolean {
    const resolved = RtcPeerSessionPolicy.normalizeTargetNumber(targetOrUid)
    if (!resolved) {
      return false
    }
    const session = this.findByTargetOrUid(resolved)
    if (!session || session.closed) {
      return false
    }
    const hasAudioOnTrack = this.hasAnsweredAudio(resolved, session)
    const subscribeReady = session.subscribeConnected || (session.subscribeReceivers > 0 && hasAudioOnTrack)
    return this.publishConnected &&
      this.publishSenders > 0 &&
      subscribeReady &&
      (session.subscribeReceivers > 0 || hasAudioOnTrack)
  }

  removeByTargetOrUid(targetOrUid: string): number {
    const resolved = RtcPeerSessionPolicy.normalizeTargetNumber(targetOrUid)
    if (!resolved) {
      return 0
    }
    let removed = 0
    this.sessions.forEach((session: RtcPeerSession) => {
      if (this.matches(session, resolved)) {
        removed += this.removeSession(session) ? 1 : 0
      }
    })
    this.answeredAudioPeerKeys.delete(resolved)
    return removed
  }

  sessionCount(): number {
    return this.sessions.size
  }

  pendingIceCount(uid: string, target: string, rtcUid: string): number {
    const key = this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    const state = this.remoteStates.get(key)
    if (state) {
      return state.pendingIceCount
    }
    const session = this.sessions.get(key)
    return session ? session.pendingIceCount : 0
  }

  sessionKey(uid?: string, target?: string, rtcUid?: string, channelType?: string): string {
    return RtcPeerSessionPolicy.sessionKey(uid, target, rtcUid, channelType)
  }

  private createSubscribe(uid: string, target: string, rtcUid: string): RtcPeerSession {
    const key = this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    const session = new RtcPeerSession(key, uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE)
    const old = this.sessions.get(key)
    this.sessions.set(key, session)
    if (old && old !== session) {
      old.closed = true
    }
    this.removeDuplicateMappings(key, session)
    return session
  }

  private findSubscribe(uid: string, target: string, rtcUid: string): RtcPeerSession | undefined {
    const mapped = this.sessions.get(this.sessionKey(uid, target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE))
    if (mapped) {
      return mapped
    }
    const legacy = this.sessions.get(RtcPeerSessionPolicy.legacySessionKey(target, rtcUid, RTC_PEER_SESSION_CHANNEL_SUBSCRIBE))
    if (legacy && this.targetMatches(legacy, target)) {
      return legacy
    }
    const resolvedUid = RtcPeerSessionPolicy.trim(uid)
    if (resolvedUid) {
      let matched: RtcPeerSession | undefined = undefined
      this.sessions.forEach((candidate: RtcPeerSession) => {
        if (!matched &&
          candidate.channelType === RTC_PEER_SESSION_CHANNEL_SUBSCRIBE &&
          candidate.uid === resolvedUid &&
          this.targetMatches(candidate, target)) {
          matched = candidate
        }
      })
      return matched
    }
    return undefined
  }

  private findByTargetOrUid(targetOrUid: string): RtcPeerSession | undefined {
    const resolved = RtcPeerSessionPolicy.normalizeTargetNumber(targetOrUid)
    if (!resolved) {
      return undefined
    }
    let matched: RtcPeerSession | undefined = undefined
    this.sessions.forEach((session: RtcPeerSession) => {
      if (!matched && !session.closed && this.matches(session, resolved)) {
        matched = session
      }
    })
    return matched
  }

  private removeDuplicateMappings(keepKey: string, keepSession: RtcPeerSession): void {
    const removals: string[] = []
    this.sessions.forEach((candidate: RtcPeerSession, key: string) => {
      if (key === keepKey || !candidate) {
        return
      }
      const sameSession = candidate === keepSession
      const sameChannel = keepSession.channelType === candidate.channelType
      const sameUid = !!keepSession.uid && keepSession.uid === candidate.uid
      const sameTarget = !!keepSession.target && keepSession.target === candidate.target
      const duplicate = sameSession ||
        (sameChannel && sameUid && sameTarget) ||
        RtcPeerSessionPolicy.sameSessionScope(key, keepKey, keepSession.uid, keepSession.target, keepSession.channelType)
      if (duplicate && this.sessions.get(key) === candidate) {
        removals.push(key)
        if (candidate !== keepSession) {
          candidate.closed = true
        }
      }
    })
    removals.forEach((key: string) => {
      this.sessions.delete(key)
    })
  }

  private removeSession(session: RtcPeerSession): boolean {
    let removed = false
    const removals: string[] = []
    this.sessions.forEach((value: RtcPeerSession, key: string) => {
      if (value === session) {
        removals.push(key)
        removed = true
      }
    })
    removals.forEach((key: string) => {
      this.sessions.delete(key)
    })
    if (removed) {
      session.closed = true
      this.remoteStates.delete(session.key)
      this.answeredAudioPeerKeys.delete(session.target)
      this.answeredAudioPeerKeys.delete(session.uid)
    }
    return removed
  }

  private hasAnsweredAudio(targetOrUid: string, session: RtcPeerSession): boolean {
    let recorded = this.answeredAudioPeerKeys.get(targetOrUid)
    if (!recorded && targetOrUid === session.uid) {
      recorded = this.answeredAudioPeerKeys.get(session.target)
    }
    if (!recorded && targetOrUid === session.target) {
      recorded = this.answeredAudioPeerKeys.get(session.uid)
    }
    return !!recorded && RtcPeerSessionPolicy.answeredAudioMatchesPeer(recorded, session.key)
  }

  private matches(session: RtcPeerSession, targetOrUid: string): boolean {
    return targetOrUid === session.target || targetOrUid === session.uid
  }

  private targetMatches(session: RtcPeerSession, target: string): boolean {
    const resolved = RtcPeerSessionPolicy.normalizeTargetNumber(target)
    return !resolved || resolved === session.target
  }

  private rtcUidChanged(session: RtcPeerSession, rtcUid: string): boolean {
    const next = RtcPeerSessionPolicy.trim(rtcUid)
    return !!session.rtcUid && !!next && session.rtcUid !== next
  }

  private result(action: RtcPeerSessionAction, key: string, reason: string): RtcPeerSessionRouteResult {
    const result = new RtcPeerSessionRouteResult()
    result.action = action
    result.key = key
    result.reason = reason
    return result
  }
}
