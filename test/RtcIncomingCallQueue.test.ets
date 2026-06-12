import { describe, it, expect } from '@ohos/hypium'
import { RtcCallMode } from '../src/main/ets/model/RtcCallConfig'
import { RtcIncomingCallQueue } from '../src/main/ets/core/RtcIncomingCallQueue'

export default function rtcIncomingCallQueueTest() {
  describe('RtcIncomingCallQueue', () => {
    it('keeps multiple bedside incoming calls', 0, () => {
      const queue = new RtcIncomingCallQueue()

      queue.upsert({
        callId: 'bed-1',
        target: { number: '8001', displayName: '1床' },
        mode: RtcCallMode.AUDIO,
        receivedAt: 1
      })
      queue.upsert({
        callId: 'bed-2',
        target: { number: '8002', displayName: '2床' },
        mode: RtcCallMode.VIDEO,
        receivedAt: 2
      })

      const snapshot = queue.getSnapshot()
      expect(snapshot.pendingCount).assertEqual(2)
      expect(snapshot.calls.length).assertEqual(2)
      expect(snapshot.calls[0].callId).assertEqual('bed-1')
      expect(snapshot.calls[1].callId).assertEqual('bed-2')
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
      expect(snapshot.calls[0].phase).assertEqual('ended')
      expect(snapshot.calls[1].phase).assertEqual('incoming')
    })
  })
}
