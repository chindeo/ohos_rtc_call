import { describe, it, expect } from '@ohos/hypium'
import { normalizeTtsText } from '../src/main/ets/tts/RtcTtsText'

export default function rtcTtsTextTest() {
  describe('RtcTtsText', () => {
    it('reads a clock time as 点/分', 0, () => {
      expect(normalizeTtsText('10:36，请3床患者到护士站')).assertEqual('十点三十六分，请3床患者到护士站')
      expect(normalizeTtsText('08:05 复查')).assertEqual('八点零五分 复查')
      expect(normalizeTtsText('20:00')).assertEqual('二十点零零分')
    })

    it('reads long digit runs one digit at a time', 0, () => {
      expect(normalizeTtsText('住院号01177125')).assertEqual('住院号零一一七七一二五')
      expect(normalizeTtsText('电话0755-1234567')).assertEqual('电话零七五五-一二三四五六七')
    })

    it('keeps short numbers for the sherpa rules', 0, () => {
      expect(normalizeTtsText('21床正在呼叫')).assertEqual('21床正在呼叫')
      expect(normalizeTtsText('体温36.5度')).assertEqual('体温36.5度')
    })

    it('reads math symbols as chinese words', 0, () => {
      expect(normalizeTtsText('3+2=5，9-4=5，6×3=18，8÷2=4'))
        .assertEqual('3加2等于5，9减4等于5，6乘3等于18，8除2等于4')
      expect(normalizeTtsText('2−1')).assertEqual('2减1')
    })

    it('leaves an invalid clock alone', 0, () => {
      expect(normalizeTtsText('比例25:99')).assertEqual('比例25:99')
    })

    it('splits an upper-case run into letters with a pause on both sides', 0, () => {
      expect(normalizeTtsText('ABCDEFGHIJ')).assertEqual('A;B;C;D;E;F;G;H;I;J;')
      expect(normalizeTtsText('JHC主机呼叫21床')).assertEqual('J;H;C;主机呼叫21床')
    })

    it('keeps a normal english word as one word', 0, () => {
      expect(normalizeTtsText('PICC维护')).assertEqual('P;I;C;C;维护')
      expect(normalizeTtsText('Nurse station')).assertEqual('Nurse station')
    })

    it('cuts a long unpunctuated sentence at word anchors, at most twice', 0, () => {
      // 不切的长句在这个模型上是每次必错（现场耳朵也听到"患、三"没发音）
      expect(normalizeTtsText('二十三床患者张三呼叫护士站请尽快前往处理'))
        .assertEqual('二十三床患者张三,呼叫护士站,请尽快前往处理')
      // 短句不动
      expect(normalizeTtsText('21床正在呼叫')).assertEqual('21床正在呼叫')
      // 原文已经断过句就尊重原文
      expect(normalizeTtsText('二十三床患者张三，呼叫护士站，请尽快前往处理'))
        .assertEqual('二十三床患者张三，呼叫护士站，请尽快前往处理')
      // 没有锚点的长句不硬切（按字数硬切会把词切断、听写成"护士战/情紧快"）
      expect(normalizeTtsText('本楼层设备巡检已完成状态正常无需处理'))
        .assertEqual('本楼层设备巡检已完成状态正常无需处理')
      // 锚点离句首太近也不切，免得把"请按呼叫铃…"这类切碎
      expect(normalizeTtsText('请按呼叫铃护士站马上过来处理一下'))
        .assertEqual('请按呼叫铃护士站马上过来处理一下')
      // 两个锚点挨太近只切一刀
      expect(normalizeTtsText('二十八床患者请求呼叫护士站请尽快处理'))
        .assertEqual('二十八床患者请求,呼叫护士站请尽快处理')
      // 小数的点不算断句标点，带体温读数的长句照样要切
      expect(normalizeTtsText('二十三床患者张三体温36.5度呼叫护士站请尽快前往处理'))
        .assertEqual('二十三床患者张三体温36.5度,呼叫护士站,请尽快前往处理')
    })

    it('handles empty text', 0, () => {
      expect(normalizeTtsText('')).assertEqual('')
    })
  })
}
