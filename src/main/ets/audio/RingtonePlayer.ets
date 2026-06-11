import media from '@ohos.multimedia.media'

let player: media.AVPlayer | undefined = undefined

export async function playRingtone(url: string): Promise<void> {
  await stopRingtone()
  if (!url) {
    return
  }
  const next = await media.createAVPlayer()
  player = next
  next.url = url
  next.loop = true
  await next.prepare()
  await next.play()
}

export async function stopRingtone(): Promise<void> {
  const current = player
  player = undefined
  if (!current) {
    return
  }
  try {
    await current.stop()
  } catch (_error) {
  }
  try {
    await current.release()
  } catch (_error) {
  }
}
