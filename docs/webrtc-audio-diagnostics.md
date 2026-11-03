# WebRTC 音频诊断记录

## 诊断原则

- 先区分问题属于信令、媒体 track、音频路由、系统音量、厂家硬件路径还是远端播放。
- 不把 `OnTrack`、ICE connected、PeerConnection connected 或 publish ready 单独当作业务接听完成。
- 媒体接通以目标 `subscribe` 收到并匹配远端 track 为准。
- “无声音”报告不要先假设床旁应用错误，应同时确认主机输出音量、物理听筒/免提路径和远端 track。

## 有效日志信号

- 本地采集正常：能看到 local audio track 获取、`readyState=live`、publish addTrack 和 sender track。
- 远端接收正常：目标 subscribe peer 收到远端 audio track，并且 track 绑定到当前目标通话。
- 路由正常：音频模式、扬声器/听筒状态、通话音量档位与当前接听入口一致。
- 通话 UI 正常：业务接听、保持、挂断等状态来自目标 `uid`，不是最新通话或当前选中卡片。

## 低风险保留项

- WebRTC 音频默认走公共低时延参数和 Opus SDP 优化。
- 通话音量提升与恢复由公共音量工具处理。
- 主机、床旁的音频路由差异通过角色、接听入口和厂家 adapter 注入。
- 音频诊断日志应保留 `uid`、`rtcUID`、`channelType`、target 和媒体类型，避免记录业务敏感内容。
- SDP、ICE、连接回调和 ontrack 都需要 session/rtcUid stale guard，防止旧异步回调污染下一通电话。
- 单个 subscribe 异常只清理目标下行；不要重置共享 publish 或其它活跃通话。

## native 日志档位（hilog 洪流开关）

- `RtcAudioController` 通过 `NativeLogging.enableLogToDebugOutput(severity)` 控制 WebRTC 内部日志是否进 hilog。
  severity 取 WebRTC `LoggingSeverity`：VERBOSE=0、INFO=1、WARNING=2、ERROR=3、NONE=4。
- **本 fork 的 native 入口没有按档位过滤**：入参只做范围校验，sink 一律以 `LS_VERBOSE` 注册，
  所以"传 2 只留告警"是无效的——2026-11-03 那样做过一次，装机后 `libjingle` 仍有 112 行/秒。
  越界值（当前用 5）反而走到"只移除 sink、不重装"的分支，等于彻底不往 hilog 写。
- 因此默认**不装 sink**（传 5），取证时才装回 INFO(1)：
  `RtcHostCallControllerOptions.diagnostics.verboseNativeLog: true`。装/卸由
  `nativeLogSinkInstalled` 记状态，避免重复调用把 sink 又装回去。
- 洪流的代价：INFO 档视频通话中实测约 190 行/秒（主机 .61），格式化与 hilog 写入落在音频/编码线程上，
  吃的是抖动和尾延迟；同时把 hilog 缓冲区冲没，其它取证日志（含字幕帧对表行）被滚掉。
  等 .so 修好范围校验后再回到按档位传值。

手工验收点：

1. 默认包视频通话 60 秒，10 秒窗口内 `hilog -x | grep -c libjingle` 应为 0（sink 未装）。
2. 同一台设备开 `verboseNativeLog: true` 重装后，同窗口应回到百行级，证明开关双向有效。
3. 两档下接听、挂断、保持切换与字幕帧（`rtc_subtitle`）行为一致，日志档位只影响 native 内部日志量。

## 3A 档位（AEC/NS/HPF/AGC）

- 包内不判机型：`RtcHostCallControllerOptions.audioProcessing: RtcAudioProcessingPolicy` 逐档注入，
  留空即既有默认（AEC 开、NS 开、HPF 开、AGC 关、AECM 关）。
- **两层必须同写**：APM 工厂（`AudioProcessingFactory.create`）和 `createAudioSource` 的约束层。
  引擎会用约束层的值回写 APM（`webrtc_voice_engine.cc:615`），只改一层等于没改。
- 生效时机：APM 实例随 `PeerConnectionFactory` 只创建一次，所以只能在 controller 构造前注入；
  工厂已存在时只记 `rtc_audio_processing late_configure ignored reason=pcf_exists`，不假装生效。
- 日志：`rtc_audio_processing aec=.. aec_mobile=.. ns=.. hpf=.. agc=.. external_delay=false`（APM 层）
  与 `rtc_audio_source_constraints aec=.. ns=.. agc=..`（约束层），宿主侧另有
  `rtc_audio_processing_policy api=.. decision=..`。
- 宿主当前口径：api12（RK3568 32 位那批）整组关掉 AEC/NS/HPF，理由是采集回调线程 `OS_AudioReadCB`
  在通话中平均吃 13–14% 单核，是应用内最贵的线程；代价是免提时回声与底噪直接进上行。
  api23 保持默认，本机不做改动。
- NS 等级在 .so 里默认 `kVeryHigh`，是最贵的一档；若关掉整组后听感不可接受，先只回开 AEC
  或把 NS 降档，别整组回开——那会退回本轮想验证的开销。

手工验收点：

1. api12 设备起呼后日志出现 `rtc_audio_processing aec=false ns=false hpf=false`，
   且约束层同样为 false，两层不一致就是没接对。
2. 关掉后 `OS_AudioReadCB`、`OS_AudioWriteCB` 的线程均值与整机 busy 相对 3A 开的同长度通话下降；
   没有下降说明 3A 不是主要开销，回到码率/渲染路径继续找，别继续调 3A。
3. 回声主观核对：床旁外放、对方讲话时本机不采到自家扬声器回声；主机会话用免提时同样检查一次。
4. 挂断、保持、切麦、铃声路径与 3A 档位无关，行为保持一致。

## native ohos_webrtc 后续

- ArkTS 层如果没有显式 ADM release/dispose API，单纯清空对象不能保证 native `AudioCapturer` 同步释放。
- native `ohos_webrtc` 应补充幂等的 `AudioDeviceModule.release()` 或 `dispose()`，并按 OpenHarmony audio 状态机停止和释放 `AudioCapturer`、`AudioRenderer`。
- native 释放时需要关闭线程并等待退出，再清理 native handle。
- 创建或启动采集失败时，可从 `SOURCE_TYPE_VOICE_COMMUNICATION` 降级到 `SOURCE_TYPE_MIC`。
- 零采样诊断应记录 source、sample rate、channel count、stream id、nonZeroBytes 和流状态。

## API 参考取舍

- 归档中的 `libwebrtc.md` 是 OpenHarmony WebRTC API 大表，内容体量大且和当前维护规则重复，不作为本项目长期文档保留。
- 本项目只沉淀实际使用规则：`RTCPeerConnection` 生命周期、SDP/ICE 透传、stats 采样、track 绑定和错误状态处理。
- API 字段含义以 SDK 原始文档为准；本项目文档只记录对主机/床旁通话链路有约束的规则。

## 排查顺序

1. 确认 call-gateway 业务状态：invite、answer、candidate、hangup 是否按同一 `uid` 串起来。
2. 确认 publish 上行只创建一次，subscribe 下行按目标通话创建。
3. 确认远端 track 身份与当前目标通话匹配。
4. 确认音频输出路径和系统通话音量。
5. 确认厂家 SDK 没有在 WebRTC 模式下启用 SIP 铃声、DMsg 或错误手柄路径。

## 验证清单

- 主机屏幕接听默认免提和较高通话音量。
- 主机手柄接听默认听筒和较低通话音量。
- 屏幕接听后再抬起手柄，能切换到听筒路径。
- 床旁 WebRTC 呼入/外呼都能采集本地音频并播放远端音频。
- 协议热切换后无重复 websocket、重复 PeerConnection 或重复铃声。
