# ohos-rtc-call Release Notes

## 0.1.5-rc1

计划下沉床旁和主机可复用的通话公共逻辑，优先从 WebRTC 信令状态机开始，后续逐步覆盖媒体资源管理、通话会话控制、音频策略、硬件事件适配、启动页管理员入口和运行时配置加载。

本版本计划包含以下开发方向：

- WebRTC 信令状态机：统一 SDP / Candidate 处理、PeerConnection 管理入口、offer / answer 路由字段、stale session 过滤、ICE 日志和本地 answer SDP 等待流程。已新增公共状态机和适配器接口，并补充单元测试覆盖核心路由、过滤、排队和 answer 生成逻辑，业务侧可逐步接入现有 PeerConnection 实例。
- WebRTC 媒体资源管理：统一 `PeerConnectionFactory`、`AudioDeviceModule`、本地音频 / 视频 track、renderer、AEC dump 和 PCM 采集统计。已扩展 `RtcAudioController` 提供本地媒体准备、远端 track 绑定、renderer 清理、AEC dump 开关、PCM 统计回调和统一 cleanup。
- 通话会话控制：统一发起、接听、挂断、自动接听、保持 / 恢复和 `RtcCallSession` 状态同步。已新增 `RtcDefaultCallService`，通过业务侧 handlers 注入实际 WebRTC/SIP 行为，公共层负责状态同步和 `RtcCallControlCommand` 分发。
- 音频策略：统一屏幕 / 手柄接听音频路由、音量提升 / 恢复、禁音和设备角色差异。已新增 `RtcCallAudioPolicyController`，支持 `bedside`、`nurseHost`、`doorHost` 策略参数，屏幕接听默认免提和 90% 音量，手柄接听默认非免提和 40% 音量，并支持通话结束恢复原音量。
- 硬件事件适配：通过设备能力层统一按键、呼叫键和手柄事件通话控制。已新增 `RtcHardwareCallController`，基于 `RtcDeviceCapabilityManager` 订阅 / 取消订阅硬件事件，业务侧可注入 payload parser，并通过 `RtcCallControlCommand` 统一分发接听、挂断和呼叫键事件。
- 启动页管理员入口：封装长按进入管理员设置、启动暂停 / 恢复和状态检查完成后延迟进入主界面的辅助控制。已新增 `RtcAdminEntryController`，长按期间暂停自动进入主页，状态检查完成后默认等待 2 秒再导航，避免多入口重复跳转。
- 运行时配置加载：补齐 RTC server host 选择、WebRTC / SIP 判断、refresh 切换计划和 `micSwitching` 应用流程。已新增 `RtcRuntimeConfigController`，业务侧只需注入 runtime config loader 和 WebRTC/SIP prepare handler。

### 当前验证结论

- `git diff --check` 通过。
- `tools/publish-ohos-rtc-call.ps1` 发布包预检通过，生成 `dist/ohos-rtc-call-0.1.5-rc1.har`；OHPM 提示 HAR 包含源码，符合当前源码 HAR 发布形态。
- 已临时克隆 `bis.git` 的 `5.0.1-SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-call-app.ps1 -BuildMode debug` 通过。
- 已临时克隆 `bis.git` 的 `v1.0_nurse_SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-nurse-app.ps1 -BuildMode debug` 通过。
- 手工安装测试和线上发布步骤已整理到 `docs/manual-test-and-publish.md`。

## 0.1.4-rc2

### 主机验证结论

主机项目已验证通过，待 `@chindeo/ohos-rtc-call` 新包审核通过后再切换线上包使用。

本版本包含以下已验证能力：

- WebRTC 通话界面保护：通话中避免后台注册刷新、页面恢复、配置轮询覆盖通话界面。
- 屏幕按钮/话筒接听音频策略：屏幕接听使用免提和 90% 通话音量，话筒接听使用非免提和 40% 通话音量。
- 系统导航栏临时调试状态：显示导航栏只在当前进程内生效，应用退出或重启后默认隐藏。
- 启动加载页恢复：从管理员设置返回启动加载页后自动恢复启动流程，不需要手动点击。
- WebRTC 地址兼容：`ws://host:port` / `wss://host:port` 自动补全 `/websocket`，已带 `/websocket` 时不重复补全。
- DNK 电源兼容：`isActive()` 按 `Promise<boolean>` 异步处理；启动保活时尝试设置 `settings.display.SCREEN_OFF_TIMEOUT` 为 10 分钟。

### DNK 系统权限说明

DNK 文档未开放直接设置背光关闭时间的 PowerApi。当前通过 OpenHarmony 系统设置项尝试设置屏幕休眠时间：

- 设置项：`settings.display.SCREEN_OFF_TIMEOUT`
- 权限：`ohos.permission.MANAGE_SECURE_SETTINGS`
- 签名要求：系统应用权限等级，DNK 文档要求将应用 `apl` 提升为 `system_core`

如果没有系统签名或权限不足，设置会失败并记录日志，但不会影响应用启动和通话。
