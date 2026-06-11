# Changelog

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
