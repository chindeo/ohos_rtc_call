// 本地纯逻辑自检，不进 Hypium 流程。用法（在仓库根目录）：
//   cp src/main/ets/tts/RtcTtsText.ets tools/_check_tts_text.ts
//   ELECTRON_RUN_AS_NODE=1 <node> --experimental-transform-types tools/check-tts-text.ts
//   rm tools/_check_tts_text.ts
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { normalizeTtsText } from './_check_tts_text.ts'

const cases: string[][] = [
  ['10:36，请3床患者到护士站', '十点三十六分，请3床患者到护士站'],
  ['08:05 复查', '八点零五分 复查'],
  ['20:00', '二十点零零分'],
  ['住院号01177125', '住院号零一一七七一二五'],
  ['电话0755-1234567', '电话零七五五-一二三四五六七'],
  ['21床正在呼叫', '21床正在呼叫'],
  ['体温36.5度', '体温36.5度'],
  ['比例25:99', '比例25:99'],
  ['', '']
]

describe('normalizeTtsText', () => {
  for (const item of cases) {
    it(item[0], () => {
      assert.equal(normalizeTtsText(item[0]), item[1])
    })
  }
})
