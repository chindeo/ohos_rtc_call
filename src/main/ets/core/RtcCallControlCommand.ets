export const RTC_CALL_CONTROL_SOURCE_HANDSET = 'handset'
export const RTC_CALL_CONTROL_SOURCE_SCREEN = 'screen'

export class RtcCallControlCommand {
  action: string = ''
  timestamp: number = 0
  sequence: number = 0
  source: string = ''
}

export class RtcCallControlCommandCodec {
  static build(action: string, sequence: number, source: string = '', timestamp: number = Date.now()): string {
    return `${action}:${timestamp}:${sequence}:${source}`
  }

  static parse(value: string): RtcCallControlCommand {
    const parts = (value || '').split(':')
    const command = new RtcCallControlCommand()
    command.action = parts[0] || ''
    command.timestamp = Number(parts[1] || 0)
    command.sequence = Number(parts[2] || 0)
    command.source = parts[3] || ''
    return command
  }
}
