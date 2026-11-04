# @chindeo/ohos-rtc-call

Reusable OpenHarmony (ArkTS) audio/video call library for WebRTC hosts: the WebRTC media layer, call state
stores, signalling protocol types and state machine, ringtone and audio-route policies, and shared call UI
building blocks.

The call-gateway signalling transport and the host-facing call controller live in
`@chindeo/ohos-gw-client`, which depends back on this package (see "Separated packages" below).

One transport only — WebRTC over `ws://` / `wss://` signaling. Vendor SDK bindings and device-specific
behavior are expected to stay in the host application and be injected as configuration.

## Install

```shell
ohpm install @chindeo/ohos-rtc-call
```

The host must provide a compatible `@ohos/webrtc` dependency and the runtime permissions it uses.

## Features

- Register address resolution: `ws://` and `wss://` resolve to a signaling URL; any other address comes
  back invalid with the reason attached.
- Signaling contract and SDP/ICE state machine: event names, the `publish` / `subscribe` channel scope, and
  the remote-description and candidate handling driven through a host-supplied peer connection adapter.
- Local media: low-latency audio setup, SDP Opus parameters, CameraKit sources, and opt-in external NV21
  frames when the host owns camera capture.
- Ringtone and ringback helpers with a channel guard, plus server-driven ringtone URLs with local fallback.
- Answer audio policy: screen answer on speaker, handset answer off speaker, per-source volume percent.
- Host-injected device behavior (see below): capture clock/delay calibration and handset route switching.
- Server-driven call settings (`callsetting`): resolution and bitrate profile, answer volume, local
  override store, change detection, periodic re-fetch.
- Runtime config coordination for `call.rtcServerHost` and `call.micSwitching`.
- Startup data cache, network recovery state, and incoming-call queue helpers.
- UI helpers: call status hint, admin-entry countdown, API endpoint settings dialog, reference call layout.
- Live subtitles from `c__broadcast` (`asr_subtitle` frames): per-`uid` containers, per-speaker color,
  sequence de-duplication, 200 ms coalescing, follow/scroll-back panel. See `docs/asr-subtitle.md`.
- Shared call state and signal models.

## Separated packages

These used to live in this package and are now standalone; the HAR no longer carries their native
libraries:

- `@chindeo/ohos-curl-http` — libcurl-backed HTTP client (`CurlAxios`).
- `@chindeo/ohos-tts-sherpa` — offline sherpa-onnx TTS engine with its text frontend.
- `@chindeo/ohos-gw-client` — call-gateway client: the WebSocket signal session and reconnect policy,
  `uid`-scoped call orchestration, broadcast history parsing and the `RtcHostCallController` facade. It
  depends back on this package.

Vendor device capabilities (MAC, boot app, power schedule, silent install, LED, hardware keys, handset
events) are also out of this package: each host keeps only the adapters its own devices need.

## Host integration

### Injected device behavior

The controller does not probe devices. The host passes what it knows about its own hardware
(`RtcHostCallController` itself comes from `@chindeo/ohos-gw-client`):

```ts
const controller = new RtcHostCallController({
  serverUrl,
  local,
  appVersion: 'v1.0.0_hmos_20261027120000',
  // Clock/scale calibration for the capture path and the declared render→mic loopback delay.
  // Omit both to keep native defaults (0).
  captureCalibration: {
    captureResamplePermille: 1068,
    aecStreamDelayMs: 216,
    vendorLabel: 'some-vendor'
  },
  // Route the call audio to the handset earpiece / back to the board.
  setHandsetMode: (enabled: boolean, reason: string): void => {
    applyHandsetRoute(enabled, reason)
  }
})
```

### Call rules to keep

- `uid` / `signalUID` is the business session key, `rtcUID` is the channel key, `channelType` is
  `publish` or `subscribe`; treat them as opaque strings and return the same triple on answer and ICE.
- Answering is confirmed only by the gateway answer API; `OnTrack`, ICE connected, or a remote
  description being applied do not count as answered.
- Dialing establishes `publish` only; the `subscribe` channel is created after a successful answer.
- Numbers and display names are for presentation and contact lookup, never as a call key.

### UI policies

- Check `RtcCallSessionGuard.isWebRtcCallInProgress(session)` before any background registration refresh,
  so a re-prepare cannot hide an active call view.
- Build control events with `RtcCallControlCommandCodec.build(action, sequence, source)` and keep the
  handset and screen sources distinct.
- Map answer source to local audio with `RtcCallAnswerAudioPolicy.resolve(source)`.
- `RtcSystemBarController` keeps navigation-bar visibility consistent within one app process; it resets
  on app exit.
- Keep `RtcHostCallController.onUiModelChange()` as the only call-state source for the call layout.

### Ringtone resources

Normal incoming `ringtone/ring1.wav`, outgoing `ringtone/ringback.wav`, transfer
`ringtone/transfer_ringback.wav`, hold `ringtone/hold.wav`, and presence events
`ringtone/presence_normal_ring.wav`, `ringtone/presence_bluecode_ring.wav`,
`ringtone/presence_sanitary_ring.wav`.

### Call settings

`RtcCallSettingController.load(reason)` is single-flight and falls back remote → bundled → code default,
then applies the local resolution override; `onChange` fires only on a real diff, and
`startAutoRefresh()` re-fetches periodically while keeping the previous snapshot on failure. Beans match
by `mac`, then `packageName`, then `deviceType`. `audio.deviceVolume` is a percentage (`-1..100`) written
to the device call stream level; `audio.streamVolume` and `startKbps` have no effect in this build.

## Basic usage

More complete examples are in the `example` directory.

```ts
import { RtcAudioController, RtcCallRouteResolver } from '@chindeo/ohos-rtc-call'
import { RtcWebRtcSignalSession } from '@chindeo/ohos-gw-client'

const route = RtcCallRouteResolver.resolve({ registerAddress: 'wss://your-signaling.example/ws' })
if (!route.registerAddress.valid) {
  console.warn(`invalid signaling address: ${route.registerAddress.reason}`)
}

const signal = new RtcWebRtcSignalSession()
signal.setListener({
  onRegister: (_message, server) => console.info(`registered to ${server?.serveNumber || ''}`),
  onReconnectScheduled: (attempt, delayMs, reason) =>
    console.info(`reconnect attempt=${attempt} delayMs=${delayMs} reason=${reason}`)
})
signal.connect({
  serverUrl: route.webrtcSignalUrl || '',
  appVersion: 'v1.0.0_hmos_20261027120000',
  identity: { number: '1001', clientType: 'client', displayName: 'RTC Client' }
})

const audio = new RtcAudioController()
audio.ensureReady()
```

With a host-owned capture pipeline, prepare an external source and forward frames; the package never
opens the device:

```ts
audio.prepareLocalVideo({ trackId: 'local-video', width: 640, height: 480, frameRate: 15, externalNv21: true })
audio.pushLocalVideoNv21Frame(frame, 640, 480)
```

Choose `externalNv21` only after the host has confirmed the capture device exists. If opening fails,
call `controller.fallbackExternalVideoToCameraKit()` rather than leaving an empty live track, and do not
hang up unrelated active calls over a local-video failure.

## Security

The package ships no server addresses, credentials, private keys, device identifiers, vendor SDK
binaries, or bundle names. Inject deployment-specific values from the host application.

## License

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE) for the upstream versions and licences of the
WebRTC code in the shipped `libs/<abi>/libohos_webrtc.so`.
