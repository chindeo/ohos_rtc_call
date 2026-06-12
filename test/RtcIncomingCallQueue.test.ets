import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcIncomingCallQueue } from '../src/main/ets/core/RtcIncomingCallQueue'

export default function rtcIncomingCallQueueTest() {
  describe('RtcIncomingCallQueue', () => {
    it('keeps multiple bedside incoming calls', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({
        callId: 'bed-1',
        uid: 'uid-1',
        target: { number: '8001', displayName: '1床' },
        mode: RtcCallMode.AUDIO,
        receivedAt: 1
      })
      queue.upsert({
        callId: 'bed-2',
        uid: 'uid-2',
        target: { number: '8002', displayName: '2床' },
        mode: RtcCallMode.VIDEO,
        receivedAt: 2
      })

      const snapshot = queue.getSnapshot()
      expect(snapshot.pendingCount).assertEqual(2)
      expect(snapshot.calls.length).assertEqual(2)
      expect(snapshot.calls.some(item => item.callId === 'bed-1')).assertTrue()
      expect(snapshot.calls.some(item => item.callId === 'bed-2')).assertTrue()
    })

    it('sorts by care weight and time', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ uid: 'normal', target: { number: '8001' }, sortWeight: 9, receivedAt: 10 })
      queue.upsert({ uid: 'special', target: { number: '8002' }, sortWeight: 1, receivedAt: 1 })

      expect(queue.getSnapshot().calls[0].uid).assertEqual('special')
    })

    it('deduplicates the same call id and preserves other calls', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ callId: 'bed-1', target: { number: '8001' }, receivedAt: 1 })
      queue.upsert({ callId: 'bed-2', target: { number: '8002' }, receivedAt: 2 })
      queue.upsert({ callId: 'bed-1', target: { number: '8001', displayName: '1床更新' }, receivedAt: 3 })

      const snapshot = queue.getSnapshot()
      expect(snapshot.pendingCount).assertEqual(2)
      expect(snapshot.calls.length).assertEqual(2)
      expect(snapshot.calls[0].target.displayName).assertEqual('1床更新')
    })

    it('marks accepted and ended call without clearing pending calls', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ callId: 'bed-1', target: { number: '8001' }, receivedAt: 1 })
      queue.upsert({ callId: 'bed-2', target: { number: '8002' }, receivedAt: 2 })
      queue.accept('bed-1')
      queue.end('bed-1', 'hangup')

      const snapshot = queue.getSnapshot()
      expect(snapshot.pendingCount).assertEqual(1)
      expect(snapshot.calls.length).assertEqual(2)
      expect(snapshot.calls.find(item => item.callId === 'bed-1')?.phase).assertEqual('ended')
      expect(snapshot.calls.find(item => item.callId === 'bed-2')?.phase).assertEqual('incoming')
    })

    it('does not reset an accepted call to incoming on repeated upsert', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ callId: 'bed-1', uid: 'uid-1', target: { number: '8001' }, receivedAt: 1 })
      queue.accept('uid-1')
      queue.upsert({ callId: 'bed-1', uid: 'uid-1', target: { number: '8001', displayName: '1床更新' }, receivedAt: 2 })

      const item = queue.getSnapshot().calls.find(record => record.uid === 'uid-1')
      expect(item?.phase).assertEqual('accepted')
      expect(item?.target.displayName).assertEqual('1床更新')
    })

    it('selects a call without accepting it', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ callId: 'bed-1', uid: 'uid-1', target: { number: '8001' }, receivedAt: 1 })
      queue.upsert({ callId: 'bed-2', uid: 'uid-2', target: { number: '8002' }, receivedAt: 2 })
      queue.select('uid-2')

      const snapshot = queue.getSnapshot()
      expect(snapshot.selectedCallId).assertEqual('bed-2')
      expect(snapshot.activeCallId).assertEqual('')
      expect(snapshot.calls.find(item => item.callId === 'bed-2')?.phase).assertEqual('incoming')
      expect(snapshot.pendingCount).assertEqual(2)
    })

    it('marks hold state without changing pending calls', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ callId: 'bed-1', uid: 'uid-1', target: { number: '8001' }, receivedAt: 1 })
      queue.upsert({ callId: 'bed-2', uid: 'uid-2', target: { number: '8002' }, receivedAt: 2 })
      queue.accept('uid-1')
      queue.markHold('uid-1', true)

      const snapshot = queue.getSnapshot()
      expect(snapshot.calls.find(item => item.callId === 'bed-1')?.isHold).assertEqual(true)
      expect(snapshot.calls.find(item => item.callId === 'bed-1')?.phase).assertEqual('accepted')
      expect(snapshot.calls.find(item => item.callId === 'bed-2')?.phase).assertEqual('incoming')
    })

    it('removes by uid without touching other calls from the same peer', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ uid: 'uid-a', target: { number: '8001' }, receivedAt: 1 })
      queue.upsert({ uid: 'uid-b', target: { number: '8001' }, receivedAt: 2 })
      queue.remove('uid-a')

      expect(queue.getSnapshot().calls.length).assertEqual(1)
      expect(queue.getSnapshot().calls[0].uid).assertEqual('uid-b')
    })

    it('does not resolve a peer-number operation when multiple sessions share that peer', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({ uid: 'uid-a', target: { number: '8001' }, receivedAt: 1 })
      queue.upsert({ uid: 'uid-b', target: { number: '8001' }, receivedAt: 2 })

      expect(queue.accept('8001') === undefined).assertEqual(true)
      expect(queue.getSnapshot().pendingCount).assertEqual(2)
    })
  })
}
