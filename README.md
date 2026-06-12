# @chindeo/ohos-rtc-call

Reusable OpenHarmony audio/video call utilities for ArkTS applications.

## Features

- Register address routing: `ws://` and `wss://` use WebRTC, other `ip:port` addresses use SIP.
- WebSocket signaling clients for WebRTC call flows, including shared registration URL building and connection-state tracking.
- SIP config and adapter interfaces for host-provided Dnake SDK integration.
- WebRTC audio helper for low-latency audio call setup.
- call-gateway SDK client for uid-based call control, SDP/ICE routing, and host-injected transport adapters.
- SDP utilities for Opus low-latency audio parameters.
- Audio output routing helper for speaker/default routes.
- Ringtone and call volume helpers, including WebRTC/SIP ringtone channel guards.
- WebRTC answer audio policy helpers for screen speakerphone answers and handset non-speaker answers.
- Runtime config coordinator for `call.rtcServerHost` and `call.micSwitching` changes.
- Startup data cache and network recovery state helpers for startup pages that must continue with cached data while business APIs recover.
- Incoming-call queue helpers for nurse hosts that need to display multiple bedside calls without replacing the active call session.
- Device capability adapters for vendor-specific MAC, boot, power, LED, and hardware key actions.
- UI helpers for RTC status hints, admin-entry countdowns, API endpoint settings, and host/bed call view presentation models.
- Process-local system navigation-bar visibility and window application helpers.
- Shared call state and signal models.

## Ringtone Policy

- Normal WebRTC incoming calls: `ringtone/ring1.wav`
- Normal SIP incoming calls: `ringtone/ring1.wav`
- WebRTC/SIP outgoing ringback: `ringtone/ringback.wav`
- Transfer ringback: `ringtone/transfer_ringback.wav`
- Call hold: `ringtone/hold.wav`
- Presence calls: use `ringtone/presence_normal_ring.wav`, `ringtone/presence_bluecode_ring.wav`, or `ringtone/presence_sanitary_ring.wav` by event type.

## Install

```shell
ohpm install @chindeo/ohos-rtc-call
```

The host application must also provide a compatible `@ohos/webrtc` dependency and request the required runtime permissions. Vendor SDK implementations such as Dnake or Shimeta are injected by the host application through adapters and are not bundled in this package.

## Host WebRTC UI Policies

- Use `RtcCallSessionGuard.isWebRtcCallInProgress(session)` before refreshing WebRTC registration from a host page. If it returns true, skip background prepare work that would reset call visibility.
- Use `RtcCallControlCommandCodec.build(action, sequence, source)` for hardware or UI control events. Use `RTC_CALL_CONTROL_SOURCE_HANDSET` when the handset is lifted, and `RTC_CALL_CONTROL_SOURCE_SCREEN` for on-screen answer buttons.
- Use `RtcCallAnswerAudioPolicy.resolve(source)` to map answer source to local audio policy. Screen answers use speakerphone and 90% voice-call volume; handset answers use non-speaker output and 40% voice-call volume.
- Use `RtcSystemBarController.setNavigationBarVisible(...)` from settings pages and `applyNavigationBarPreference(...)` from each ability/window lifecycle to keep system navigation-bar visibility consistent across pages in the current app process. This state is for temporary remote debugging and resets to hidden after app exit or restart.

## Basic Usage

More complete examples are available in the `example` directory.

```ts
import { RtcAudioController, RtcCallRouteResolver, RtcTransportProtocol, RtcWebRtcSignalSession } from '@chindeo/ohos-rtc-call'

const route = RtcCallRouteResolver.resolve({
  registerAddress: 'wss://your-signaling.example/ws',
  sipUser: '1001',
  sipPassword: '',
  deviceIp: ''
})

if (route.protocol === RtcTransportProtocol.SIP) {
  // Configure the host app's Dnake SIP adapter with route.sipConfig.
}

const signal = new RtcWebRtcSignalSession()

signal.setListener({
  onRegister: (_message, server) => {
    console.info(`registered to ${server?.serveNumber || ''}`)
  },
  onMessage: message => {
    console.info(`rtc signal ${message.eventName}`)
  }
})

signal.connect({
  serverUrl: route.webrtcSignalUrl || '',
  appVersion: 'your_app_webrtc',
  identity: {
    number: '1001',
    clientType: 'client',
    displayName: 'RTC Client'
  }
})

const audio = new RtcAudioController()
audio.ensureReady()
```

## call-gateway SDK

Use `RtcCallGatewayClient` when a host app integrates with call-gateway audio/video callbacks. The host app owns the concrete gateway transport and injects it through `RtcCallGatewayAdapter`; this package keeps only SDK state, uid routing, and WebRTC SDP/ICE handling.

```ts
import { RtcCallGatewayClient } from '@chindeo/ohos-rtc-call'

const client = new RtcCallGatewayClient({
  adapter: hostGatewayAdapter,
  peerAdapter: hostWebRtcPeerAdapter,
  local: { number: 'host-1001', displayName: 'Host Device' }
})

client.handleOpenMultiActivity('bed-1002', 'Bed 1002', 'signal-uid-1002', false)
client.answer('signal-uid-1002')
```

Call operations must use call-gateway `uid` / `signalUID`. SDP and ICE routing must preserve `rtcUID` and `channelType`; numbers are display and lookup fields only.

## Security

This package does not include business server addresses, signing credentials, private keys, device identifiers, Dnake SDK binaries, or application bundle names. Inject all deployment-specific values from the host application.

## License

Apache-2.0
