# Changelog

## Unreleased

- 新增字幕样式帧 `asr_subtitle_style`：字号、字色、底色、底色不透明度、描边色与描边宽度改由网关
  后台配置下发，端上不再硬编码配色；`style_version` 幂等，样式只作用于下一条与未闭合半句，
  已定稿历史行保留建行时快照。收不到样式帧时用内置默认（20fp 白字、黑底 60%、1fp 黑描边）。
- WebRTC native 日志默认不再往 hilog 装 sink：本 fork 的 `enableLogToDebugOutput` 入参只做范围校验、
  sink 恒按 `LS_VERBOSE` 注册，所以按档位传 WARNING 无效（装机复测仍有 112 行/秒）；
  默认改传越界值走"只移除不重装"，通话中的 `libjingle` 洪流与随之而来的格式化/写日志开销一起省掉。
  新增 `RtcCallDiagnosticsOptions.verboseNativeLog`，取证时置 `true` 装回 INFO 全量。
- 新增 `RtcHostCallControllerOptions.audioProcessing`（`RtcAudioProcessingPolicy`）：AEC/AECM/NS/HPF/AGC
  逐档由宿主注入，APM 工厂与 `createAudioSource` 约束层同写（引擎会用约束层回写 APM）。
  不传即保持既有默认（AEC/NS/HPF 开、AGC 关）。宿主当前在 api12 机型整组关 3A 换性能，
  代价是免提回声与底噪进上行，见 `docs/webrtc-audio-diagnostics.md`。
- 多路通话布局：主画面内不再重复叠一份本机预览（原来两路出现四张卡片），主区改 `layoutWeight(1)`、
  侧栏按视口定宽（220vp/300vp），控制条用等宽占位对齐，不再用 75%/25% 把主视频横向压扁。
  控制层那一行是 100%×100% 且 `zIndex(2)`，整层设 `HitTestMode.Transparent`：否则侧栏小卡的
  接听/挂断/切换点不到，第二路只能等到超时无人接听。
- 字幕浮层按路分区（主区一路 + 右侧窄栏其余各路），面板只按"该路已接通"创建、不按"已有字幕行"创建，
  待接听抑制改为仅在整组还没有接通的一路时生效。

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
- Added live subtitles on the existing `c__broadcast` downlink, against the gateway's **v2 one-sentence-per-frame
  contract**: `RtcSubtitleStore` parses the nested `asr_subtitle` frame (`sentence_text`, `utterance_id`,
  `sentence_end`, `begin_ms` / `end_ms` / `generation`, `role`), keeps one container per `uid` and one line
  per `(uid, source_number, utterance_id)`, replaces a line in place when the same utterance is revised,
  freezes it only on `sentence_end`, drops stale `seq`, counts a `seq` jump as sentences lost for good
  (`rtc_subtitle gap ... missed=n`, no re-fetch), coalesces renders to one per 200 ms, and finalizes open
  lines when the call ends. `RtcSubtitleOverlay` / `RtcSubtitlePanel` show the current sentence
  bottom-center over that call's image, one sentence above the previous one, over a faint band so light
  video backgrounds stay readable, with an expandable transcript, follow-latest and jump-to-latest;
  `RtcHostCallController.getSubtitleStore()` hands the store to the host. Captions never repeat the
  speaker name (the region already is that call); the transcript labels by `role`. The local device's own
  speech is dropped (`setLocalSpeakers`, wired in `RtcWebRtcCallController.start()`), so a screen never
  shows your own words; suppressed frames still log with `self=true`. Every frame emits one
  reconciliation log line; raw recognized text stays out of the log unless `logFrameText` is set.
  Non-subtitle broadcasts keep their existing branches. See `docs/asr-subtitle.md`.

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
