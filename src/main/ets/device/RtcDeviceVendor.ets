import { deviceInfo } from '@kit.BasicServicesKit'

export enum RtcDeviceVendor {
  DNAKE = 'dnake',
  SHIMETA = 'shimeta',
  AURINE = 'aurine',
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
    deviceInfo.displayVersion
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
    if (vendor === RtcDeviceVendor.DNAKE || vendor === RtcDeviceVendor.SHIMETA || vendor === RtcDeviceVendor.AURINE) {
      return vendor as RtcDeviceVendor
    }
    return RtcDeviceVendor.UNKNOWN
  }

  static isShimeta(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.SHIMETA
  }

  static isDnake(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.DNAKE
  }

  static isAurine(vendor: string = RtcDeviceVendorResolver.getStoredVendor()): boolean {
    return vendor === RtcDeviceVendor.AURINE
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
