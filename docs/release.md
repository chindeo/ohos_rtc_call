# ohos-rtc-call Release Notes

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

### 床旁项目专用开发提示词

你现在接手床旁 OpenHarmony / OHOS API 12 项目，需要复用 `@chindeo/ohos-rtc-call` 公共模块，并保持与主机项目已经验证通过的行为一致。当前主机验证通过的预发布版本为 `0.1.4-rc2`，待审核通过后再替换为线上正式包。

请按以下规则检查和实现床旁项目：

1. 公共包版本策略

- 优先使用审核通过后的 `@chindeo/ohos-rtc-call` 线上包。
- 临时测试时可以使用 `0.1.4-rc2` 预发布 HAR，但不要长期依赖本地 HAR。
- 不要在床旁项目重复实现公共模块已经提供的通话、音频、导航栏、设备能力逻辑。

2. 系统导航栏规则

- 显示系统导航栏只用于远程调试。
- 导航栏显示状态只允许当前应用进程内生效。
- 应用退出或重启后必须默认隐藏系统导航栏。
- 如果床旁也有管理员设置入口，应调用 `RtcSystemBarController.setNavigationBarVisible(...)` 和 `applyNavigationBarPreference(...)`。
- 不要在床旁项目里持久化“显示导航栏”状态。

3. 启动加载页规则

- 启动页应显示 IP、MAC、版本等基础信息。
- 长按进入管理员设置时，启动页保持显示，不允许倒计时期间自动跳主页面。
- 从管理员设置返回启动页后，必须自动恢复启动流程，不能依赖用户手动点击一次。
- 如果已有有效 MAC，可以直接继续加载配置和认证。
- 如果没有有效 MAC，应立即触发一次 MAC 获取，并保留定时重试。
- 避免 `onPageShow`、点击、定时器等多入口并发进入主页面。

4. WebRTC 通话界面保护

- WebRTC 通话中，后台注册刷新、页面恢复、配置轮询不能覆盖或关闭通话界面。
- 使用 `RtcCallSessionGuard.isWebRtcCallInProgress(session)` 判断当前是否有可见或进行中的 WebRTC 通话。
- 通话中应跳过会重置 WebRTC UI、重新 prepare WebRTC、或触发主页面覆盖的后台流程。

5. 接听音频策略

- 屏幕按钮接听：默认免提，通话音量 90%。
- 话筒/手柄事件接听：默认非免提，通话音量 40%。
- 如果先屏幕接听，后续拿起话筒，需要自动切换为非免提和 40% 音量。
- 床旁如果有硬件接听事件，也必须区分 `screen` 和 `handset` 来源。
- 使用 `RtcCallControlCommandCodec` 传递控制命令来源。
- 使用 `RtcCallAnswerAudioPolicy` 获取接听后的音频路由和音量策略。

6. DNK 电源和息屏兼容

- `DeviceSdk.getInstance().getPowerApi().isActive()` 是 `Promise<boolean>`，必须 `await` 后判断。
- 不能写成 `if (!isActive())`，否则 Promise 对象永远为真，唤醒逻辑不会触发。
- DNK SDK 文档没有开放设置背光关闭时间的专用接口。
- 可以尝试通过 `settings.display.SCREEN_OFF_TIMEOUT` 设置屏幕休眠时间，但需要 `ohos.permission.MANAGE_SECURE_SETTINGS` 和系统签名 / `system_core` 权限。
- 权限不足时只记录日志，不要影响床旁应用启动和通话。
- 主机当前验证目标值为 10 分钟。

7. WebRTC URL 补全

- WebRTC 模式下，`ws://host:port` 或 `wss://host:port` 如果没有 `/websocket` 路径，需要自动补全。
- 已经是 `/websocket` 的地址不要重复补全。
- SIP/WebRTC 模式仍按服务地址区分：`ws://` / `wss://` 使用 WebRTC，普通 `ip:port` 使用 SIP。

8. 设备厂家隔离

- 床旁项目必须通过设备适配层处理厂家能力。
- 非 DNK 设备不要初始化 `@company/device_sdk`。
- 非 DNK 设备不要触发 DNK SIP、DNK 铃声、DNK 按键事件。
- Aurine、Shimeta、DNK 的 MAC、电源、按键、LED、话筒等能力应通过 adapter / capability manager 走。

### 床旁验收标准

- 管理员设置返回启动页后无需点击，自动进入主流程。
- WebRTC 通话中主页面不会覆盖通话界面。
- 屏幕接听和话筒接听的音频路由、通话音量符合规则。
- 应用重启后系统导航栏默认隐藏。
- DNK 设备息屏后能按轮询唤醒，日志能看到 `isActive` / `wakeup` 或屏幕超时设置结果。
- WebRTC 地址自动补全 `/websocket`。
- 非 DNK 设备不初始化 DNK SDK。
