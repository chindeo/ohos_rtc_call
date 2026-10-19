const SYSTEM_TYPE = 'hmos'

export class RtcAppVersion {
  // 注册报文里的 appVersion，后台「音视频版本」列原样展示。安卓侧走的是设备内 AAR
  // 的编译期版本常量（v0.0.17_linux_<时间>），这里对齐同一格式，别再回落到角色标记串。
  static build(versionName: string, buildTime: string): string {
    const version = (versionName || '').trim() || 'unknown'
    const time = (buildTime || '').trim()
    return time.length > 0 ? `v${version}_${SYSTEM_TYPE}_${time}` : `v${version}_${SYSTEM_TYPE}`
  }
}
