# Changelog

## 0.1.4-rc3 timestamp HAR

- Fixed legacy WebSocket `c__hangup.data.isHangUp` handling so `false` preserves publish and the call page, while `true` or a missing field fully closes publish and the call UI.
- Prevented stale connected media state from reviving a hidden or ended single-call UI after hangup.
- Added focused regression coverage for single-call hangup, multi-call keep-alive, `c__offline`, and stale media-state handling.

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
