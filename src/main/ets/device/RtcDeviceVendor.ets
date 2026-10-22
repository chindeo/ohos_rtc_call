import { deviceInfo } from '@kit.BasicServicesKit'

export enum RtcDeviceVendor {
  DNAKE = 'dnake',
  SHIMETA = 'shimeta',
  AURINE = 'aurine',
  JHC = 'jhc',
  UNKNOWN = 'unknown'
}

export const RTC_DEVICE_VENDOR_KEY = 'rtcDeviceVendor'
export const RTC_DEVICE_VENDOR_LABEL_KEY = 'rtcDeviceVendorLabel'
export const RTC_DEVICE_VENDOR_INFO_KEY = 'rtcDeviceVendorInfo'

AppStorage.setOrCreate<string>(RTC_DEVICE_VENDOR_KEY, RtcDeviceVendor.UNKNOWN)
AppStorage.setOrCreate<string>(RTC_DEVICE_VENDOR_LABEL_KEY, '未知厂家')
AppStorage.setOrCreate<string>(RTC_DEVICE_VENDOR_INFO_KEY, '')

function toLowerText(value: string | undefined): string {
  return (value || '').toLowerCase()
}

function includesAny(source: string, keywords: string[]): boolean {
  for (let i = 0; i < keywords.length; i += 1) {
    if (source.includes(keywords[i])) {
      return true
    }
  }
  return false
}

function collectDeviceInfo(): string {
  return [
    deviceInfo.manufacture,
    deviceInfo.productModel,
    deviceInfo.hardwareModel,
    deviceInfo.osFullName,
    deviceInfo.displayVersion,
    deviceInfo.sdkApiVersion !== undefined ? '' + deviceInfo.sdkApiVersion : ''
  ].map((item: string | undefined) => item || '').join(' ')
}

function getVendorLabel(vendor: RtcDeviceVendor): string {
  if (vendor === RtcDeviceVendor.DNAKE) {
    return '狄耐克'
  }
  if (vendor === RtcDeviceVendor.SHIMETA) {
    return '视美泰'
  }
  if (vendor === RtcDeviceVendor.AURINE) {
    return 'Aurine'
  }
  if (vendor === RtcDeviceVendor.JHC) {
    return '金海创'
  }
  return '未知厂家'
}

export class RtcDeviceVendorResolver {
  static getDeviceInfoText(): string {
    return collectDeviceInfo()
  }

  static detect(): RtcDeviceVendor {
    const info = toLowerText(collectDeviceInfo())
    if (includesAny(info, ['shimeta', 'shi meta', 'showmetech', 'show meta', '视美泰'])) {
      return RtcDeviceVendor.SHIMETA
    }
    if (includesAny(info, ['aurine', '奥瑞那', 'mhmh0216', 'medical'])) {
      return RtcDeviceVendor.AURINE
    }
    if (includesAny(info, ['jhc', 'jinhai', 'jin hai', '金海创'])) {
      return RtcDeviceVendor.JHC
    }
    if (Number(deviceInfo.sdkApiVersion || 0) >= 23 && includesAny(info, ['openharmony 6'])) {
      return RtcDeviceVendor.JHC
    }
    if (includesAny(info, ['dnake', '狄耐克'])) {
      return RtcDeviceVendor.DNAKE
    }
    return RtcDeviceVendor.UNKNOWN
  }

  static persist(vendor: RtcDeviceVendor = RtcDeviceVendorResolver.detect()): RtcDeviceVendor {
    AppStorage.setOrCreate<string>(RTC_DEVICE_VENDOR_KEY, vendor)
    AppStorage.setOrCreate<string>(RTC_DEVICE_VENDOR_LABEL_KEY, getVendorLabel(vendor))
    AppStorage.setOrCreate<string>(RTC_DEVICE_VENDOR_INFO_KEY, collectDeviceInfo())
    return vendor
  }

  static getStoredVendor(): RtcDeviceVendor {
    const vendor = AppStorage.get<string>(RTC_DEVICE_VENDOR_KEY) || RtcDeviceVendor.UNKNOWN
    if (vendor === RtcDeviceVendor.DNAKE || vendor === RtcDeviceVendor.SHIMETA ||
      vendor === RtcDeviceVendor.AURINE || vendor === RtcDeviceVendor.JHC) {
      return vendor as RtcDeviceVendor
    }
    return RtcDeviceVendor.UNKNOWN
  }

  static isShimeta(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.SHIMETA
  }

  // JHC Cdo-I101 (api23 bedside) delivers capture content at ~45000 labeled-48k samples/s, so
  // AEC3's reference and its own echo slide apart. Two independent calibrations of the zero-drift
  // value agree: a known click train played from the call gateway drifts +1.96%/s at 1089, giving
  // 1089/1.0196 ~= 1068; and AEC3's own render/capture call-counter gap drifts -5.6 blocks/s at
  // 1089 but +4.4 blocks/s at 1045, interpolating to ~1064. 0 = leave native alone.
  static captureResamplePermille(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): number {
    return vendor === RtcDeviceVendor.JHC ? 1068 : 0
  }

  // Asserts the whole speaker->microphone loopback delay to the echo canceller instead of letting
  // native sum its own two measurements. With useExternalDelayEstimator off this only seeds the
  // alignment at reset; native can only see the 158~186 ms the platform reports, while the click
  // train measured 216 ms. 0 would mean "use the measured sum".
  static aecStreamDelayMs(): number {
    return 216
  }

  static isDnake(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.DNAKE
  }

  static isAurine(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.AURINE
  }

  static isJhc(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.JHC
  }

  static shouldUseDnakeSdk(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.DNAKE
  }

  static supportsDnakeSip(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.DNAKE
  }

  static isDnakeSdkAvailable(): boolean {
    return RtcDeviceVendorResolver.shouldUseDnakeSdk()
  }
}
