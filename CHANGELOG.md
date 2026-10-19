# Changelog

## Unreleased

- Added `RtcAppVersion.build(versionName, buildTime)`, which formats the register payload's `appVersion` as `v<versionName>_hmos_<yyyyMMddHHmmss>` to match how the Android AAR devices report themselves (`v0.0.17_linux_…`) and replace the `bed_native_webrtc` / `nurse_native_webrtc` role markers; the role stays available as `clientType`, and the build timestamp comes from a `BUILD_TIME` constant each host's build script stamps per variant. Note `systemType` is deliberately untouched: the gateway uses `SystemTypeHmos` to decide whether to base64-wrap the SDP it sends, so switching it is a protocol change, not a label change.
- Exported `combineHttpUrl` from the http module so hosts can log the address the client actually requests. The bedside interceptor used to hand-concatenate `baseURL + url`, which printed `https://hostapp/perm/obtainBedPerms` for a request that was in fact correct — the missing `/` is inserted by `combineHttpUrl`, not by the caller.

- Fixed the rebuilt sherpa NAPI shim never initializing. `SherpaOnnxOfflineTtsZipvoiceModelConfig` was declared two floats short of the v1.12.18 header, which shifted every field after it, so `silence_scale` reached `SherpaOnnxCreateOfflineTts` as `0` and the engine returned null — the bedside only showed "TTS 未初始化". The structs now match `c-api.h` field for field, `max_num_sentences` / `silence_scale` are set explicitly (the C API struct carries no defaults), `Reject()` logs the reason natively and rejects with a real `Error` so hosts no longer see `undefined`, and async work carries a resource name. Verified on .104: `stage=init ok=true create_ms=11404 fsts=3`.

- Fixed the shared WebRTC controller tearing down every active call when the server echoed `c__hangup` for a session that was already removed by a local single-call hangup. The echo guard now runs for every `c__hangup` (previously short-circuited by the terminal policy), and the terminal close-all fallback keeps other sessions whenever the payload carries an identity or more than one call is active. `c__offline` and the last-session close-all semantics are unchanged.
- Known boundary (host-validated 2026-10-15 on .61/.93): a `c__hangup` that carries **no** session identity (`uuid`/`rtcUid`/target number all empty) while exactly **one** call remains still closes the whole group, preserving the `b45dd98` single-call close-on-terminal semantics. Android `RtcInitCall.kt:578` instead skips the close-all whenever any other target exists, ignoring the count. Real traffic always carries an identity, so the echo is caught by the guard first; not aligning now to avoid reintroducing the "single-call UI does not close" regression, to be revisited only if device evidence shows a stale identityless terminal.
- Made `RtcRingtoneController` observable: `playIncoming` / `playUrl` now emit a `ring_local_gate` / `ring_url_gate` line through an optional `configureLogger` callback whenever they skip, start, or the driver refuses, so a server-configured URL ringtone that silently does nothing reports the exact reason (`emptyUrl`, `policyDisabled`, `busy`, `channelDisabled`, `noDriver`, `driverNoUrl`) instead of returning with no trace. Purely additive: no default sink, behavior unchanged when no logger is wired, and the `externalUrlEnabled` default stays `false` (hosts opt in via `configurePolicy`).
- Added the URL ringtone fallback race: `playUrl` can now hand the driver an `onResult` callback that reports `playing` / `error` / `idle`, and when `urlFallbackEnabled` is opted in the controller resets the url player and starts the prewarmed local ring on `error`, refusal, or `urlFallbackTimeoutMs` (default 1200ms) without hearing `playing`. It logs `ring_url_gate result=fallback reason=<io|timeout|refused>`. Disabled by default, so a host whose driver never reports an outcome keeps its current behaviour instead of getting a second ring layered on top. See `docs/ringtone-url-fallback.md`.
- Added offline TTS on sherpa-onnx: the `tts` module, its armeabi-v7a prebuilt native chain (including a self-built onnxruntime 1.16.3 in softfp+NEON for the 32-bit bedside runtime), and `createAsync` / `generateAsync` so loading the model stays off the main thread and no longer trips the lifecycle watchdog.
- Added call-announcement events matching Android: `c__broadcast` payloads that carry `status` are now parsed into `RtcBroadcastHistory` and raised through `onCallHistory` (hold notices keep their existing in-controller handling, everything unrecognised still goes to `onBroadcast`), and `RtcHostCallController` raises `onAutoAnswerNotice` when an incoming session meets `autoAnswer`. The bedside maps these to the sherpa TTS voice: `为您自动接听` with the ring stopped, and `无人接听` only when the history is a timeout for a call this device placed, de-duplicated by `uid`. See `docs/call-broadcast-announce.md`.
- Fixed the URL ringtone fallback never firing under real timing. The pending-fallback intent was a local of `playUrl`, so a driver that resolves `true` first and reports `error`/`idle` a few dozen milliseconds later — which is how `AVPlayer` IO failures always arrive — only set `settled` and cleared the timer, writing the intent into a variable nobody read again: no `result=fallback`, no local ring, total silence. The fallback context is now an instance field, a late report triggers the fallback in place, and `stop()` cancels it so a post-hangup `idle` cannot restart the ring. `docs/ringtone-url-fallback.md` also pins the driver-side `audioRendererInfo` order (url → set renderer in `initialized` → prepare) that hosts must follow to avoid `5400102`.
- Fixed digits being silent in every announcement: the matcha Chinese lexicon only knows pinyin, so `21床,正在呼叫。` came out as "床,正在呼叫". The controller now hands `number.fst,date.fst,phone.fst` to sherpa as `ruleFsts` (the NAPI shim reads a new `ruleFsts` config field instead of hardcoding an empty string, and the shim has been rebuilt for armeabi-v7a softfp). Real-device proof on .99: the same sentence is 1.867s of audio with the fsts and 1.21s without. This replaces the short-lived in-house `normalizeTtsText` so there is only one text-normalization layer; note the trap that made this look like a softfp crash — `--rule-fsts` is the ASR flag, TTS wants `--tts-rule-fsts`, and passing the wrong one exits with RC=255 before anything opens an fst. Missing fst files no longer break init (the engine still starts and only loses number reading), so older hosts that have not shipped them keep working.
- Fixed TTS playback never producing sound. `playWav` called `prepare()` straight after assigning the source and never called `play()`, so the first real-device attempt failed with `current state is not stopped or initialized, unsupport prepare operation` — the same `idle`-vs-`initialized` rule the ringtone path already follows. The player now runs the documented state machine (`fdSrc` → prepare in `initialized` → play in `prepared` → resolve on `completed`), resolves instead of hanging when `stop()` cuts a phrase short, and reads the local wav through `fdSrc` rather than an unverified `fd://` url. `stop()` also bumps a generation counter, so pressing it while a phrase is still synthesizing (the multi-second part the bedside test page used to ignore) cancels that phrase instead of playing it out after the user asked for silence.
- Fixed a single announcement wedging the whole queue for two minutes. The bedside renderer intermittently fails to start (`AudioRenderProxyStart: call failed! error code is -1`), and the player then sits in `playing` until the pipeline drains it — measured at 113s for a 2.31s wav, with `framePosition` never leaving 0. `playWav` now takes the audio duration and watchdogs the promise at `max(3s, duration + 4s)`, releasing the stuck player and retrying once with a fresh one, so the worst case is a 6s gap instead of a frozen queue. Announcements also queue and play out in full rather than pre-empting each other: `stop()` only cancels the phrase in flight (the generation is taken when a phrase starts, not when it is requested), so a hangup-driven stop can no longer swallow a queued call announcement. Clock times and serial numbers are normalized to Chinese words before the engine sees them, because `number.fst` runs first and reads `01177125` as "一千一百七十七万一千二百五" and never leaves `date.fst`/`phone.fst` anything to match; short numbers such as bed and temperature values still go through the fsts.
- Added the TTS取证锚点 `rtc_tts_perf`（纯日志，不改行为）：`stage=init` 带 `create_ms/threads/noiseScale/fsts`，`stage=enqueue|synth|play|skip|stop|fail` 带 `seq/synth_ms/audio_ms/rtf/play_ms/attempts/queue`。之前"没出声"、"播了但听不见"和"队列卡住"在日志上是同一个样子，验收清单里的 RTF 和长时间不失效两项也无从判定。`playWav` 现在返回实际尝试次数以便区分一次过和重试过。
- Added the server-driven ring mute: `RtcServerInfo` now carries `muteRingtone` from the `c__register` success payload (`true` = announce only, no ringtone), and `RtcHostCallController`'s `onRegistered` **signature changed** to pass the parsed `RtcServerInfo` through, since the flag is only known at registration. The package itself applies no default — the product口径 (2026-10-17) is **ring muted unless the gateway sends an explicit `false`**, because the gateway currently omits the field in both switch states; hosts implement it as `server.muteRingtone !== false`. Both hosts store it and gate `playIncomingRingtone` alongside their existing `isPlayRingtone` policy, and the bedside skips the ring prewarm while muted. See the `muteRingtone` section of `docs/call-broadcast-announce.md`.

- Rebuilt the sherpa NAPI shim from source and put that source in the repo. `sherpa_tts_napi.cpp` had never been committed — only the `libs/armeabi-v7a/libsherpa_onnx.so` artifact and a sha256 that no longer matched the shipped file (`48fd705d…` recorded, `62ca9394…` actual) — so when the `dataDir` field was needed for `matcha-icefall-zh-en` there was nothing on this machine to edit. The rewrite keeps the exported surface identical (`create/createAsync/destroy/generate/generateAsync/sampleRate/numSpeakers`, module name `sherpa_onnx`, tag `SherpaShim`, handles are index+1 so `0` still means "no engine"), adds the optional `dataDir` (espeak-ng-data's parent, required for any Chinese+English model to voice Latin letters), and is now built by `tools/build-sherpa-shim.sh`. Two traps are recorded in `docs/tts-models-and-native-build.md`: do not pass `-nostdlib++` (the typeinfo/vtable relocations resolve at load time, before the constructor's `dlopen` can help), and the struct field order must track sherpa-onnx **v1.12.18** `c-api.h:1019-1100`. The rebuilt `.so` (`30,508` bytes, `9719231a911c…`) is only statically compared against the previous artifact — it has not been device-verified yet.

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
- Wait for native capture to confirm it stopped before creating the next bedside video source, bounded by a default 1500 ms timeout, so an overlapping `CreateCaptureSession` cannot wedge `camera_service` while the previous session object is still alive.

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
