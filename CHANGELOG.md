# Changelog

## Unreleased

- 信令传输与通话编排出库到 `@chindeo/ohos-gw-client`：`RtcWebRtcSignalSession`、`RtcWebRtcReconnectPolicy`、
  `RtcBroadcastHistory`、`RtcWebRtcCallController`、`RtcHostCallController` 及各自用例整体迁走，逻辑未改，
  只是跨包引用改成 `@chindeo/ohos-rtc-call` 导入。协议类型 `RtcSignalTypes` 与
  `RtcWebRtcSignalStateMachine` 留在本包——`webrtc/RtcWebRtcMediaController.ets` 依赖它们，依赖方向只能是
  gw-client → rtc-call。宿主改从 gw-client 导入上述入口，并按 gw-client README 加 root `overrides`。
  2026-11-04 床旁与主机各一台真机验收通过：拨打、接听、保持/切换、单路挂断、挂断全部、两路并发、
  断网重连、字幕出字与样式、自预览开关，两台均见 `rtc_signal_recv event=c__register status=200`。

- 多路右侧侧卡不再重复显示同一路名字：无画面时 `AudioPlaceholder` 已经在头像下面画过一次，画面左下角
  那块带底色的名字 chip 只在**有画面**的侧卡上保留（真机多路第二路实测重复显示）。

- 本机自预览改由网关科室开关 `local_preview` 控制（随 `c__register` 的 `data.localPreview` 下发），
  **默认不画**：判定只认严格 `true`，键缺省/`null`/`""`/`0` 一律不画，所以新端配老网关也是不画。
  每次注册成功覆盖本地状态，注册失败不采信；通话中不轮询，改后台要等设备重连或重启应用才生效。
  关掉只把预览视图移出组件树，本机信息卡（头像 + "-- 自己"）保留，采集走 `OH_NativeImage`、
  预览 surface 只进渲染链，上行不受影响。宿主无需再接线。

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
- api23 回声消除这条线的全过程合并进 `docs/aec-echo-cancellation-api23.md`（唯一权威记录）：
  原床旁工程 10-22 那份已冻结为当日原始记录，call-gateway 那份只存在于 `v0.0.16` 分支、其网关侧取证节已并入。
- 多路通话布局：主画面内不再重复叠一份本机预览（原来两路出现四张卡片），主区改 `layoutWeight(1)`、
  侧栏按视口定宽（220vp/300vp），控制条用等宽占位对齐，不再用 75%/25% 把主视频横向压扁。
  控制层那一行是 100%×100% 且 `zIndex(2)`，整层设 `HitTestMode.Transparent`：否则侧栏小卡的
  接听/挂断/切换点不到，第二路只能等到超时无人接听。
- 字幕浮层按路分区（主区一路 + 右侧窄栏其余各路），面板只按"该路已接通"创建、不按"已有字幕行"创建，
  待接听抑制改为仅在整组还没有接通的一路时生效。
- 字幕显示收口四条：字幕态不再画标题 chip（主区和右侧窄栏都不画，`RtcSubtitlePanel` 去掉 `title`/`showTitle`
  入参——两路字幕都贴在自己画面下方，画面左上角已有同名 `NameTag`）；窄栏那一路字号
  端上压到 ≤16fp（`min(网关值, 16)`，行高跟着走，这是对"字号完全由网关下发"的唯一端上例外）；
  字幕态加净高上限并底对齐，超出先挤掉上一句、当前句不裁；静默超过 12 秒字幕整块自动收起，
  下一帧到达立即恢复，展开态不自动收。
- 字幕样式端上落盘兜底：样式帧每次真正应用后把规范化帧写进设备偏好（`RtcSubtitleStyleCache`，库
  `rtcSubtitleStyle` / 键 `style_frame`），启动时先读回套上再等网关。原因是网关的补发按"该 Peer 收过哪个版本"
  去重、而同号重复注册（app 重启/重装）刻意复用队列里的 Peer，标记跟着活下来 —— 真机见过整场一帧样式都不发，
  界面退回内置默认。回读仍走 `parseRtcSubtitleStyleFrame` 的逐项校验；这次已经收到过网关帧就不覆盖，
  读写失败只记日志不影响正文。`RtcSubtitleStore` 相应新增 `restoreStyle()`、`isStyleFromCache()` 与
  `onStyleApplied` 回调。
- 整场没收到样式帧、正文却到了，打一条 `rtc_subtitle_style absent reason=no_frame_before_body
  rendered=cache|builtin fontSize=.. bgOpacity=..`（每场一次）；套用缓存打 `rtc_subtitle_style restored
  version=.. source=cache`。用来分"网关没下发"、"用的缓存"和"端上没套用"，不必再靠截图猜。

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
