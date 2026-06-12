import { describe, it, expect } from '@ohos/hypium'
import { RtcCallSessionStore } from '../src/main/ets/core/RtcCallSessionStore'

export default function rtcCallSessionStoreTest() {
  describe('RtcCallSessionStore', () => {
    it('keeps different uid sessions for the same peer isolated', 0, () => {
      const store = new RtcCallSessionStore()

      store.upsert({ uid: 'uid-a', peerNumber: '1039', displayName: '1床', status: '拨打' })
      store.upsert({ uid: 'uid-b', peerNumber: '1039', displayName: '1床', status: '拨打' })

      expect(store.findByUid('uid-a')?.peerNumber).assertEqual('1039')
      expect(store.findByUid('uid-b')?.peerNumber).assertEqual('1039')
      expect(store.uidForPeer('1039')).assertEqual('uid-b')
      expect(store.snapshot().size).assertEqual(2)
    })

    it('removes one uid without clearing other sessions on the same peer', 0, () => {
      const store = new RtcCallSessionStore()

      store.upsert({ uid: 'uid-a', peerNumber: '1039', status: '拨打' })
      store.upsert({ uid: 'uid-b', peerNumber: '1039', status: '拨打' })
      store.removeUid('uid-a')

      expect(store.findByUid('uid-a') === undefined).assertEqual(true)
      expect(store.findByUid('uid-b')?.peerNumber).assertEqual('1039')
      expect(store.uidForPeer('1039')).assertEqual('uid-b')
    })

    it('marks hold state without changing session identity', 0, () => {
      const store = new RtcCallSessionStore()

      store.upsert({ uid: 'uid-a', peerNumber: '1039', status: '接听', isHold: false })
      store.markHold('uid-a', true)
      store.upsert({ uid: 'uid-a', peerNumber: '1039', displayName: '1床' })

      expect(store.findByUid('uid-a')?.isHold).assertEqual(true)
      expect(store.findByUid('uid-a')?.status).assertEqual('接听')
    })

    it('resolves peer from from/to fields with self number', 0, () => {
      expect(RtcCallSessionStore.resolvePeer('1001', '1039', '1001')).assertEqual('1039')
      expect(RtcCallSessionStore.resolvePeer('1039', '1001', '1001')).assertEqual('1039')
    })
  })
}
