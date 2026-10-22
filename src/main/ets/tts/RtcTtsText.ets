const DIGITS = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九']

function cardinalUnder100(value: number): string {
  if (value < 10) {
    return DIGITS[value]
  }
  const tens = Math.floor(value / 10)
  const ones = value % 10
  const head = tens === 1 ? '十' : `${DIGITS[tens]}十`
  return ones === 0 ? head : `${head}${DIGITS[ones]}`
}

function readClock(hourText: string, minuteText: string): string {
  const hour = Number.parseInt(hourText, 10)
  const minute = Number.parseInt(minuteText, 10)
  if (Number.isNaN(hour) || hour > 23 || Number.isNaN(minute) || minute > 59) {
    return `${hourText}:${minuteText}`
  }
  // "10:05" 要念"十点零五分"，分钟十位是 0 时补一个零。
  const minuteRead = minuteText.length === 2 && minuteText.charAt(0) === '0'
    ? `零${DIGITS[minute]}`
    : cardinalUnder100(minute)
  return `${cardinalUnder100(hour)}点${minuteRead}分`
}

function readDigitByDigit(digits: string): string {
  let out = ''
  for (let i = 0; i < digits.length; i++) {
    out += DIGITS[Number.parseInt(digits.charAt(i), 10)]
  }
  return out
}

/**
 * espeak-ng 会把连续大写字母当成一个英文单词去拼读（"JHC" 念成生造词），
 * 拆成单字母它才念字母名。播报里的字母串基本都是缩略语（JHC/ICU/PICC），
 * 所以只处理全大写串；含小写的正常英文单词保持整词读法。
 * 分隔必须用标点、不能用空格：光用空格十个字母会连着念成一串，真机上听不出边界。
 * 串尾那个标点也不能少：`I, C, U三床…` 会把字母和汉字连读出多余鼻音（回读成 `i c u n`）。
 * 标点选分号：2026-10-22 PC 各 8 次回读 + 现场耳朵共同判定。
 * `I、C、U、三床请到护士站` 3585ms 且八次跑出七种结果，`I;C;U;…` 只要 2481ms、八次回读完全一致；
 * JHC 省 1.26 秒、PICC 省 1.35 秒。逗号/顿号/句号/问号/叹号都在 3.3~3.6 秒这一档，压不下来。
 * 注意这只适用于字母：**中文长句要用逗号**，同一位置换成分号会把稳定性打掉
 * （长句分号 8 次跑出 5 种结果，现场听到"前往处理"的往偶发漏读），两处的符号不能统一。
 */
export function spellUpperRuns(text: string): string {
  return text.replace(/[A-Z]{2,}/g, (run: string): string => `${run.split('').join(';')};`)
}

/**
 * sherpa 的中文前端没有算符的音，"3+2=5" 里那几个符号会被整段丢掉，念出来只剩数字。
 * 算符在播报里本来就有固定汉字读法，所以在文本层换成汉字，数字继续交给 rule-fst 去规整。
 * ASCII 减号只在两侧都是数字时才换，免得把日期、编号里的连字符念成"减"。
 */
function readMathSymbols(text: string): string {
  return text
    .replace(/(\d)\s*[-−－]\s*(?=\d)/g, '$1减')
    .split('×').join('乘')
    .split('÷').join('除')
    .split('=').join('等于')
    .split('＋').join('加')
    .split('+').join('加')
}

/**
 * 长句切分。24 字无标点的呼叫话术在这个模型上是"每次必错"（回读 12/12，错在床号之后的
 * 者/患/张；真机上现场耳朵也是"患、三没发音"），在词与词之间补两个逗号就降到 2/12。
 * 两条边界是实测划出来的：
 * - **不能按字数硬切**。每 4 字一刀把"护士站/请"切成破词后，模型会把字序读乱
 *   （回读成"护士战""情紧快"），比丢字更难接受，而且多花 2 秒。
 * - **刀数要少**。切三刀 5.39 秒、切七刀 6.63 秒，现场判"停顿太久、不通顺"；
 *   只切两刀 5.03 秒，效果一样。
 * 所以只在动词锚点前插逗号，最多两刀，短句和已带标点的原文一律不动。
 * 用半角逗号：它在模型音素表里（tokens.txt 中 `,` = 4），`、` 不在表里（虽然也当停顿用，
 * 但链路没查明，升级前端时属于没人保证还能用那一类）。
 */
const LONG_SENTENCE_MIN_CHARS = 14
const LONG_SENTENCE_ANCHORS: string[] = ['呼叫', '请']
// 锚点前至少留这么多字，免得把"21床呼叫护士站"这类短句也切碎。
const LONG_SENTENCE_MIN_HEAD = 6
// 两个切点之间至少隔这么多字，避免出现"请,快"这种切在两字内的破句。
const LONG_SENTENCE_MIN_SPAN = 4
const LONG_SENTENCE_MAX_CUTS = 2
// 小数的点不算断句标点，否则"体温36.5度…呼叫…"这种句子永远进不了切分。
const CLAUSE_PUNCTUATION = /[、，；：！？,;:?]/

export function splitLongSentence(text: string): string {
  if (!text || text.length < LONG_SENTENCE_MIN_CHARS || CLAUSE_PUNCTUATION.test(text)) {
    return text
  }
  let out = text
  let cuts = 0
  let lastCut = -1
  for (let i = 0; i < LONG_SENTENCE_ANCHORS.length && cuts < LONG_SENTENCE_MAX_CUTS; i++) {
    const at = out.indexOf(LONG_SENTENCE_ANCHORS[i], LONG_SENTENCE_MIN_HEAD)
    if (at <= 0 || (lastCut >= 0 && at - lastCut < LONG_SENTENCE_MIN_SPAN)) {
      continue
    }
    out = `${out.slice(0, at)},${out.slice(at)}`
    lastCut = at
    cuts++
  }
  return out
}

/**
 * sherpa 的 number.fst 排在最前，会把所有数字串按基数读掉，date/phone 两条规则实际轮不到。
 * 所以时刻和编号这类必须逐位念的，在喂给引擎前先转成汉字；床号、体温这种短数字留给 fst。
 */
export function normalizeTtsText(text: string): string {
  if (!text) {
    return text
  }
  const withClock = text.replace(/(\d{1,2}):(\d{2})/g, (_m: string, h: string, m: string): string => readClock(h, m))
  // 算符放在数字规则之后：号码里的连字符要先被逐位读法吃成汉字，
  // 才不会被当成减号（"0755-1234567" 念成"零七五五减一二三四五六七"是错的）。
  // 长句切分放最后一步，作用在最终喂引擎的文本上；字母串自带顿号后就不再多切（含字母的长句没测过）。
  return splitLongSentence(readMathSymbols(spellUpperRuns(withClock.replace(/\d{4,}/g, (digits: string): string => readDigitByDigit(digits)))))
}
