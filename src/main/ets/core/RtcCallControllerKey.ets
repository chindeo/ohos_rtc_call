export interface RtcCallControllerKeyInput {
  serverUrl: string
  localNumber: string
  displayName: string
  clientType: string
  identity: string
  ip: string
  locId: string
  hospitalId: string
  autoAnswer: boolean
}

/**
 * 宿主组件判断"要不要重建 controller"的唯一依据。两端共用一份，避免
 * 床旁和主机各自维护字段清单导致漂移。
 */
export class RtcCallControllerKey {
  static of(input: RtcCallControllerKeyInput): string {
    const payload: RtcCallControllerKeyInput = {
      serverUrl: input.serverUrl,
      localNumber: input.localNumber,
      displayName: input.displayName,
      clientType: input.clientType,
      identity: input.identity,
      ip: input.ip,
      locId: input.locId,
      hospitalId: input.hospitalId,
      autoAnswer: input.autoAnswer
    }
    return JSON.stringify(payload)
  }
}
