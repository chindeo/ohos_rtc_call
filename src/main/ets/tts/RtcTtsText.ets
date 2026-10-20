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
 * 用逗号而不是空格分隔：espeak 会把逗号编成韵律停顿，光用空格十个字母会连着念成一串，
 * 真机上听不出边界。
 */
export function spellUpperRuns(text: string): string {
  return text.replace(/[A-Z]{2,}/g, (run: string): string => run.split('').join(', '))
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
  return readMathSymbols(spellUpperRuns(withClock.replace(/\d{4,}/g, (digits: string): string => readDigitByDigit(digits))))
}
