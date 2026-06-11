import audio from '@ohos.multimedia.audio'

export enum RtcAudioOutputRoute {
  DEFAULT = 'default',
  SPEAKER = 'speaker'
}

export class RtcAudioRoute {
  private routeSeq: number = 0

  async setSpeaker(enabled: boolean): Promise<void> {
    const seq = ++this.routeSeq
    const routingManager = audio.getAudioManager().getRoutingManager()
    await routingManager.setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, enabled)
    if (seq !== this.routeSeq) {
      return
    }
  }

  async restoreDefault(): Promise<void> {
    await this.setSpeaker(false)
  }
}
