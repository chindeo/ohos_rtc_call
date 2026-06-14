# 手工安装测试和本地 HAR 分发清单

## 目标版本

- 公共包：`@chindeo/ohos-rtc-call@0.1.4-rc3`
- 床旁验证分支：`5.0.1-SHIMeta`
- 主机验证分支：`v1.0_nurse_SHIMeta`

## 需求验收前置检查

每次开发或修复前，先从下方长清单中抽出本次必须验证的最小集合，并记录在需求说明或提交说明里：

- 确认本次 HAR 版本、业务工程依赖来源，以及是否使用本地 `file:` HAR 临时验证。
- 确认目标设备角色：床旁、主机、门口机、手表等仅音频设备，避免用错误设备规则判断接通状态。
- 确认本次覆盖单路、双路或多路通话；多路改动必须先验证单路流程没有被破坏。
- 确认本次预期行为、非目标和不能破坏的已验证行为，例如按钮条件、信令字段、挂断语义和 track 接通判定。
- 确认验收顺序：先公共包单元或预检，再 Example 最小编译验证，最后按目标设备执行手工验收。

## 本地开发联调 HAR

个人本地开发联调时，使用带时间戳的 HAR 文件名，并复制到业务工程 `libs/` 目录，避免 OHPM 因相同路径和相同版本复用旧缓存：

```powershell
.\tools\publish-ohos-rtc-call.ps1 -DevTimestampName -SkipPrepublish -CopyToLibsDir `
  ..\5.0.1-SHIMeta\libs,..\v1.0_nurse_SHIMeta\libs
```

生成文件示例：

```text
dist\ohos-rtc-call-0.1.4-rc3-20260613-153000-123.har
..\5.0.1-SHIMeta\libs\ohos-rtc-call-0.1.4-rc3-20260613-153000-123.har
..\v1.0_nurse_SHIMeta\libs\ohos-rtc-call-0.1.4-rc3-20260613-153000-123.har
```

包内 `oh-package.json5` 的 `name` 和 `version` 不变，只有本地 HAR 文件名变化。业务工程验证时将
`@chindeo/ohos-rtc-call` 依赖指向本工程 `libs/` 下的时间戳 HAR：

```json5
"@chindeo/ohos-rtc-call": 'file:./libs/ohos-rtc-call-0.1.4-rc3-20260613-153000-123.har'
```

每次生成新的开发 HAR 后，同步更新业务工程依赖路径并执行 `ohpm install`。公共包后续不使用线上 OHPM 包，也不依赖 `ohos_rtc_call/dist` 的本机绝对路径。如果目标工程仍复用旧产物，再按现有方式定向删除
RTC junction 和单个 `.ohpm` 缓存目录。

## HAR 预检

在 `ohos_rtc_call` 项目根目录执行：

```powershell
.\tools\publish-ohos-rtc-call.ps1
```

团队共享联调包使用版本号加时间戳文件名，不发布到 OHPM。源码变化后应生成新的时间戳 HAR，并复制到床旁和主机工程 `libs/`。

同一版本只允许个人本地临时覆盖标准文件名 HAR，并且必须显式执行：

```powershell
.\tools\publish-ohos-rtc-call.ps1 -AllowLocalOverwrite
```

预检通过后会生成：

```text
dist\ohos-rtc-call-0.1.4-rc3.har
```

## Example 最小编译验证

以下命令仅作为人工集成验收参考；公共包修复流程不自动执行业务工程构建、编译或安装。

如果验证的是公共包改动，先将业务工程中唯一的 `@chindeo/ohos-rtc-call` 依赖替换为本工程 `libs/` 下的时间戳 HAR，例如：

```json5
"@chindeo/ohos-rtc-call": 'file:./libs/ohos-rtc-call-0.1.4-rc3-20260613-153000-123.har'
```

宿主工程仍需提供兼容的 `@ohos/webrtc` 依赖，因为公共包在 `oh-package.json5` 中将其声明为动态依赖。

将 `example/basic-call-setup.ets` 引入宿主工程可编译入口。示例中的信令地址、设备号码和 adapter 只用于编译验证，可替换为本地测试配置，也可保持不会实际联网的占位值。

执行宿主工程 debug 构建，目标是验证：

- 本次 HAR 能被外部工程消费。
- `Index.ets` 导出的 SDK 类型可被 ArkTS 正常导入。
- `example/basic-call-setup.ets` 的基础 WebRTC/SIP 路由、信令状态机和铃声策略示例可编译。
- `@ohos/webrtc` 动态依赖由宿主工程正确提供。

Example 最小编译验证只证明公共 SDK 可被消费和示例代码可编译；真机通话、音频路由、多路来电和 call-gateway 行为仍以后续设备安装和手工验收点为准。

手动刷新主机工程依赖后，至少确认安装模块包含以下公共包更新，避免出现 UI 已更新但核心控制器仍为旧版本的半新半旧状态：

```powershell
$RTC_MODULE = "$HARMONY_ROOT\v1.0_nurse_SHIMeta\nurse\oh_modules\@chindeo\ohos-rtc-call"
Select-String -Path "$RTC_MODULE\src\main\ets\core\RtcHostMultiCallController.ets" -Pattern "markConnectedByMediaState"
Select-String -Path "$RTC_MODULE\src\main\ets\core\RtcHostMultiCallController.ets" -Pattern "model.visible = mapped.length > 0"
Get-Content "$RTC_MODULE\rtc-package-fingerprint.json"
```

`rtc-package-fingerprint.json` 中的 `sourceSha256` 必须随本次 HAR 更新变化，不能继续停留在旧缓存值。

## 设备安装

以下命令仅作为人工设备验收参考；公共包修复流程不自动安装调试包。

床旁：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
cd "$HARMONY_ROOT\5.0.1-SHIMeta"
.\tools\install-call-app.ps1 -Target <device-ip>:5555
```

主机：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
cd "$HARMONY_ROOT\v1.0_nurse_SHIMeta"
.\tools\install-nurse-app.ps1 -Target <device-ip>:5555
```

## 手工验收点

### call-gateway SDK 验收基准

- SDK 对接以 `call-gateway/docs/integration/client_av_integration.md` 为基准；`docs/gateway/interface.md` 和 `docs/gateway/ctl.md` 是回调与操作字段来源。
- 所有通话 UI、操作、日志、SDP 和 ICE 绑定都必须使用 `uid` / `signalUID`，号码只作为显示、联系人索引和单通话唯一候选兜底。
- SDP / ICE 必须原样透传并绑定 `signalUID`、`rtcUID`、`channelType`；`channelType` 只允许 `publish` 或 `subscribe`。
- 本地生成 answer 或 candidate 后，必须通过 `SendSdp(signalUID, rtcUID, channelType, ...)` 或 `SendCandidate(signalUID, rtcUID, channelType, ...)` 带回同一组字段。
- 接听、保持 / 恢复、普通挂断必须按目标 `uid` 调用 `CallAnswer(uid)`、`CallSwitch(uid)`、`CallHangUp(uid, d)`；缺少 `uid` 时只能走明确的单通话唯一候选兜底，多通话或 `subscribe` 信令必须阻断。
- WebSocket 信令路径中的 `s__apply`、`applyType`、`isAll`、`c__sdp`、`c__candidate`、`c__answer` 与 SDK 接入同属 call-gateway 通话协议，验收时必须共享同一套 uid / peer 归属规则。
- 客户端日志至少能定位 `signal_uid`、`rtc_uid`、`channel_type`、peer、target、action、state 和 reason；多通话下不得出现用最新 `uid` 覆盖旧通话 SDP / ICE 的情况。
- 来电预接听阶段停留 5-10 秒不接听时，主叫端不应听到被叫真实麦克风环境声；接听成功且音频路由稳定后，真实上行音频应恢复。

### 通用启动和基础通话

- 启动页状态检查完成后，等待约 2 秒再进入主界面。
- 启动页长按期间不自动跳主界面，长按完成进入管理员设置。
- 从管理员设置返回启动页后，启动流程可恢复。
- WebRTC 主叫、被叫、接听、挂断流程正常。
- 音频来电收到缺少 `sdpMLineIndex` 的 Candidate 时应用不崩溃；传入 native 的 Candidate 对象不得包含值为 `undefined` 的数值字段。
- 屏幕接听默认免提，通话音量约 90%。
- 手柄接听默认非免提，通话音量约 40%。
- 通话中拿起 / 放下手柄的路由和挂断策略符合对应设备角色。
- 通话结束后恢复接听前音量。
- WebRTC / SIP 协议切换和 runtime config refresh 不打断当前通话。

### 主机 / 床旁启动降级

- 业务接口不可访问但已有缓存配置时，主机 / 床旁可进入主界面并保留通话能力。
- 使用缓存进入主界面时显示“网络异常，请检查网络”提示。
- 后续接口请求恢复成功后，网络异常提示可自动清除。
- 首次安装且没有成功缓存过设备配置时，允许停留在启动页并提示必要数据缺失。
- 在线启动成功后，应持久化设备 `mac`、`token`、`config.json` 和床位图 `ListDeviceBean`。
- 断网启动时，如果本地存在有效 `mac`、`token` 和 `config.json`，启动页应使用缓存跳转主界面。
- 断网进入主界面后，如果床位图接口失败但存在缓存 `ListDeviceBean`，主界面应显示上次床位图、科室信息和本机科室号。
- 断网进入主界面后，如果没有缓存床位图，主界面允许显示加载失败，但不能阻塞启动页跳转。
- 恢复网络后刷新首页，接口新数据应覆盖本地床位图缓存。

### 主机多床旁来电

- 公共模块构建产物版本保持 `0.1.4-rc3`；Example 最小编译验证和后续真机业务验证前必须确认使用的是本次新构建的 rc3 时间戳 HAR，不能混入旧 rc2 或旧 rc3 缓存。
- 单路来电必须沿用改造前已经验证的单人流程和界面风格：publish offer 完成且本地 answer SDP 已发送后接听按钮可点击；call-gateway SDK 接听 / 挂断按当前会话 `uid` 调用，WebSocket 信令路径继续验证 `applyType=2/3`。
- 单路场景不得因多人会话 uid 门控导致接听或挂断不可点击；只有第二路可见会话加入后才启用多人调度和 uid 歧义保护。
- 单路接听、挂断按钮沿用原单人界面的尺寸、间距、配色和交互反馈，图标使用安卓 `call-lib` 对应原始资源。
- 两个床旁同时拨打主机时，主机列表显示两个独立条目，第二路保持待接听状态，不继承第一路接听状态。
- 主机右侧设备区域顶部固定显示本机信息；支持视频且本机视频可用时显示本机视频预览。
- 主机右侧设备区域下方只显示床旁列表，列表超出区域时可在列表区域内滚动，不再出现上下两套床旁列表。
- 点击主机列表中的床旁条目时，选中样式立即切换；仅选择条目不应把待接听来电改成已接听。
- 主机来电默认保持手动接听；即使配置中带自动接听标记，床旁拨入后也应先停留在待接听页面。
- 主机通话 UI 可通过临时版本标记和日志确认实际进入的是 WebRTC 主机组件，而不是 SIP 组件或旧页面。
- 主机收到 WebSocket `c__answer`、call-gateway answer 通知或 `publish connected` 后不能直接进入通话中；业务接听以 gateway 接听接口成功为准，媒体接通以目标 `subscribe` track 匹配为准。
- 主机只有在对应 `uid + rtcUID + subscribe` 路收到对端音 / 视频 track，且从 `track.id` / `stream.id` 解析出的号码匹配当前床旁后，才显示通话中和保持按钮。
- 点击接听后应先进入接听中 / 等待媒体状态，不能直接标记为通话中。
- 音频通话接听后，匹配到对应 `subscribe` 音频 track 即可进入通话中。
- 普通视频设备的视频通话接听后，必须匹配到对应 `subscribe` 视频 track 后才进入通话中；只收到音频 track 时保持连接中 / 等待视频，但控制栏仍完整显示。
- 手表等仅音频设备的视频通话接听后，匹配到对应 `subscribe` 音频 track 即可进入通话中，不等待视频 track。
- 多床旁通话时，每接听一路床旁只建立并绑定该床旁的一路独立 `subscribe`，不能把其它床旁来电串成已接听状态。
- 多床旁通话时，左侧主界面、右侧远端卡片、`SessionPeer`、`SessionState`、`subscribe` 通道和普通挂断都必须绑定同一个业务 `uid/sessionId`。
- 收到 call-gateway SDP / ICE / answer / hangup 回调或 WebSocket `c__*` 信令时，不能因为缺少 `uid` 就随意绑定到当前 active；多通话和 `subscribe` 信令缺少 `uid` 必须阻断，单通话兼容路径只允许按唯一号码映射兜底。
- 多人通话模式下，接听、保持 / 恢复、普通挂断必须携带业务 `uid/sessionKey`；缺少 `uid` 且无法确认单通话兼容路径时，应阻断该操作并记录日志，不能降级成挂断全部或操作当前 active。
- `subscribe` peer 隔离规则对齐 call-gateway：不同 `uid` 的床旁必须独立；同 `uid` 下不同 `rtcUID` / `channelType` 必须独立；号码兜底只能用于单通话唯一候选场景。
- 从双路挂断为单路后，剩余会话恢复单路布局和操作方式，但来电、接听、通话、保持及媒体状态不得被重置。
- 主机左侧当前床旁详情按状态显示操作按钮：待接听显示接听，通话中显示保持，保持中显示恢复，并始终保留当前通话挂断。
- 主机单路来电时，左侧主操作区必须显示接听按钮；本地 `publish` 应答未完成时接听按钮可置灰，`localAnswerReady` 后必须可点击。
- `publish` 应答完成后，不论回调携带的是 callId、uid 还是已登记的 sessionKey，都必须归一到同一路会话并启用对应接听按钮。
- 主机点击接听后，在对应 `subscribe` track 匹配成功前显示连接中 / 等待媒体状态，可以显示挂断、保持、静音 / 禁音、免提 / 切麦等控制，但不能提前标记为通话中。
- 主机床旁列表使用统一中性背景；待接听、通话中、保持中使用状态色标识，当前选中项使用明显边框和焦点样式，不能用多块高饱和背景拼接页面。
- 接听、挂断、保持、恢复、静音、免提和挂断全部必须显示公共图片图标和文字，不能依赖 `✓`、`×`、`Ⅱ` 等字体字符。
- 主机右侧床旁列表中的挂断按钮使用红色小图标按钮，图标和主操作区挂断图标保持一致但尺寸缩小。
- 主机右侧设备区域去掉“通话列表”标题和数量标记，本机画面 / 本机信息与下方远端列表之间使用色块分隔。
- 主机右侧远端列表只显示非当前活动床旁；当前活动床旁只显示在左侧主操作区。
- 点击主机右侧远端列表小框右上角切换按钮时，该床旁切换到左侧主操作区，并从右侧列表移除；原左侧床旁如未挂断则回到右侧列表。
- 主机右侧远端列表小框右上角显示切换按钮；点击该按钮才切换左侧主操作区，日志应出现低敏 `side_switch`。
- 点击主机右侧远端列表的视频 / 头像预览区域不应切换左侧主操作区，避免误触接听、挂断或保持。
- 点击右侧小框右上角切换按钮只切换展示焦点和对应远端 renderer，不得修改任一路的待接听、接听中、通话中或保持状态。
- 已有活动通话时，新的待接听来电只进入右侧远端列表，不能自动抢占左侧主操作区。
- 当前左侧床旁为待接听时，左侧主操作区应显示接听按钮；只点击右侧列表条目不应把待接听来电改成已接听。
- 已接听通话条目显示通话中状态和保持按钮，不显示接听按钮。
- 待接听来电条目显示来电 / 待接听状态和接听按钮，不显示保持按钮。
- 按顺序执行“床旁 1 拨打 -> 主机接听 -> 床旁 2 拨打”时，床旁 1 保持已接听状态，床旁 2 保持待接听状态。
- 继续执行“主机接听床旁 2”后，两个通话条目的接听 / 保持 / 挂断按钮状态分别符合当前通话状态。
- 左侧主操作区普通“挂断”只结束当前活动床旁，右侧列表普通“挂断”只结束该条目对应床旁；call-gateway SDK 必须按目标 `uid` 挂断，WebSocket 信令路径继续验证普通挂断 `isAll=false`。
- 点击右侧床旁 2 的接听按钮后，床旁 2 应留在右侧小框并切换为接听中 / 通话中状态，右侧只显示保持 / 恢复和挂断，不显示挂断全部、静音 / 禁音、免提 / 切麦。
- WebSocket 信令路径的普通挂断信令必须为 `isAll=false`。
- 点击右侧条目的挂断图标时只能触发该路挂断，不能同时触发条目选择，也不能关闭其它路 subscribe peer。
- 点击右侧条目的接听图标时只能触发该条目接听，不能只切换选中项；日志应出现对应条目的低敏 `side_action action=accept`。
- 点击右侧条目的挂断图标时只能触发该条目挂断，不能只切换选中项；日志应出现对应条目的低敏 `side_action action=hangup`。
- 点击右侧小框预览区域不应切换展示焦点；只有右上角切换按钮会切换，日志应出现对应条目的低敏 `side_switch`。
- 右侧按钮日志、控制器操作日志和 UI 模型日志应使用同一个低敏 `sidHash` 串联目标会话，不能输出完整 `sessionKey` / `uid` / `rtcUid`。
- 本地单挂后如果服务端回推无目标身份或误带 `isAll=true` 的终端通知，剩余多路通话不得被清空。
- `publish` 是页面级共享上行通道；call-gateway WebSocket 通话协议中 `c__hangup.data.isHangUp === false` 表示后台确认仍有其他通话，普通单挂或远端单路终端通知应保留 `publish` 和页面；`true` 或缺失表示没有保留语义，最后一路结束时必须关闭 `publish` 和通话页面。
- 挂断第二路时只结束第二路，第一路仍保持原通话状态。
- 挂断第一路时只结束第一路，第二路仍保留并维持原来电或通话状态。
- 两路均已接听时，无论哪一路当前显示在左侧，普通挂断都只能结束当前目标；如果被挂断的是最早建立 publish 的会话，剩余通话仍应自动切到左侧，页面不能关闭。
- 多路通话时左侧主操作区显示图标 + 文字组合的“挂断全部”，点击后所有床旁通话同时结束；右侧本机信息下面不显示挂断全部按钮。
- 多路通话时主机话筒放下触发“挂断全部”，所有床旁通话同时结束。
- 单通话接听后点击保持，条目切换为保持中；再次恢复后回到通话中。
- 多路通话中对当前活动通话点击保持 / 恢复，不应误改变其它床旁条目的保持状态。
- 音频单路接听后，连接中和通话中都应显示头像、用户名、挂断、保持、静音 / 禁音、免提 / 切麦按钮，不应只显示背景图，也不应崩溃退出。
- 如果音频接听后仍崩溃，收集崩溃前后 hilog，优先检查 ArkUI exception 栈以及最后一条 `rtc_answer_state` / `rtc_answer_mark` 日志。

### 通话 UI 参考布局

- 单路呼入页显示头像、名称、邀请类型、拒接和接听；主按钮为 `120vp`，按钮文字为 `22fp`，底部留白与安卓参考一致。
- 单路呼出等待页显示头像、名称、等待提示和挂断；打开页面或点击接听都不能直接显示通话中。
- 点击接听后页面显示连接中，目标 `subscribe` 媒体未匹配前显示媒体层和完整控制栏，但状态不能提前变为通话中。
- 单路音频通话显示头像占位和用户名；单路视频通话在远端视频可用时显示视频，否则保持参考视频背景和头像占位。
- 多路呼入使用两列网格；奇数个来电的最后一项跨两列，最多两行占满可视区域，超出后在网格内滚动。
- 两个床旁同时来电且都未接听时，左右两个分割卡片中的床旁名称和“邀请你语音 / 视频通话”文案必须在各自卡片内水平居中；三路及以上多路呼入、奇数最后一项跨列时也必须保持居中。
- 多路通话主画面和右侧缩略区域宽度约为 `75% / 25%`，本机卡片固定在右侧顶部，非当前目标在下方滚动。
- 当前缩略项使用 `#69F46E` 的 `3vp` 边框，未选中项使用 `#7E7F80`；点击只切换主画面及 renderer。
- 多路视频中每个已有视频 track 的目标都可绑定自己的缩略 renderer；挂断目标后该 renderer 清空，其他缩略视频继续显示。
- 静音、免提、保持、恢复、挂断和挂断全部使用公共图片资源；默认态、选中态和禁用态与模型一致。
- 护士站控制文案显示“免提”；床旁启用麦克风路由切换时显示“切麦”，点击后播放扬声器保持开启。
- 保持只改变目标卡片：头像切换为保持占位，名称显示保持状态，其他通话的视频、状态和按钮不变。
- 横屏和竖屏分别检查呼入、呼出、音频通话、视频通话、多路呼入和多路通话，无拉伸、遮挡或控制区越界。
- 对照 `docs/call-ui-reference.md` 检查字号、颜色、圆角、按钮尺寸、边距、用户名半透明背景和媒体裁剪方式。

## 本地 HAR 分发

设备验收通过后，将已验证的时间戳 HAR 固定在业务工程 `libs/`，并提交对应业务工程依赖路径：

```powershell
.\tools\publish-ohos-rtc-call.ps1 -DevTimestampName -SkipPrepublish -CopyToLibsDir `
  ..\5.0.1-SHIMeta\libs,..\v1.0_nurse_SHIMeta\libs
```

如果 HAR 已经生成，并确认要同步到业务工程 `libs/`，可直接复制已有 HAR：

```powershell
.\tools\publish-ohos-rtc-call.ps1 -HarPath .\dist\ohos-rtc-call-0.1.4-rc3-20260613-153000-123.har -SkipPrepublish -CopyToLibsDir `
  ..\5.0.1-SHIMeta\libs,..\v1.0_nurse_SHIMeta\libs
```

后续不通过 `-Publish` 发布到 OHPM。同步 HAR 后再更新床旁和主机业务工程依赖到对应 `libs` 文件名，分别重新构建和安装验证。
