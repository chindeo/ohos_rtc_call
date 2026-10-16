const CN_DIGITS = '零一二三四五六七八九'

function isDigitChar(ch: string): boolean {
  return ch >= '0' && ch <= '9'
}

function digitByDigit(run: string): string {
  let out = ''
  for (let i = 0; i < run.length; i++) {
    out += CN_DIGITS.charAt(run.charCodeAt(i) - 48)
  }
  return out
}

// 只处理 1..999：床号、呼叫次数、音量百分比这类短数字都落在这里。
// explicitTen=false 时 10 读"十"、110 读"一百一十"，跟口语一致。
function cardinalText(run: string, explicitTen: boolean = false): string {
  const n = Number(run)
  if (!isFinite(n) || n < 0 || n > 999) {
    return digitByDigit(run)
  }
  if (n < 10) {
    return CN_DIGITS.charAt(n)
  }
  if (n < 100) {
    const tens = Math.floor(n / 10)
    const ones = n % 10
    const head = tens === 1 && !explicitTen ? '' : CN_DIGITS.charAt(tens)
    return `${head}十${ones === 0 ? '' : CN_DIGITS.charAt(ones)}`
  }
  const hundreds = Math.floor(n / 100)
  const rest = n % 100
  if (rest === 0) {
    return `${CN_DIGITS.charAt(hundreds)}百`
  }
  // 105 → 一百零五；110 → 一百一十。
  return `${CN_DIGITS.charAt(hundreds)}百${rest < 10 ? `零${CN_DIGITS.charAt(rest)}` : cardinalText(`${rest}`, true)}`
}

function numberText(run: string): string {
  // 4 位以上按位读：年份、科室号、住院号都不该读成"一千零二十四"。
  if (run.length >= 4) {
    return digitByDigit(run)
  }
  // 前导 0 是编号特征（0117），按位读。
  if (run.length > 1 && run.charAt(0) === '0') {
    return digitByDigit(run)
  }
  return cardinalText(run)
}

function clockPart(run: string): string {
  const n = Number(run)
  if (n < 10) {
    return `零${CN_DIGITS.charAt(n)}`
  }
  return cardinalText(run)
}

interface RunScan {
  run: string
  end: number
}

function scanDigits(chars: string[], from: number): RunScan {
  let run = ''
  let i = from
  while (i < chars.length && isDigitChar(chars[i])) {
    run += chars[i]
    i++
  }
  return { run: run, end: i }
}

interface ClockScan {
  text: string
  end: number
}

// 10:36 → 十点三十六分；08:05 → 八点零五分；10:36:20 → 十点三十六分二十秒。
function tryClock(chars: string[], hourRun: string, colonIndex: number): ClockScan {
  const miss: ClockScan = { text: '', end: colonIndex }
  const minute = scanDigits(chars, colonIndex + 1)
  if (minute.run.length !== 2) {
    return miss
  }
  const hour = Number(hourRun)
  const minuteValue = Number(minute.run)
  if (!isFinite(hour) || !isFinite(minuteValue) || hourRun.length > 2 || hour >= 24 || minuteValue >= 60) {
    return miss
  }
  let end = minute.end
  let second = scanDigits(chars, end + 1)
  const hasSeconds = end < chars.length && chars[end] === ':' && second.run.length === 2 && Number(second.run) < 60
  if (hasSeconds) {
    end = second.end
  }
  const hourText = cardinalText(hourRun)
  const minuteText = minuteValue === 0 ? (hasSeconds ? '零分' : '整') : `${clockPart(minute.run)}分`
  const secondText = hasSeconds ? (Number(second.run) === 0 ? '零秒' : `${clockPart(second.run)}秒`) : ''
  return { text: `${hourText}点${minuteText}${secondText}`, end: end }
}

/**
 * 播报前把阿拉伯数字和时间转成汉字读法。
 * 我们的软浮点 sherpa 构建带 rule-fsts 会直接崩（RC=255），而 matcha 的中文词典只认拼音，
 * 数字进词典查不到就被丢掉，现象是"句子里的数字不响"。所以规整必须在端上做。
 */
export function normalizeTtsText(text: string): string {
  if (!text) {
    return ''
  }
  const chars = text.split('')
  let out = ''
  let i = 0
  while (i < chars.length) {
    if (!isDigitChar(chars[i])) {
      out += chars[i]
      i++
      continue
    }
    const integer = scanDigits(chars, i)
    const clock = tryClock(chars, integer.run, integer.end)
    if (clock.text) {
      out += clock.text
      i = clock.end
      continue
    }
    if (chars[integer.end] === '.') {
      const fraction = scanDigits(chars, integer.end + 1)
      if (fraction.run.length > 0) {
        out += `${numberText(integer.run)}点${digitByDigit(fraction.run)}`
        i = fraction.end
        continue
      }
    }
    out += numberText(integer.run)
    i = integer.end
    // 不是合法时刻的 "25:36" 之类，冒号留着也念不出（词典会吞），显式丢掉让文本可读。
    if (chars[i] === ':' && i + 1 < chars.length && isDigitChar(chars[i + 1])) {
      i++
    }
    continue
  }
  return out
}
