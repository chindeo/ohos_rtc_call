# Changelog

## Unreleased

- Fixed the shared WebRTC controller tearing down every active call when the server echoed `c__hangup` for a session that was already removed by a local single-call hangup. The echo guard now runs for every `c__hangup` (previously short-circuited by the terminal policy), and the terminal close-all fallback keeps other sessions whenever the payload carries an identity or more than one call is active. `c__offline` and the last-session close-all semantics are unchanged.
- Known boundary (host-validated 2026-10-15 on .61/.93): a `c__hangup` that carries **no** session identity (`uuid`/`rtcUid`/target number all empty) while exactly **one** call remains still closes the whole group, preserving the `b45dd98` single-call close-on-terminal semantics. Android `RtcInitCall.kt:578` instead skips the close-all whenever any other target exists, ignoring the count. Real traffic always carries an identity, so the echo is caught by the guard first; not aligning now to avoid reintroducing the "single-call UI does not close" regression, to be revisited only if device evidence shows a stale identityless terminal.
- Made `RtcRingtoneController` observable: `playIncoming` / `playUrl` now emit a `ring_local_gate` / `ring_url_gate` line through an optional `configureLogger` callback whenever they skip, start, or the driver refuses, so a server-configured URL ringtone that silently does nothing reports the exact reason (`emptyUrl`, `policyDisabled`, `busy`, `channelDisabled`, `noDriver`, `driverNoUrl`) instead of returning with no trace. Purely additive: no default sink, behavior unchanged when no logger is wired, and the `externalUrlEnabled` default stays `false` (hosts opt in via `configurePolicy`).
- Added the URL ringtone fallback race: `playUrl` can now hand the driver an `onResult` callback that reports `playing` / `error` / `idle`, and when `urlFallbackEnabled` is opted in the controller resets the url player and starts the prewarmed local ring on `error`, refusal, or `urlFallbackTimeoutMs` (default 1200ms) without hearing `playing`. It logs `ring_url_gate result=fallback reason=<io|timeout|refused>`. Disabled by default, so a host whose driver never reports an outcome keeps its current behaviour instead of getting a second ring layered on top. See `docs/ringtone-url-fallback.md`.
- Added offline TTS on sherpa-onnx: the `tts` module, its armeabi-v7a prebuilt native chain (including a self-built onnxruntime 1.16.3 in softfp+NEON for the 32-bit bedside runtime), and `createAsync` / `generateAsync` so loading the model stays off the main thread and no longer trips the lifecycle watchdog.

## 0.1.4-rc3 timestamp HAR (2026-10-13)

- Added the `callsetting` module as the single source of truth for server-driven audio/video parameters: bean matching, sanitizing, video-profile and audio-setting resolution, local override storage, change detection, and 5-minute auto refresh. Host applications now inject a fetcher, a logger and the device identity instead of re-implementing parsing.
- Treated `audio.deviceVolume` as a percentage (`-1..100`), matching the Android `call-lib` source, and kept `streamVolume` and `startKbps` documented as not implementable on this WebRTC SDK.
- Added the shared audio/video settings panel and page shell (`RtcCallSettingPanel`, `RtcCallSettingPage`, `RtcCallSettingPanelModel`) so both devices render one implementation; controls that are not implemented render greyed out with a visible reason and swallow the tap instead of pretending to take effect.
- Added `RtcCallControllerKey` so a host can decide whether a device-identity change really requires rebuilding the controller.
- Added live `setVideoSource` on the WebRTC media controller and `setVideoSource` / `setScreenAnswerVolumePercent` on the host controller, so an updated `call_setting` takes effect on the next track without re-registering.
- Fixed the resolution list behaving as multi-select: `@Builder` value parameters do not re-render, so the row now takes a single object literal and the row key carries the selected state.
- Fixed saving only a volume override also pinning the currently effective resolution as a local override.
- Added focused unit coverage for the merged policy and for the controller's fallback, override and change-detection paths using injected fetcher and override doubles.

## 0.1.4-rc3 timestamp HAR

- Added opt-in external NV21 video sources so a host can feed vendor UVC frames into WebRTC without invoking CameraKit.
- Added host-controller external video lifecycle callbacks and frame forwarding so applications can open UVC only for video calls and close it during teardown.
- Added a native libcurl/OpenSSL HTTP compatibility client with Axios-style instances and interceptors for OpenHarmony firmware affected by Network Kit hostname-resolution error `2300006`.
- Added WebSocket reconnect with exponential backoff, per-device cohort spreading, random jitter, connection/register timeouts, and stable-registration reset protection.
- Made WebRTC registration state follow the live signaling connection instead of controller creation, while preserving active media sessions during signaling recovery.
- Fixed legacy WebSocket `c__hangup.data.isHangUp` handling so `false` preserves publish only when another local call remains, while the last session, `true`, or a missing field fully closes publish and the call UI.
- Prevented stale connected media state from reviving a hidden or ended single-call UI after hangup.
- Added focused regression coverage for single-call hangup, multi-call keep-alive, `c__offline`, and stale media-state handling.
- Added optional local video `deviceId` forwarding so hosts can bypass incompatible automatic camera enumeration on vendor firmware.
- Release the native PeerConnectionFactory when the host controller is disposed so WebRTC worker, network, and video-source threads do not accumulate across page lifecycles.
- Reject late SDP, ICE, and answer signals after a call session reaches its terminal state, preventing closed calls from recreating subscribe peers during teardown.
- Preserve the shared publish peer only while another call remains; the last local hangup now releases all WebRTC media resources immediately.
- Prefer H.264 constrained baseline through transceiver codec preferences while retaining VP8 fallback, and log negotiated video codec summaries without logging full SDP.
- Send host multi-call answers immediately for the selected UID instead of waiting for media readiness, while preserving targeted hangup isolation for remaining calls.
- Publish the remaining call state before single-call termination callbacks so host pages stay visible while another call is active.
- Bind side-call video tracks to session-specific renderers and limit live side previews to one by default, keeping additional video calls as placeholders.
- Emit low-frequency per-video-peer RTC stats for negotiated codec, direction, resolution, FPS, frame count, bytes, and packet loss, with timers tied to peer teardown.
- Enforce exact camera and sender frame-rate limits, recover a stalled native camera stream without rebuilding the call, and replace the local publish track once when native recovery is exhausted.

## 0.1.4-rc3

- Added `RtcCallGatewayClient` and gateway adapter types for call-gateway uid-based call control, SDP answer routing, ICE candidate routing, and multi-call session snapshots.
- Added a call-gateway compile-time example and focused Hypium tests for uid routing, gateway answer semantics, SDP route preservation, local candidate sending, and targeted hangup.
- Added shared WebRTC signaling state machine for SDP/Candidate routing, stale session filtering, PeerConnection dispatch, ICE diagnostics, and local answer SDP waiting.
- Added focused Hypium unit tests for WebRTC signal routing, scoped rtcUid handling, stale filtering, candidate queue flushing, and answer generation.
- Extended `RtcAudioController` with shared local audio/video track lifecycle, renderer binding, AEC dump control, PCM sample stats, and cleanup snapshots.
- Added `RtcDefaultCallService` for shared call session control, incoming/outgoing state transitions, auto answer, hold/resume, hangup, and control command dispatch.
- Extended `RtcDefaultCallService` with an incoming-call queue so nurse hosts can retain multiple bedside calls without overwriting the active media session.
- Added `RtcCallAudioPolicyController` for shared answer audio routing, volume boost/restore, handset mode, mute state, and device role policy parameters.
- Added `RtcHardwareCallController` for shared hardware call-key and handset event dispatch through common call control commands.
- Added `RtcAdminEntryController` for startup long-press admin entry, startup pause/resume, pending navigation protection, and delayed home navigation.
- Added `RtcRuntimeConfigController` for runtime config loading, RTC server host selection, changed-key detection, protocol switch planning, and micSwitching application.
- Added `RtcStartupDataCache` for startup API data caching and cache fallback when business APIs are temporarily unavailable.
- Added `RtcNetworkRequestRecoveryController` for consistent network-error prompts and recovery-state clearing after API requests resume.

## 0.1.4-rc2

- Added `RtcCallSessionGuard` for protecting visible WebRTC call UI from background prepare/registration refreshes.
- Added `RtcCallControlCommandCodec` with screen/handset source metadata for call control events.
- Added `RtcCallAnswerAudioPolicy` for shared WebRTC answer routing: screen answer uses speakerphone at 90%, handset answer uses non-speaker output at 40%.
- Added `RtcSystemBarController` for shared process-local system navigation-bar visibility and window application.

## 0.1.3

- Added package repository metadata for OHPM scoring.
- Added an `example` directory with a safe WebRTC/SIP integration sample.
- Updated the package script so examples are included in the released HAR.

## 0.1.2

- Added `RtcWebRtcSignalSession` for shared WebRTC signal URL building, connection deduplication, registration state tracking, packet splitting, raw signal sending, and error callbacks.
- Added `RtcCallUiPresenter` to map shared call view state into host/bed UI layouts, labels, volume visibility, and action states.
- Kept package docs focused on runtime integration and removed internal release workflow notes from public package content.
- Documented host/bed volume policy updates for downstream apps: host 30%, bedside 70%.

## 0.1.1

- Added runtime protocol switching helpers for WebRTC/SIP register addresses.
- Added Dnake SIP runtime interfaces and SIP call state mapping helpers.
- Added vendor capability adapters and bootstrap helpers for Dnake/Shimeta devices.
- Added call volume, ringtone channel, status hint, admin countdown, and API setting UI helpers.
- Updated WebRTC default call volume policy to 90%.

## 0.1.0

- Initial reusable OpenHarmony RTC call utilities.
- Added signaling client, call models, SDP helper, audio controller, audio route helper, and ringtone helper.
