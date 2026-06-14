import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcCallLifecycleStore } from '../src/main/ets/core/RtcCallLifecycleStore'

export default function rtcCallLifecycleStoreTest() {
  describe('RtcCallLifecycleStore', () => {
    it('merges the same uid and keeps answered phase', 0, () => {
      const store = new RtcCallLifecycleStore()

      store.upsertCall({
        uid: 'uid-1',
        number: 'bed-1',
        name: 'Bed 1',
        direction: 'incoming',
        phase: 'incoming',
        mode: RtcCallMode.AUDIO
      })
      store.markPhase('uid-1', 'answered', false)
      store.upsertCall({
        uid: 'uid-1',
        number: 'bed-1',
        name: 'Bed 1 New',
        direction: 'incoming',
        phase: 'incoming'
      })

      const session = store.get('uid-1')
      expect(store.listCalls().length).assertEqual(1)
      expect(session?.phase).assertEqual('answered')
      expect(session?.name).assertEqual('Bed 1 New')
    })

    it('isolates same number with different uid', 0, () => {
      const store = new RtcCallLifecycleStore()

      store.upsertCall({ uid: 'uid-a', number: 'bed-1', direction: 'incoming' })
      store.upsertCall({ uid: 'uid-b', number: 'bed-1', direction: 'incoming' })

      const resolved = store.resolveUidOrUniqueNumber('', 'bed-1', 'hangup', true)
      expect(store.listCalls().length).assertEqual(2)
      expect(resolved.handled).assertEqual(false)
      expect(resolved.reason).assertEqual('ambiguous number')
    })

    it('tracks peer by uid channel and rtc uid', 0, () => {
      const store = new RtcCallLifecycleStore()

      store.upsertCall({ uid: 'uid-a', number: 'bed-1', direction: 'incoming' })
      const publish = store.upsertPeer('uid-a', 'rtc-pub', 'publish', 'host', 'bed-1')
      const subscribe = store.upsertPeer('uid-a', 'rtc-sub', 'subscribe', 'bed-1', 'host')

      expect(publish?.key).assertEqual('uid-a:publish:rtc-pub')
      expect(subscribe?.key).assertEqual('uid-a:subscribe:rtc-sub')
      expect(store.listPeers().length).assertEqual(2)
    })

    it('removes target uid only and keeps remaining call selected', 0, () => {
      const store = new RtcCallLifecycleStore()

      store.upsertCall({ uid: 'bed-1-uid', number: 'bed-1', direction: 'outgoing' })
      store.upsertCall({ uid: 'bed-2-uid', number: 'bed-2', direction: 'incoming' })
      store.upsertPeer('bed-1-uid', 'rtc-1', 'subscribe', 'bed-1', 'host')
      store.upsertPeer('bed-2-uid', 'rtc-2', 'subscribe', 'bed-2', 'host')

      store.remove('bed-1-uid')
      const snapshot = store.snapshot()

      expect(snapshot.calls.length).assertEqual(1)
      expect(snapshot.calls[0].uid).assertEqual('bed-2-uid')
      expect(snapshot.selectedUid).assertEqual('bed-2-uid')
      expect(snapshot.peers.length).assertEqual(1)
      expect(snapshot.peers[0].uid).assertEqual('bed-2-uid')
    })
  })
}
