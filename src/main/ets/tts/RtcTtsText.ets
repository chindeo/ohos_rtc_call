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
 * sherpa 的 number.fst 排在最前，会把所有数字串按基数读掉，date/phone 两条规则实际轮不到。
 * 所以时刻和编号这类必须逐位念的，在喂给引擎前先转成汉字；床号、体温这种短数字留给 fst。
 */
export function normalizeTtsText(text: string): string {
  if (!text) {
    return text
  }
  const withClock = text.replace(/(\d{1,2}):(\d{2})/g, (_m: string, h: string, m: string): string => readClock(h, m))
  return withClock.replace(/\d{4,}/g, (digits: string): string => readDigitByDigit(digits))
}
