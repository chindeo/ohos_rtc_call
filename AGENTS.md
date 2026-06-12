# 仓库协作指南

## 基本规则

- 默认用中文回复。
- 先读相关文件，再做小而聚焦的修改。
- 保持现有风格，避免无关重构。
- 不确定就明说，不要把猜测写成事实。
- 改动后做最小必要验证，不默认全量测试。
- 提交代码前注意脱敏，避免提交密钥、密码、Token、内网地址、临时路径、设备地址和本地绝对路径等敏感信息。
- 非平凡改动需要说明变更内容、原因、验证方式和风险。
- 不默认 commit、push、发布或部署，除非用户明确要求。

## 需求和实现流程

- 需求调整或修改确认流程：先分析问题并给出方案，等待用户确认；确认后先更新并整理相关文档和手工验收点；最后再进入代码实现、验证、提交或发布流程。
- 需求锁定：开工前必须写清目标、非目标、成功标准、受影响入口，以及不能破坏的已验证行为；这些内容不清楚时先补齐，不直接进入实现。
- 涉及 WebRTC、多通话、启动流程时，必须先列出状态源、信令来源、UI 状态和本次最小验收场景；缺少业务规则、设备现象或日志时要明确说明缺口。
- 防反复修改：同一问题第二次修改前，必须先说明上一次为什么没解决，例如需求理解错误、状态源选错、测试缺失或边界遗漏；禁止只在同一位置反复试改。
- 修复同类问题时，必须回到数据流、状态机、信令字段或验收点重新定位，并明确本次防回归锚点：单元测试、手工验收点、日志检查或最小复现场景。
- 实现防偏离：先保留已验证单路流程，再扩展多人、多设备和异常路径；不能为了抽象改掉原有按钮条件、信令字段、挂断语义或 track 接通判定。
- 公共 controller 与旧业务实现不能同时处理同一条信令或同一份媒体资源，避免双 PeerConnection、双状态源和重复 UI 状态更新。

## call-gateway 对接基准

- 新的音视频 SDK 和验收口径以 `call-gateway/docs/integration/client_av_integration.md`、`docs/gateway/interface.md`、`docs/gateway/ctl.md` 为准。
- `uid` / `signalUID` 是业务会话主键，`rtcUID` 是 RTC 通道主键，`channelType` 只允许 `publish` 或 `subscribe`。客户端必须把这些字段当作不透明字符串透传和绑定。
- 号码、显示名、床号、科室号只能用于展示、联系人索引或旧单通话兼容兜底，不能作为新 SDK 的通话唯一键。
- SDP/ICE 收到什么 `uid`、`rtcUID`、`channelType`，后续 answer/candidate 就必须带回同一组字段；禁止从当前选中 UI、最新通话或号码重新推导。
- 业务接听只以 call-gateway 接听接口成功为准；`OnTrack`、ICE connected、PeerConnection connected、publish ready、remote description applied 都不能单独判定为已接听。
- 拨打阶段只建立 `publish` 上行通道；接听成功后才为目标会话建立或激活对应 `subscribe` 下行通道。
- 媒体接通以目标 `subscribe` 收到并匹配远端 track 为准：音频通话至少匹配远端音频；普通视频设备需匹配远端视频；手表等仅音频设备的视频通话可只匹配远端音频。
- 来电预接听阶段不能发送真实麦克风音频；接听成功且音频路由稳定后再解除上行静音。
- 多通话时，接听、保持 / 恢复、普通挂断、关闭和 UI 清理都必须按目标 `uid` 执行；缺少 `uid` 且无法确认单通话兼容路径时应阻断并记录原因。
- 单个 `subscribe` 异常时优先恢复目标下行通道，不能直接清理其它活跃通话或关闭共享 `publish`。

## 项目结构

- `src/main/ets/` 存放 ArkTS 源码，按 `audio`、`core`、`device`、`model`、`signaling`、`sip`、`ui`、`webrtc` 分域组织。
- `Index.ets` 是公共导出入口；新增对外 SDK、类型或控制器时必须确认是否需要从这里导出。
- `test/*.test.ets` 是 Hypium 单元测试。
- `example/` 存放最小接入示例；`docs/` 存放发布、验收和说明文档；`tools/` 存放打包发布脚本。

## 构建、测试和发布命令

- `ohpm install`：安装 OpenHarmony 包依赖。
- `.\tools\publish-ohos-rtc-call.ps1`：生成 HAR，并执行敏感内容扫描和 `ohpm prepublish`。
- `.\tools\publish-ohos-rtc-call.ps1 -SkipPrepublish`：只生成 HAR，不执行 OHPM 预发布检查。
- `.\tools\publish-ohos-rtc-call.ps1 -Publish`：设备验收通过后发布到 OHPM。
- `git diff --check`：提交前检查空白和补丁格式。
- 单元测试通过 OpenHarmony / DevEco 的 Hypium 流程执行；文档-only 修改不需要运行构建或发布脚本。

## 代码风格和测试

- `.ets` 文件沿用现有 ArkTS 风格：两空格缩进、优先单引号、不使用分号。
- 公共 RTC 类型、类和常量沿用 `Rtc...` 命名。
- 宿主 SDK、服务地址、凭据、bundle 名称和设备标识必须通过 adapter 或配置注入，不能硬编码进公共包。
- 测试使用 Hypium 的 `describe`、`it`、`expect`，文件命名采用 `FeatureName.test.ets`。
- 优先补小而确定的单元测试；跨设备通话、音频路由和 call-gateway 真机链路以手工验收清单为准。

## 提交和 PR

- 提交信息沿用 `feat:`、`fix:`、`chore:` 等简短前缀。
- PR 需要说明变更内容、验证结果、影响的宿主项目和潜在回归风险。
- 公共 API、导出入口或验收口径变化时，同步更新 `README.md`、`CHANGELOG.md`、`docs/` 或 `todo.md`。
