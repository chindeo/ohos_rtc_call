import { Loggable, NativeLogging } from 'libohos_webrtc.so'

export enum LoggingSeverity { VERBOSE, INFO, WARNING, ERROR, NONE }

export class Logging {
  private static loggingEnabled: boolean = false
  private static loggable: Loggable | null
  private static loggableSeverity: LoggingSeverity = LoggingSeverity.ERROR

  static injectLoggable(injectedLoggable: Loggable, severity: LoggingSeverity): void {
    if (injectedLoggable != null) {
      Logging.loggable = injectedLoggable
      Logging.loggableSeverity = severity
      NativeLogging.injectLoggable(injectedLoggable, severity)
    }
  }

  static deleteInjectedLoggable(): void {
    Logging.loggable = null
    NativeLogging.deleteLoggable()
  }

  static enableLogThreads(): void {
    NativeLogging.enableLogThreads()
  }

  static enableLogTimeStamps(): void {
    NativeLogging.enableLogTimeStamps()
  }

  static enableLogToDebugOutput(severity: LoggingSeverity): void {
    if (Logging.loggable != null) {
      throw new Error('Logging to native debug output not supported while Loggable is injected.')
    }
    NativeLogging.enableLogToDebugOutput(severity)
    Logging.loggingEnabled = true
  }

  static log(severity: LoggingSeverity, tag: string, message: string): void {
    if (Logging.loggable) {
      if (severity < Logging.loggableSeverity) {
        return
      }
      Logging.loggable.logMessage(message, severity, tag)
      return
    }
    if (Logging.loggingEnabled) {
      NativeLogging.log(message, severity, tag)
      return
    }
    switch (severity) {
      case LoggingSeverity.ERROR:
        console.error(tag, message)
        break
      case LoggingSeverity.WARNING:
        console.warn(tag, message)
        break
      case LoggingSeverity.INFO:
        console.info(tag, message)
        break
      default:
        console.debug(tag, message)
        break
    }
  }

  static d(tag: string, message: string): void {
    Logging.log(LoggingSeverity.INFO, tag, message)
  }

  static e(tag: string, message: string, error?: Error): void {
    Logging.log(LoggingSeverity.ERROR, tag, message)
    if (error !== undefined) {
      Logging.log(LoggingSeverity.ERROR, tag, error.message)
    }
  }

  static w(tag: string, message: string, error?: Error): void {
    Logging.log(LoggingSeverity.WARNING, tag, message)
    if (error !== undefined) {
      Logging.log(LoggingSeverity.WARNING, tag, error.message)
    }
  }

  static v(tag: string, message: string): void {
    Logging.log(LoggingSeverity.VERBOSE, tag, message)
  }
}
