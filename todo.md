# ohos-rtc-call 下沉实施 TODO

## 目标

将床旁和主机重复且容易产生行为差异的 RTC 公共逻辑逐步下沉到 `@chindeo/ohos-rtc-call`，页面侧只保留业务数据、导航、UI 展示和项目专属接口。

## 阶段 0：文档和版本边界

状态：已完成

任务：

- [x] 清理 `docs/release.md` 中“床旁项目专用开发提示词”。
- [x] `release.md` 只保留各版本开发内容简介和验证结论。
- [x] 在 `CHANGELOG.md` 记录新增公共能力摘要。
- [x] 明确下一批能力建议版本号，例如 `0.1.5-rc1`。

验收：

- `docs/release.md` 不再包含床旁项目交接提示词。
- 版本记录能看出每个版本新增了哪些公共能力。

风险：

- 只整理文档，不改变运行行为。

## 阶段 1：WebRTC 信令状态机

状态：已完成

任务：

- [x] 新增 WebRTC 信令状态机模块。
- [x] 下沉 `handleSdp`。
- [x] 下沉 `handleCandidate`。
- [x] 下沉 publish / subscribe PeerConnection 管理入口。
- [x] 下沉 offer / answer 路由字段生成。
- [x] 下沉 stale session 过滤。
- [x] 下沉 ICE 统计和日志入口。
- [x] 下沉 `waitForLocalAnswerSdp`。
- [x] 补充 WebRTC 信令状态机核心单元测试。
- [x] 保持 `RtcWebRtcSignalSession` 只负责 WebSocket 连接、注册、消息拆包和原始信令收发。
- [x] 通过接口注入 PeerConnection 操作，避免状态机直接绑定床旁或主机页面。

验收：

- 床旁和主机可以共用同一套 SDP / Candidate 处理流程。
- stale session 信令不会污染当前通话。
- offer / answer 发送字段由公共模块统一生成。
- ICE 日志输出入口一致。

风险：

- 当前公共库没有业务项目里的 `handleSdp` / `handleCandidate` 原实现，落地时需要参考床旁和主机现有代码，避免改变已验证行为。

## 阶段 2：WebRTC 媒体资源管理

状态：已完成

任务：

- [x] 在现有 `RtcAudioController` 基础上扩展，不新增平行音频实现。
- [x] 统一 `PeerConnectionFactory` 创建和释放。
- [x] 统一 `AudioDeviceModule` 创建和释放。
- [x] 统一本地音频 track 创建、禁音和释放。
- [x] 补齐本地视频 track 创建和释放。
- [x] 补齐 renderer 绑定和解绑。
- [x] 下沉 `cleanupRtcCallResources`。
- [x] 下沉 AEC dump 开关和清理策略。
- [x] 下沉 PCM 采集统计日志回调。
- [x] 补充媒体资源管理轻量单元测试。

验收：

- 页面不再手写 ADM / PCF / track 的重复生命周期代码。
- 挂断、异常退出、页面销毁时资源释放路径一致。
- AEC dump 和 PCM 统计可按诊断配置开关控制。

风险：

- 媒体资源释放顺序会影响通话稳定性，需要先做小范围替换验证。

## 阶段 3：通话会话控制

状态：已完成

任务：

- [x] 在当前 `RtcCallService` 接口基础上提供默认控制器实现。
- [x] 下沉发起呼叫流程。
- [x] 下沉接听流程。
- [x] 下沉挂断流程。
- [x] 下沉自动接听流程。
- [x] 下沉通话保持 / 恢复流程。
- [x] 统一通话中状态同步到 `RtcCallSession`。
- [x] 统一 `RtcCallControlCommand` 解析和分发。
- [x] 补充通话会话控制单元测试。

验收：

- 页面通过公共控制器完成发起、接听、挂断和保持恢复。
- `RtcCallSession` 状态变化一致，可被 `RtcCallSessionGuard` 正确识别。
- 屏幕按钮和硬件事件都走同一套控制命令。

验证：

- [x] `git diff --check` 通过。
- [x] 临时克隆 `bis.git` 的 `5.0.1-SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-call-app.ps1 -BuildMode debug` 通过。
- [x] 临时克隆 `bis.git` 的 `v1.0_nurse_SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-nurse-app.ps1 -BuildMode debug` 通过。
- [ ] 手工安装到设备验证。
- [ ] 发布到线上包源。

风险：

- 通话控制牵涉 UI 跳转和业务状态，业务侧仍需保留导航和项目数据处理。

## 阶段 4：音频策略

状态：已完成

任务：

- [x] 保留并扩展 `RtcCallAnswerAudioPolicy`。
- [x] 增加 `deviceRole` 策略参数：
  - `bedside`
  - `nurseHost`
  - `doorHost`
- [x] 下沉接听后音量提升。
- [x] 下沉通话结束后音量恢复。
- [x] 下沉扬声器 / 听筒 / 手柄策略。
- [x] 下沉禁音状态同步。
- [x] 保持屏幕接听和手柄接听差异：
  - 屏幕接听默认免提，通话音量 90%。
  - 手柄接听默认非免提，通话音量 40%。
- [x] 新增 `RtcCallAudioPolicyController`，业务侧可注入音频 driver 或使用默认系统音频 / 设备能力实现。
- [x] 补充音频策略单元测试。

验收：

- 主机和床旁只通过 `deviceRole` 或策略参数表达差异。
- 先屏幕接听后拿起手柄时，可自动切到非免提和 40% 音量。
- 通话结束后能恢复接听前音量。

风险：

- 不同设备厂家的音频路由能力不一致，需要保留失败日志但不阻断通话。

## 阶段 5：Dnake 硬件事件通话适配

状态：已完成

任务：

- [x] 新增 `RtcHardwareCallController`。
- [x] 基于 `RtcDeviceCapabilityManager` 订阅和取消订阅按键事件。
- [x] 下沉呼叫键触发处理。
- [x] 下沉手柄拿起 / 放下触发处理。
- [x] 支持床旁自动接听时切手柄。
- [x] 支持主机屏幕接听不切手柄。
- [x] 页面只传入回调，例如 `onAnswer`、`onHangup`、`onCallKey`。
- [x] 支持业务侧注入硬件事件 parser，兼容厂家 payload 差异。
- [x] 补充硬件事件控制单元测试。

验收：

- 非 DNK 设备不会初始化 DNK SDK。
- DNK 按键和手柄事件通过公共控制器转成统一通话命令。
- 取消订阅后不再残留硬件事件回调。

风险：

- 硬件事件原始 payload 可能存在厂家差异，控制器需要保留可配置解析器。

## 阶段 6：启动页管理员入口辅助

状态：已完成

任务：

- [x] 新增 `RtcAdminEntryController`。
- [x] 封装 touch down / up / cancel。
- [x] 封装长按完成回调。
- [x] 封装 pending navigation 状态。
- [x] 封装 pause / resume startup。
- [x] 修复启动页无法长按进入管理员设置界面的集成路径。
- [x] 启动页状态检查完成后，等待 2 秒再进入主界面。
- [x] 业务侧继续传入具体 `SettingHostAbility` 名称、主页 URL 和启动数据加载函数。
- [x] 补充启动页管理员入口控制单元测试。

验收：

- 启动页长按可进入管理员设置界面。
- 长按倒计时期间不会自动跳主界面。
- 从管理员设置返回启动页后可恢复启动流程。
- 启动页状态检查完成后延迟 2 秒进入主界面。
- 避免 `onPageShow`、点击、定时器等多入口并发进入主界面。

风险：

- 公共模块不能知道具体设置页和主页，需要业务侧按接口传入。

## 阶段 7：API 配置和运行时配置加载

状态：已完成

任务：

- [x] 在已有 `RtcApiConfigStore` 上补齐运行时配置读取辅助。
- [x] 在已有 `RtcRuntimeConfigCoordinator` 上补齐 RTC server host 选择流程。
- [x] 统一 WebRTC / SIP 协议判断。
- [x] 统一 runtime config refresh 后的切换计划。
- [x] 统一 `micSwitching` 应用流程。
- [x] 新增 `RtcRuntimeConfigController`，通过业务 loader 加载运行时配置并计算 changedKeys。
- [x] 补充运行时配置控制单元测试。

验收：

- `config.json` 地址解析、RTC server host 选择和协议判断使用同一套公共逻辑。
- runtime config refresh 时只在需要时重新 prepare WebRTC / SIP。
- `micSwitching` 初始应用和变更应用路径清晰。

风险：

- 该阶段已有部分基础能力，落地时应优先补缺口，避免重写现有协调器。

## 整体验证和发布准备

状态：已完成

任务：

- [x] `git diff --check` 通过。
- [x] `tools/publish-ohos-rtc-call.ps1` 发布包预检通过，生成 `dist/ohos-rtc-call-0.1.5-rc1.har`。
- [x] 临时克隆 `bis.git` 的 `5.0.1-SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-call-app.ps1 -BuildMode debug` 通过。
- [x] 临时克隆 `bis.git` 的 `v1.0_nurse_SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-nurse-app.ps1 -BuildMode debug` 通过。
- [x] 手工安装测试和线上发布步骤整理到 `docs/manual-test-and-publish.md`。
- [ ] 手工安装到设备验证。
- [ ] 设备验收通过后执行线上发布。

## 不建议下沉

- 床旁主页菜单、患者信息、MQTT 业务刷新。
- 主机科室 / 病区 UI。
- 具体 API service 的业务接口。
- `SettingHostAbility` 本身。
- 启动页完整业务流程，例如获取床位配置、获取患者详情、跳转哪个主页。
