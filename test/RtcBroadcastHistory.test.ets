import { describe, it, expect } from '@ohos/hypium'
import {
  isRtcBroadcastHistoryBusy,
  isRtcBroadcastHistoryOffline,
  isRtcBroadcastHistoryTimeout,
  parseRtcBroadcastHistory
} from '../src/main/ets/signaling/RtcBroadcastHistory'

export default function rtcBroadcastHistoryTest() {
  describe('RtcBroadcastHistory', () => {
    it('parses a status-bearing broadcast and detects timeout by flag', 0, () => {
      const history = parseRtcBroadcastHistory(
        '{"uid":"u1","from":"1001","to":"2002","status":"挂断","is_timeout":true}'
      )
      expect(history !== undefined).assertEqual(true)
      expect(history ? history.uid : '').assertEqual('u1')
      expect(isRtcBroadcastHistoryTimeout(history || {})).assertEqual(true)
    })

    it('detects timeout, busy and offline from Chinese status text', 0, () => {
      const timeout = parseRtcBroadcastHistory('{"status":"拨打回调超时挂断"}')
      const busy = parseRtcBroadcastHistory('{"status":"对方忙线中"}')
      const offline = parseRtcBroadcastHistory('{"status":"离线挂断"}')

      expect(isRtcBroadcastHistoryTimeout(timeout || {})).assertEqual(true)
      expect(isRtcBroadcastHistoryBusy(busy || {})).assertEqual(true)
      expect(isRtcBroadcastHistoryOffline(offline || {})).assertEqual(true)
      expect(isRtcBroadcastHistoryTimeout(offline || {})).assertEqual(false)
    })

    it('reads a history wrapped by the broadcast data field', 0, () => {
      const inner = '{"uid":"u9","status":"接听","is_auto_answer":true}'
      const history = parseRtcBroadcastHistory(JSON.stringify({ data: inner }))
      expect(history ? history.uid : '').assertEqual('u9')
      expect(history ? history.is_auto_answer : false).assertEqual(true)
    })

    it('ignores broadcasts without a status field', 0, () => {
      expect(parseRtcBroadcastHistory('call failed') === undefined).assertEqual(true)
      expect(parseRtcBroadcastHistory('{"type":"call_media_downgraded","uid":"u1"}') === undefined).assertEqual(true)
    })
  })
}
