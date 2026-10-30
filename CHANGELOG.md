# Changelog

## 0.2.0

Breaking — this package is now WebRTC-only and carries no vendor-specific code.

- Removed the SIP transport: `sip/` domain, `RtcTransportProtocol.SIP`, `RtcRingtoneChannel.SIP` and
  `RtcRingtonePolicy.sipEnabled`, `RtcRuntimeSwitchHandlers.prepareSip`, and the SIP-only fields on
  `RtcCallRouteOptions` / `RtcBusinessRuntimeConfig` / `RtcRuntimeConfigControllerOptions`
  (`sipUser`, `sipPassword`, `ntpServer`, `bindingCode`, `deviceIp`). A register address that is not
  `ws://` / `wss://` now resolves invalid with the reason attached instead of falling through.
- Removed the device capability domain (`RtcDeviceVendor`, capability adapter/manager, bootstrapper,
  hardware call controller, vendor adapters). Hosts keep the adapters their own devices need and pass
  behavior in through `RtcHostCallController`: `captureCalibration` (capture resample permille, declared
  render→mic loopback delay) and `setHandsetMode`.
- Split out three packages, so this HAR no longer ships their native libraries:
  `@chindeo/ohos-curl-http` (libcurl HTTP client), `@chindeo/ohos-tts-sherpa` (offline TTS), and
  `@chindeo/ohos-gw-client` (call-gateway client, in the gateway repository; it depends back
  on this package).
- `hangupAll()` now sends one hangup per session with its own uuid instead of a single one.
- `RtcServerInfo` carries `muteRingtone` from the register payload; `onRegistered` passes it through.
- Added `RtcAppVersion.build(versionName, buildTime)` for the register payload version marker.
- Added observable ringtone decisions (`configureLogger`, `ring_local_gate` / `ring_url_gate`) and an
  opt-in URL-ringtone fallback to the local ring on `error`, refusal, or timeout.
- Added live subtitles on the existing `c__broadcast` downlink: `RtcSubtitleStore` parses the nested
  `asr_subtitle` frame, keeps one container per `uid`, splits the cumulative `text` into one line per
  completed sentence (decimal points do not break a sentence), drops stale `seq`, coalesces partial
  updates to one render per 200 ms, and finalizes open lines when the call ends.
  `RtcSubtitleOverlay` / `RtcSubtitlePanel` show the current sentence bottom-center over that call's
  image, one sentence above the previous one, with an expandable transcript, follow-latest and
  jump-to-latest; `RtcHostCallController.getSubtitleStore()` hands the store to the host. Speaker names
  are not repeated as a prefix unless one call really has several speakers. Non-subtitle
  broadcasts keep their existing branches. See `docs/asr-subtitle.md`.

## 0.1.4-rc3

- Added the `callsetting` module as the single source of truth for server-driven audio/video parameters:
  bean matching, sanitizing, video profile and audio setting resolution, local overrides, change
  detection, and periodic refresh. Hosts inject fetcher, logger and identity.
- Added the shared audio/video settings panel and page; unimplemented controls render disabled with a
  visible reason.
- Added `RtcCallControllerKey`, live `setVideoSource` on both controllers, and
  `setScreenAnswerVolumePercent`.
- Added opt-in external NV21 video input so a host can feed its own capture frames, with controller
  lifecycle callbacks and `fallbackExternalVideoToCameraKit()`.
- Added WebSocket reconnect with exponential backoff, per-device spreading, jitter, and timeouts;
  registration state now follows the live signaling connection.
- Fixed single-call hangup tearing down every active call on a repeated `c__hangup`, stale media state
  reviving an ended call, and legacy `isHangUp=false` handling.
- Released the native `PeerConnectionFactory` on dispose; bounded native capture stop before the next
  video source is created.
- Prefer H.264 constrained baseline with VP8 fallback; low-frequency per-peer RTC stats logging.

## 0.1.4-rc2

- Added `RtcCallSessionGuard`, `RtcCallControlCommandCodec` with screen/handset sources,
  `RtcCallAnswerAudioPolicy`, and `RtcSystemBarController`.

## 0.1.3

- Added package repository metadata and an `example` directory included in the released HAR.

## 0.1.2

- Added `RtcWebRtcSignalSession` and `RtcCallUiPresenter`; public package docs narrowed to runtime
  integration.

## 0.1.1

- Added runtime protocol switching, call volume, ringtone channel, status hint, admin countdown and API
  setting UI helpers; default WebRTC call volume policy 90%.

## 0.1.0

- Initial release: signaling client, call models, SDP helper, audio controller, audio route helper, and
  ringtone helper.
