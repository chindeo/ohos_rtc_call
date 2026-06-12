import { describe, it, expect } from '@ohos/hypium'
import {
  RtcPeerSessionAction,
  RtcPeerSessionRegistry
} from '../src/main/ets/core/RtcPeerSessionRegistry'

export default function rtcPeerSessionRegistryTest() {
  describe('RtcPeerSessionRegistry', () => {
    it('reuses repeated subscribe offer for one peer', 0, () => {
      const registry = new RtcPeerSessionRegistry()

      const first = registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      const second = registry.routeSubscribeOffer('uidA', '118787', 'rtcA')

      expect(first.action).assertEqual(RtcPeerSessionAction.CREATE)
      expect(second.action).assertEqual(RtcPeerSessionAction.REUSE)
      expect(second.key).assertEqual('uidA|118787|subscribe')
      expect(registry.sessionCount()).assertEqual(1)
    })

    it('recreates one peer when rtc uid changes', 0, () => {
      const registry = new RtcPeerSessionRegistry()

      registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      const changed = registry.routeSubscribeOffer('uidA', '118787', 'rtcB')

      expect(changed.action).assertEqual(RtcPeerSessionAction.RECREATE)
      expect(changed.reason).assertEqual('rtc_uid_changed')
      expect(registry.sessionCount()).assertEqual(1)
    })

    it('keeps different uid sessions isolated', 0, () => {
      const registry = new RtcPeerSessionRegistry()

      registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      registry.routeSubscribeOffer('uidB', '1039', 'rtcB')

      expect(registry.sessionCount()).assertEqual(2)
      expect(registry.routeSubscribeOffer('uidA', '118787', 'rtcA').action)
        .assertEqual(RtcPeerSessionAction.REUSE)
      expect(registry.sessionCount()).assertEqual(2)
    })

    it('keeps same uid but different targets isolated', 0, () => {
      const registry = new RtcPeerSessionRegistry()

      registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      registry.routeSubscribeOffer('uidA', '1039', 'rtcB')

      expect(registry.sessionCount()).assertEqual(2)
      expect(registry.sessionKey('uidA', '118787', 'rtcA', 'subscribe'))
        .assertEqual('uidA|118787|subscribe')
      expect(registry.sessionKey('uidA', '1039', 'rtcB', 'subscribe'))
        .assertEqual('uidA|1039|subscribe')
    })

    it('keeps legacy sessions isolated by target and rtc uid', 0, () => {
      const registry = new RtcPeerSessionRegistry()

      registry.routeSubscribeOffer('', '118787', 'rtcA')
      registry.routeSubscribeOffer('', '1039', 'rtcA')

      expect(registry.sessionCount()).assertEqual(2)
      expect(registry.sessionKey('', '118787', 'rtcA', 'subscribe'))
        .assertEqual('118787|rtcA|subscribe')
      expect(registry.sessionKey('', '1039', 'rtcA', 'subscribe'))
        .assertEqual('1039|rtcA|subscribe')
    })

    it('removes one target without touching the other session', 0, () => {
      const registry = new RtcPeerSessionRegistry()
      registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      registry.routeSubscribeOffer('uidB', '1039', 'rtcB')

      expect(registry.removeByTargetOrUid('uidA')).assertEqual(1)

      expect(registry.sessionCount()).assertEqual(1)
      expect(registry.routeSubscribeOffer('uidB', '1039', 'rtcB').action)
        .assertEqual(RtcPeerSessionAction.REUSE)
    })

    it('ignores late subscribe signals while closing', 0, () => {
      const registry = new RtcPeerSessionRegistry()

      expect(registry.routeSubscribeOffer('uidA', '118787', 'rtcA', true).action)
        .assertEqual(RtcPeerSessionAction.IGNORE_CLOSING)
      expect(registry.receiveSubscribeIce('uidA', '118787', 'rtcA', true).action)
        .assertEqual(RtcPeerSessionAction.IGNORE_CLOSING)
      expect(registry.sessionCount()).assertEqual(0)
    })

    it('caches subscribe ice before remote description with overflow guard', 0, () => {
      const registry = new RtcPeerSessionRegistry(2)

      expect(registry.receiveSubscribeIce('uidA', '118787', 'rtcA').action)
        .assertEqual(RtcPeerSessionAction.CACHE_ICE)
      expect(registry.receiveSubscribeIce('uidA', '118787', 'rtcA').action)
        .assertEqual(RtcPeerSessionAction.CACHE_ICE)
      expect(registry.receiveSubscribeIce('uidA', '118787', 'rtcA').action)
        .assertEqual(RtcPeerSessionAction.DROP_OVERFLOW)
      expect(registry.pendingIceCount('uidA', '118787', 'rtcA')).assertEqual(2)
    })

    it('accepts answer only for matching subscribe audio peer', 0, () => {
      const registry = new RtcPeerSessionRegistry()
      registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      registry.markPublishState(true, 1)
      registry.markSubscribeState('uidA', '118787', 'rtcA', false, 1)
      registry.markAnsweredAudio('118787', 'uidA|118787|subscribe')

      expect(registry.isAnswered('118787')).assertEqual(true)
      expect(registry.isAnswered('uidA')).assertEqual(true)
    })

    it('rejects answer audio from another peer', 0, () => {
      const registry = new RtcPeerSessionRegistry()
      registry.routeSubscribeOffer('uidA', '118787', 'rtcA')
      registry.markPublishState(true, 1)
      registry.markSubscribeState('uidA', '118787', 'rtcA', false, 1)
      registry.markAnsweredAudio('118787', 'uidA|1039|subscribe')

      expect(registry.isAnswered('118787')).assertEqual(false)
    })
  })
}
