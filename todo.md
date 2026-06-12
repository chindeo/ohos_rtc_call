# ohos-rtc-call 下沉实施 TODO

## 目标

将床旁和主机重复且容易产生行为差异的 RTC 公共逻辑下沉到 `@chindeo/ohos-rtc-call`。公共模块统一持有信令、媒体资源、通话会话、多路状态和通用通话 UI；业务页面只保留业务配置、页面生命周期、导航、项目专属接口、业务日志 / 提示，以及本机和远端视频 Surface Builder。

其中主机业务工程 `v1.0_nurse_SHIMeta` 的 `RtcCallHost.ets` 最终只作为业务配置和页面容器，不再自管 WebSocket、SDP / Candidate、PeerConnection、音视频 track、多路会话状态或多人通话 UI。

## 完成状态口径

- “公共能力已实现”：公共模块中已有可复用类、状态机或基础控制器，并有对应单元测试。
- “业务接入已完成”：业务工程已删除同类自管逻辑，运行时只使用公共模块入口。
- 只有公共能力、业务接入和真机验收全部完成后，对应阶段才能标记为“已完成”。
- 临时业务工程中的验证性修改不作为公共模块下沉完成依据。

## 接入检查点口径

- 每个阶段推进时必须分别记录公共能力、业务接入和真机验收状态，不能用其中一项替代整体完成。
- 公共能力完成必须对应公共模块实现、公共导出和单元测试；如果只是业务工程临时验证，不计入公共能力完成。
- 业务接入完成必须确认旧业务自管逻辑已经移除或停止处理同一信令 / 媒体资源，避免新旧实现并行。
- 真机验收完成必须记录已跑的最小场景、设备角色和未覆盖风险；只完成构建或安装不能标记为真机验收通过。
- 同一问题反复修改时，进入下一次实现前必须记录上次偏差原因和本次防回归锚点。

## 阶段 0：文档和版本边界

状态：已完成

任务：

- [x] 清理 `docs/release.md` 中“床旁项目专用开发提示词”。
- [x] `release.md` 只保留各版本开发内容简介和验证结论。
- [x] 在 `CHANGELOG.md` 记录新增公共能力摘要。
- [x] 明确下一批能力建议版本号，例如 `0.1.4-rc3`。

验收：

- `docs/release.md` 不再包含床旁项目交接提示词。
- 版本记录能看出每个版本新增了哪些公共能力。

风险：

- 只整理文档，不改变运行行为。

## 阶段 0.5：启动数据缓存

状态：已完成

任务：

- [x] 新增 `RtcStartupDataCache`，支持业务启动数据按 key 持久化缓存。
- [x] 支持 loader 成功后写缓存，loader 失败后回退到最近一次可用缓存。
- [x] 支持业务侧自定义数据可用性判断、是否写缓存、序列化和反序列化。
- [x] 支持无缓存时使用业务传入的 fallback value。
- [x] 补充启动数据缓存单元测试。

验收：

- 后台业务接口短时不可用时，业务侧可以读取最近一次成功缓存继续启动。
- 缓存能力不绑定床旁或主机业务模型。
- 通话链路不依赖主页面业务接口缓存。

风险：

- 首次安装且从未成功拉取过床旁配置时，仍无法凭空恢复床位业务数据，需要至少一次成功缓存。

## 阶段 0.6：网络恢复提示和多床旁来电队列

状态：已完成

任务：

- [x] 新增 `RtcNetworkRequestRecoveryController`，统一 API 请求失败、缓存回退和成功恢复后的提示状态。
- [x] 默认网络异常提示文案为“网络异常，请检查网络”。
- [x] 新增 `RtcIncomingCallQueue`，按 callId / 床旁身份保留多个来电。
- [x] `RtcDefaultCallService` 接入来电队列，当前媒体通话中收到新来电时只入队，不覆盖当前会话。
- [x] 补充网络恢复提示和多来电队列单元测试。

验收：

- 床旁启动页可在业务接口异常且使用缓存启动时显示网络异常提示，接口恢复后成功请求可清除异常状态。
- 主机可基于队列快照显示多个床旁来电列表 / 弹窗。
- 接通一个床旁通话时，其他床旁来电仍保留在队列中，不被误挂断或隐藏。

风险：

- 队列只下沉状态管理，主机具体列表 / 弹窗 UI 仍由业务侧接入队列快照。

## 阶段 1：WebRTC 信令状态机

状态：进行中（公共能力已实现，业务主机未完成接入）

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
- [ ] 主机通过公共总入口接入 `RtcWebRtcSignalSession` 和 `RtcWebRtcSignalStateMachine`。
- [ ] 删除 `RtcCallHost.ets` 自管的 WebSocket、`handleSdp`、`handleCandidate` 和 Candidate 缓存。

验收：

- 床旁和主机可以共用同一套 SDP / Candidate 处理流程。
- stale session 信令不会污染当前通话。
- offer / answer 发送字段由公共模块统一生成。
- ICE 日志输出入口一致。
- `RtcCallHost.ets` 不再直接创建 WebSocket 或解析 SDP / Candidate。

风险：

- 公共状态机已具备基础处理能力，但业务主机仍保留完整原实现；接入时需要逐项对照已验证行为，避免遗漏路由字段和兼容逻辑。

## 阶段 2：WebRTC 媒体资源管理

状态：进行中（公共资源能力已实现，业务主机未完成接入）

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
- [ ] 新增 `RtcWebRtcMediaController`，统一 publish / subscribe PeerConnection 与 track 的会话绑定。
- [ ] 统一 `ontrack` 身份解析和媒体接通判定。
- [ ] 主机改由公共媒体控制器创建和释放 PeerConnection、track 与媒体资源。
- [ ] 删除 `RtcCallHost.ets` 自管的 `PeerConnectionFactory`、publish PC、subscribe PC 和音视频 track。

验收：

- 页面不再手写 ADM / PCF / track 的重复生命周期代码。
- 挂断、异常退出、页面销毁时资源释放路径一致。
- AEC dump 和 PCM 统计可按诊断配置开关控制。
- 普通视频设备的视频通话必须收到匹配的视频 track 后才算接通。
- 音频通话或手表设备收到匹配的音频 track 后即可算接通。

风险：

- 媒体资源释放顺序会影响通话稳定性，需要先做小范围替换验证。

## 阶段 3：通话会话控制

状态：进行中（公共基础控制已实现，业务主机未完成接入）

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
- [ ] 新增主机唯一业务入口 `RtcHostCallController`。
- [ ] 新增 `RtcHostMultiCallController`，统一 active、side list、pending、accepted 和 hold 状态。
- [ ] 所有接听、保持、恢复、单路挂断、全部挂断和选择操作都按 `uid / sessionKey` 路由。
- [ ] 缺少 `uid / sessionKey` 且无法唯一映射时阻断操作。
- [ ] 主机页面和硬件事件全部改走 `RtcHostCallController`。

验收：

- 页面通过公共控制器完成发起、接听、挂断和保持恢复。
- `RtcCallSession` 状态变化一致，可被 `RtcCallSessionGuard` 正确识别。
- 屏幕按钮和硬件事件都走同一套控制命令。
- 普通挂断只结束目标会话，话筒放下和挂断全部才结束全部会话。

验证：

- [x] `git diff --check` 通过。
- [x] 临时克隆 `bis.git` 的 `5.0.1-SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-call-app.ps1 -BuildMode debug` 通过。
- [x] 临时克隆 `bis.git` 的 `v1.0_nurse_SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-nurse-app.ps1 -BuildMode debug` 通过。
- [ ] 手工安装到设备验证。
- [ ] 发布到线上包源。

风险：

- 通话控制牵涉 UI 跳转和业务状态，业务侧仍需保留导航和项目数据处理。

## 阶段 4：音频策略

状态：进行中（公共能力已实现，业务主机仍有部分音频状态和资源逻辑待迁移）

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
- [ ] 主机通过 `RtcHostCallController` 间接使用公共音频资源和路由策略。
- [ ] 删除 `RtcCallHost.ets` 自管的通话音量恢复、扬声器路由和媒体资源状态。

验收：

- 主机和床旁只通过 `deviceRole` 或策略参数表达差异。
- 先屏幕接听后拿起手柄时，可自动切到非免提和 40% 音量。
- 通话结束后能恢复接听前音量。

风险：

- 不同设备厂家的音频路由能力不一致，需要保留失败日志但不阻断通话。

## 阶段 5：Dnake 硬件事件通话适配

状态：进行中（公共能力已实现，业务主机未完成统一入口接入）

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
- [ ] 主机硬件事件通过 `RtcHostCallController` 转换为按 `sessionKey` 路由的统一操作。
- [ ] 话筒放下统一调用 `hangupAll`，屏幕普通挂断只调用目标会话的 `hangup`。

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

状态：进行中（公共包预检完成，业务全链路接入和真机验收未完成）

任务：

- [x] `git diff --check` 通过。
- [x] `tools/publish-ohos-rtc-call.ps1` 发布包预检通过，生成 `dist/ohos-rtc-call-0.1.4-rc3.har`。
- [x] 临时克隆 `bis.git` 的 `5.0.1-SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-call-app.ps1 -BuildMode debug` 通过。
- [x] 临时克隆 `bis.git` 的 `v1.0_nurse_SHIMeta` 分支，替换为当前公共包本地 file 依赖后执行 `tools/build-nurse-app.ps1 -BuildMode debug` 通过。
- [x] 手工安装测试和线上发布步骤整理到 `docs/manual-test-and-publish.md`。
- [ ] 手工安装到设备验证。
- [ ] 设备验收通过后执行线上发布。

## 阶段 8：接口异常降级启动和主机多人通话

状态：进行中

任务：

- [x] 公共包新增 `RtcStartupFallbackController`，统一判断启动数据来自网络、缓存、fallback 时是否允许进入主页。
- [x] 公共包新增 `RtcCallSessionStore`，按 uid / peer 管理多路通话会话和保持状态。
- [x] `RtcIncomingCallQueue` 支持 uid、sessionKey、peerNumber、保持状态和优先级排序。
- [x] `RtcDefaultCallService` 支持按 uid 接听、挂断、保持 / 恢复，并保留其它来电。
- [x] 补充启动降级、多会话、多来电队列和保持恢复单元测试。
- [x] 生成 `0.1.4-rc3` HAR 并通过 `ohpm prepublish` 预检。
- [x] 床旁临时项目接入启动降级：接口异常但配置缓存可用时进入主页，详情允许缓存 / 空对象降级。
- [x] 床旁临时项目主页增加“网络异常，请检查网络”提示，请求成功后清除提示并刷新缓存。
- [x] 主机临时项目补多路通话列表、活动会话切换、单路挂断不清空其它会话，仅作为临时验证，不计入公共化完成项。
- [x] 主机临时项目增加保持 / 恢复按钮，复用现有保持状态和本地麦克风上行控制，仅作为临时验证，不计入公共化完成项。
- [x] 床旁临时项目构建通过。
- [x] 主机临时项目构建通过。
- [x] 安装床旁 HAP 到床旁测试设备并确认进程存活。
- [x] 安装主机 HAP 到主机测试设备并确认进程存活。
- [ ] 真机验证床旁启动降级和通话。
- [ ] 真机验证主机多床旁来电、保持 / 恢复和单路挂断。
- [ ] 设备验收通过后再生成最终 `0.1.4-rc3` 预发布包。

验收：

- 接口不可访问或断网时，床旁不再卡启动页；有缓存配置时可以进入主页面并保留通话能力。
- 主页显示网络异常提示；接口恢复后定时刷新成功并清除提示。
- 主机同时收到多个床旁呼叫时，能看到多个床旁条目，接听 / 切换 / 挂断其中一路不影响其它路。
- 主机通话中可保持 / 恢复当前活动通话。

风险：

- 首次安装且从未成功缓存床旁配置时，仍无法保证通话注册所需账号信息完整。
- OHOS 主机保持发送协议当前按现有广播结构适配，需真机联调确认服务端是否接受。

## 阶段 9：主机 WebRTC 全链路和多人 UI 公共化接入

状态：进行中（公共链路和多人 UI 已接入，音频来电崩溃已修复；会话状态闭环、操作路由和双路真机验收待完成）

目标：

- 公共模块提供主机通话唯一总入口，业务工程不再直接编排多个底层 controller。
- `v1.0_nurse_SHIMeta` 的 `RtcCallHost.ets` 只保留业务配置、页面生命周期、业务日志 / 提示和视频 Surface Builder。
- 主机 WebRTC 链路、多会话状态和多人通话 UI 的唯一真值全部位于公共模块。

### 单路兼容与多人边界

- 单路通话必须保持改造前已经验证通过的按钮和信令流程，不能为了多人抽象改变单路接听、挂断的触发条件和调用路径。
- 单路来电在 publish offer 处理完成、本地 answer SDP 已发送后显示并启用接听按钮；新 call-gateway SDK 点击接听必须按当前会话 `uid` 调用接听接口，旧 WebSocket 兼容路径才继续验证 `applyType=2`。
- 单路挂断在新 call-gateway SDK 中必须按当前会话 `uid` 调用挂断接口；旧 WebSocket 兼容路径才继续验证 `applyType=3` 和单路 `isAll` 语义。
- 单路界面沿用原单人通话的布局、配色、按钮尺寸、间距和交互反馈，不套用多人列表样式。
- 只有存在第二路可见会话时才启用多人调度能力，包括右侧列表、展示焦点切换、按 uid 的操作隔离和挂断全部按钮。
- 从多人退回单路后，剩余会话恢复单路显示和操作方式，但不得重建或改变该会话原有的来电、接听、通话或保持状态。
- 多人逻辑以 call-gateway 为基准：业务 `uid` / `signalUID` 是操作和 UI 主键，`rtcUID + channelType` 定位 RTC 通道，号码只用于显示、联系人索引和旧单通话兼容。
- 多人模式的接听、保持、恢复和单路挂断必须携带目标 `uid/sessionKey`；缺少 uid 时阻断操作，不能退化成当前 active、号码推导或挂断全部。
- 普通挂断只结束指定 uid 对应的信令、subscribe peer、媒体状态和 UI；独立“挂断全部”按钮及话筒放下才结束全部会话。
- 点击右侧已接听设备只交换主显示区和侧边列表位置，不改变通话状态；待接听和保持中的设备不因切换动作自动接听或恢复。
- 主显示会话结束后优先选择另一条已接听会话；没有已接听会话时显示一条待接听会话。

公共模块任务：

- [x] 新增 `RtcHostCallController`，作为业务工程唯一调用入口。
- [x] 新增 `RtcWebRtcCallController`，统一 WebSocket 注册、信令分发、SDP、Candidate 和 publish / subscribe 信令编排。
- [x] 新增 `RtcWebRtcMediaController`，统一 PeerConnectionFactory、publish PC、subscribe PC、本地 / 远端 track 和 renderer 生命周期。
- [x] 新增 `RtcHostMultiCallController`，统一 active、side list、pending、accepted、hold 和媒体接通状态。
- [x] 将 `RtcWebRtcSignalStateMachine`、`RtcPeerSessionRegistry`、`RtcIncomingCallQueue` 和 `RtcDefaultCallService` 收敛到总入口内部。
- [x] 新增 `RtcHostCallUiModel`，统一 `localCard`、`activeCall`、`sideCalls`、`actions`、`showHangupAll`、`volume` 和 `videoState`。
- [x] 新增公共 ArkUI 组件 `RtcHostMultiCallLayout`。
- [x] `RtcHostMultiCallLayout` 负责左侧主通话区、右侧本机信息 / 视频区、远端列表、状态颜色和通话操作。
- [x] 本机和远端视频 Surface 通过 `@BuilderParam` 注入，公共 UI 不直接绑定业务 renderer 生命周期。
- [x] 在 `Index.ets` 导出总入口、媒体控制器、多会话控制器、UI model 和公共组件。

统一会话模型：

- [ ] 每一路会话统一绑定 `sessionKey`、`uid`、`peerNumber`、`callId` 和 `subscribeRtcUid`。
- [ ] `invite`、publish answer ready、subscribe、UI 条目和控制操作必须先解析为同一个规范 `sessionKey`，不能由独立 Map 使用未经归一化的字符串临时关联。
- [ ] 展示焦点和媒体活动状态分离；点击右侧条目只切换左右显示位置，不改变该会话的来电、接听、通话或保持状态。
- [ ] 每一路 subscribe PeerConnection、远端音频 track、远端视频 track、phase、hold 和 mediaConnected 都归属于同一会话。
- [x] 传给 OpenHarmony WebRTC native 的 Candidate 只包含有效字段；`sdpMLineIndex` 非数字时不得写入对象。
- [ ] publish connected 只表示本机上行已建立，不作为对端已接听依据。
- [ ] `ontrack` 必须通过 track id / stream id 唯一匹配目标会话后才更新接通状态。
- [ ] 普通视频设备的视频通话等待视频 track；音频通话或手表设备只等待音频 track。
- [ ] 无法唯一匹配会话时不更新状态，并输出可定位日志。

业务工程替换任务：

- [x] `RtcCallHost.ets` 改为创建和持有 `RtcHostCallController`。
- [x] 页面生命周期只调用公共 controller 的 `start` 和 `dispose`，业务配置通过构造参数注入。
- [x] 页面监听公共 `RtcHostCallUiModel` 并渲染 `RtcHostMultiCallLayout`。
- [x] 页面按钮和硬件事件只调用 `accept`、`hangup`、`hangupAll`、`hold`、`resume` 和 `select`。
- [x] 删除业务自管 WebSocket、SDP / Candidate、Candidate 缓存和信令路由。
- [x] 删除业务自管 publish PC、subscribe PC、PeerConnectionFactory 和音视频 track。
- [x] 删除业务自管 `sessionPeers`、`sessionStates`、`subscribeStates` 和 `activeSessionId`。
- [ ] 业务依赖版本改为 `0.1.4-rc3`；本地验证可临时使用相对 `file:` HAR，不提交本机绝对路径。

公共模块单元测试：

- [x] 双路来电状态相互隔离。
- [ ] 单路接听和挂断保持改造前调用路径，不经过多人 uid 歧义门控。
- [ ] 第二路加入后才切换为多人调度，退回单路后恢复单路展示和操作。
- [ ] 接听一路只建立对应一路 subscribe。
- [x] 普通挂断只结束目标会话。
- [x] active 会话挂断后切换到下一路可见会话。
- [x] 缺少 uid 且多路无法唯一映射时阻断操作。
- [x] 普通视频、音频通话和手表设备使用各自正确的媒体接通判定。
- [ ] publish answer ready 使用 callId、uid 或规范 sessionKey 回调时都能启用同一路接听按钮。
- [ ] 点击右侧条目只改变展示选中项，不修改两路原有 phase、hold 和 mediaConnected。
- [ ] 左侧和右侧普通挂断都只关闭对应信令会话、subscribe peer 和 UI 条目。

公共多人 UI 修正：

- [ ] 接听、挂断、保持、恢复、静音、免提和挂断全部使用公共模块图片资源，不使用字体字符模拟图标。
- [ ] 页面使用统一中性背景；待接听、通话中、保持中只通过受控状态色和选中边框区分，避免大面积多色背景拼接。
- [ ] 当前选中床旁在左侧显示，右侧列表移除该条目；切换后原左侧未结束会话回到右侧。
- [ ] 右侧条目挂断按钮阻止卡片切换事件，避免一次点击同时触发选择和挂断。

构建和真机验证：

- [x] 构建 `0.1.4-rc3.har`，不发布。
- [x] `v1.0_nurse_SHIMeta` 使用本地 rc3 HAR 构建通过。
- [x] 安装主机 HAP 到测试设备。
- [ ] 验证单路来电、接听、保持、恢复和单路挂断。
- [x] 验证音频来电处理 Candidate 时不发生 `Number::CheckCast` native 崩溃。
- [ ] 验证双路来电独立接听、活动通话切换、右侧列表和状态颜色。
- [ ] 验证普通挂断不影响其它通话，挂断全部和话筒放下结束全部通话。
- [ ] 验证视频设备、音频通话和手表设备的接通判定。
- [ ] 测试结束后清理测试进程，避免残留。

阶段完成判据：

- `RtcCallHost.ets` 不再直接引用 WebSocket 和 `@ohos/webrtc`。
- `RtcCallHost.ets` 不再保存 PeerConnection、track、Candidate 或多会话真值状态。
- 业务工程只依赖 `RtcHostCallController` 和 `RtcHostMultiCallLayout` 完成通话控制与渲染。
- 公共模块单元测试、rc3 HAR 构建、业务构建和真机验收全部通过。

风险：

- 业务主机当前包含大量已验证的兼容逻辑，迁移时需要逐项核对信令字段、track 身份解析和资源释放顺序。
- 迁移期间不能让旧实现和公共 controller 同时处理同一条信令，否则会产生双 PeerConnection 和双状态源。
- 阶段可以拆分检查点实施，但公共 UI 或多会话控制单独接入不能将本阶段标记为完成。

## 不建议下沉

- 床旁主页菜单、患者信息、MQTT 业务刷新。
- 主机科室 / 病区 UI。
- 具体 API service 的业务接口。
- `SettingHostAbility` 本身。
- 启动页完整业务流程，例如获取床位配置、获取患者详情、跳转哪个主页。
- 项目专属日志上报、业务 Toast 文案和业务导航。
