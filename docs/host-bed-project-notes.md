# 主机和床旁项目接入说明

## 接入边界

- 主机项目使用 `nurse` 模块，床旁项目使用 `entry` 和业务公共模块。
- 业务项目只负责启动入口、权限、业务接口、MQTT、首页入口、硬件事件来源和页面挂载。
- 通话关系、WebRTC/SIP 协议切换、媒体资源、铃声、音量、状态提示和通话 UI 投影由本项目维护。
- 主机/床旁不再保留独立 `AGENTS.md`；协作规则统一看本项目 `AGENTS.md`。

## 构建和安装

- 需要验证业务项目时，使用业务项目自己的 `tools/build-*-app.ps1` 和 `tools/install-*-app.ps1`。
- 不直接猜测 DevEco、Hvigor、OpenHarmony SDK 或 hdc 的本机安装路径。
- 文档整理、规则调整、README 更新等文档-only 变更不需要跑业务项目构建。
- 运行构建或安装前先确认用户明确要求；若用户只提供日志，则只分析日志并给出修复方案。

## 依赖和 HAR

- 本项目生成的 `ohos-rtc-call-*.har` 是联调产物。业务仓只跟踪**一个已验收**的 HAR 快照（`libs/ohos-rtc-call-<日期-时刻>.har`），换 pin 时在同一笔提交里删掉旧快照，不在 `libs/` 里堆历史代次。
- 过期快照在删除前先进 `5.0.1-SHIMeta/artifacts/har-history/har/` 并在 `MANIFEST-latest.txt` 登记字节数、原生 build-id 与 `packageVersion`；清单与文件的 md5 必须一致。
- 业务项目提交中除该快照外只允许提交依赖声明、lock 文件或接入代码。
- 业务项目中不保存本机绝对路径、临时 HAR 文件名、设备地址或个人环境配置。

## 音视频参数（call_setting）接入

- 解析、匹配、本机覆盖存储与 3 分钟自动重拉全部在本项目 `src/main/ets/callsetting/`；两个业务项目各留一层薄门面 `utils/rtc/RtcCallSettingStore.ets`，只负责注入取数实现（`RequestAxios` + `resourceManager`）、设备身份和 AppStorage 镜像。业务侧不再各自复制一份解析。
- 音视频设置页的界面在本项目 `src/main/ets/ui/RtcCallSettingPanel.ets` 与 `RtcCallSettingPage.ets`；业务项目只提供数据快照和标题栏颜色。页面只读：未实现的控件灰显并给出原因，不接受点击后假装生效，也不提供保存。
- `audio.deviceVolume` 是百分比（`-1..100`），换算成设备的 `VOICE_CALL` 档位后**常驻生效**：SDK 23 的 `AudioVolumeGroupManager` 只有 getter，唯一可写的是已废弃的 `AudioManager.setVolume`，它要求 `ohos.permission.ACCESS_NOTIFICATION_POLICY`（availableLevel 是 normal，normal APL 装上即授予，不需要 ACL）。床旁 2026-10-13 实测 `requested=14 before=7 after=14 applied=true`。每次写入都紧跟一次回读并一起打日志——"没抛异常"不等于"档位真的变了"。挂断不还原：床旁是公共设备，没有属于某个用户的通话音量需要保护。
- `streamVolume`（webrtc 播放音量）与 `startKbps` 本端没有对应接口，只展示不生效。播放本身通过默认 `rendererUsage = STREAM_USAGE_VOICE_COMMUNICATION` 落在 `VOICE_CALL` 流上，已经被 deviceVolume 控制；`AudioSource.setVolume` 只能作用于 `createAudioSource()` 造出的本地麦，`AudioDeviceModule` 只有 `setSpeakerMute/setMicrophoneMute`，远端轨只有布尔 `enabled`。不要把两个值相乘去"近似"它——那会让档位不再等于服务器值。
- 音量没有本机覆盖通道（`applyAudioOverride` 已删），本机覆盖只剩分辨率一项，"清除缓存"一并清掉。参数变化通过 `setVideoSource` / `setScreenAnswerVolumePercent` 立即作用，不重新注册；只有 `RtcCallControllerKey` 变化才重建 controller。

## 主机差异

- 主机支持多人通话界面、保持/恢复、手柄接听/挂断和主机音频路由策略。
- 主机点击保持/恢复可以本地乐观更新按钮状态，但最终应由服务端 `c__broadcast` 保持通知校准。
- 主机屏幕按钮接听、手柄接听、后续切换听筒/免提应走公共音频路由入口，不在页面内直接调厂家 SDK。

## 床旁差异

- 床旁使用单床旁通话体验，能展示远端保持状态，但不显示主动保持/恢复按钮。
- 床旁首页按钮、床旁硬件按键和业务呼叫入口保留在业务项目，发起通话时调用公共 controller。
- 床旁特有的视频 surface、本地摄像头、麦克风/扬声器切换通过公共配置和回调接入。
- 独立 `com.chindeo.call` 通话应用是床旁历史方案；若未重新立项，不再复制 native WebRTC host 或维护第二套通话链路。

## 两端已确认的语义差异（不要为了统一而抹平）

- MAC 归一化：床旁注入 `normalizeMac`，主机只 `trim`。主机历史上就用原样 MAC 匹配上了服务器 bean，改成统一归一化会改变匹配结果。
- 首 bean 回退：主机与床旁都允许在没有任何 bean 匹配时取第一个 bean（`matchedBy=firstBean`），与安卓 `parseDefault` 一致。
- 音量落点：床旁在 VOIP 场景下铃声被框架改路由到 `VOICE_CALL`，所以应答音量百分比同时影响响铃响度；主机走手柄/免提路由，不套用同一条推断。
- 视频采集：主机用厂家 UVC 外部帧输入，床旁用 CameraKit；服务器下发的分辨率只在 API23 + 金海创床旁上直接驱动采集参数。

## 验收重点

- 主机拨床旁只显示一个床旁卡片，显示对端名称。
- 多通话挂断一路只关闭目标 `uid`，最后一路结束才关闭总 UI 和释放 `publish`。
- `c__hangup.data.isHangUp === false` 保留共享 `publish` 和总页面；`true` 或缺失按目标结束处理。
- 主机保持床旁后，床旁收到服务端保持通知并进入保持画面；恢复后回到通话画面。
- SIP/WebRTC 热切换后没有重复注册、重复响铃或双 PeerConnection。
