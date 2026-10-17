# 通话播报语义（自动接听 / 无人接听 / 忙线 / 离线 / 拒接）

## 需求锁定

- 目标：床旁和主机都在与安卓一致的事件上发声，文案取网关下发的通话结果文本，不在端上自造。
- 非目标：本期不做 `c__broadcast` 到 MQTT `app/ims/group/{locCode}` 的转发。安卓 `CallSendTypeUtils` 里被注释掉的“xxx正在呼叫”文案不照搬。
- 成功标准：`.99` / 主机真机能听到对应播报；自动接听播报后铃声停止且不出现双路音频；同一次通话结果只播一次。
- 不能破坏：接听判定仍以网关接听接口为准；`c__hangup` 作用域、铃声门控（`isPlayRingtone`）、外链铃声失败回落行为保持原样；hold 广播仍由 `RtcWebRtcCallController` 内部消化。

## 播报文案有三条互相独立的通路

2026-10-16 按安卓 `bis_call_gateway_jdk17_merge` 逐行核实。**此前文档认定“主机不播无人接听”是错的**，已纠正——错误来源是只看了 `setNoResponse()` 的 `isBed` 门控，没查它上面那条 desc 通路。

### 通路一：通话结果文本 → 本机 Intent 广播 → 各端设备 App 自己念（主机、PDA、床旁都走）

`CallSendTypeUtils.callEnd(bean, transferInfo)` 的入口闸门是 `isAnswerDevices() || isBed`，而 `isAnswerDevices()` = `isNurse || isPda`（`CallSendTypeUtils.kt:83-85`）。命中的四类结果各带一条中文文本：

| 结果 | 文本来源 | 出处 |
| --- | --- | --- |
| 占线 | `RtcConstants.BUSY.desc` | `:50-53` |
| 超时未接 | `RtcConstants.NO_ONE_HEARD.desc` | `:55-65` |
| 离线 | `RtcConstants.OFFLINE.desc` | `:67-69` |
| 其他挂断原因 | `bean.hangUpType`（已由网关换好中文） | `:71-73` |

这些文本经 `sendCallTypeLocId(..., KEY_CALL_END_REASON, desc)` → `context.sendBroadcast()`（`:133-144`）发给同机的设备 App 播报。**关键门控**：`getInfo(bean)`（`:87-105`）对主机/PDA 只有在本机号码出现在 `bean.from` 或 `bean.to` 里时才返回数据，否则 `callEnd` 直接 early-return——即**只播自己参与的那通电话，不播全科室所有超时**；但这条通路**没有“必须是呼出方”的门控**，主机作为被叫超时同样会播。

接收端 App 不在本仓库，因此“具体念成什么、是否带床号”以设备实际表现为准，别在端上凭想象补文案。

### 通路二：床旁专属的自定义文案

`isBed` 且本机是呼出方时才走 `NoResponseUtils.setNoResponse()`（`:59-61`）：优先服务端 `ConfigEnum.noOneHeard` 自定义文案，取不到用本地转换，再取不到才回落“无人接听”。这是床旁在通路一之外额外的一条，不是主机路径。

### 通路三：呼叫内容播报 → MQTT → 外围设备

大屏、走廊屏、门口屏、手表、PDA 等靠 MQTT `call` / `callEnd` category 起停播报（本仓库 AGENTS.md 明确：`call_end` 只服务外围通知，不参与 WebRTC 信令、接听门控或页面切换）。“xxx正在呼叫”这类走这条，与通路一的本机通话结果文本是两回事，不要混用。

## 待补缺口：挂断原因中文不在端上

`hangUpType` 的中文由安卓 `BroadcastConst.isOperationType()` 调 `Gateway.errToGBK{hangUpType}` 换好再往下传。鸿蒙侧没有对应实现，`RtcServerInfo.i18n` 字段虽然存在但全仓未使用。**先确认这颗 i18n 是不是那张码表再接，不要自己写一份错误码到文本的映射。** 本轮能对齐的是超时 / 忙线 / 离线三条固定文本。

## 事件从哪来：`c__broadcast` HistoryBean

解析口径对齐安卓 `BroadcastConst.isOperationType()`：能解析出**带 `status` 字符串字段**的对象才当作通话记录处理，否则继续走原 `onBroadcast`。广播可能把原文再包一层 `{"data":"<原文>"}`，两种写法都要认；包装壳自身没有 `status` 字段，不会被误判成记录（由 `RtcBroadcastHistory.test.ets` 钉住）。字段名以 `HistoryBean.java` 的 `@JSONField` 为准：

`uid`、`from`、`to`、`to_name`、`from_name`、`start_time`、`end_time`、`is_video`、`is_auto_answer`、`status`、`hang_up_type`、`hang_up_number`、`is_mpp`、`is_hold`、`is_calling`、`is_timeout`、`is_offline`。

状态判定与安卓一致：

- 超时：`is_timeout == true`，或 `status` 为 `拨打超时挂断` / `拨打回调超时挂断`。
- 占线：`is_calling == true`，或 `status` 为 `主机繁忙，请稍后再试` / `对方忙线中`。
- 离线：`is_offline == true`，或 `status` 为 `离线挂断`。

无人接听不是端上计时器：超时判定来自网关在广播里带的字段，端只做识别和发声。

## 自动接听

安卓在来电界面展示时判 `!isCallOut && isAutoAnswer() && number 非空`，命中即 Toast + 播 `为您自动接听` + 停铃声（`AutoAnswerUtils.kt:42-67`，调用点 `IncomingCallFragment.kt:91`）。`isAutoAnswer()` 对非 bed 设备直接返回 false，所以这条只属于床旁。

## 鸿蒙侧出口

- `RtcWebRtcCallController`：`c__broadcast` 先按 hold 解析，命中即返回；否则解析 HistoryBean，命中回调 `onCallHistory`，两类都没命中才回调 `onBroadcast`。
- `RtcHostCallController`：透传 `onCallHistory`；`handleIncoming` 中 `session.incoming && autoAnswer` 时回调 `onAutoAnswerNotice`，不改变原有 `onPublishReady` 自动接听执行点。
- 床旁：`RtcCallHost` 把事件映射成文案调 `speakBedTts`，自动接听同时 `stopRingtone()`；按 `uid` 去重。床旁当前按“本机是呼出方”门控超时播报（对应通路二），通路一那条更宽的门控（参与方即可）是否与床旁现有听感重复，**等真机证据再定，不先改**。
- 主机：接 `onCallHistory`，按通路一规则播（本机是 `from` 或 `to` 的一方 + 超时/忙线/离线），复用主机现有服务端 `speak()`，不接离线引擎。

## 文案口径

- 自动接听：固定 `为您自动接听`，与安卓 `AutoAnswerUtils.textToast` 一致。
- 无人接听 / 忙线 / 离线：取安卓 `RtcConstants` 的中文 desc 固定值。
- 床旁自定义无人接听：安卓优先服务端 `ConfigEnum.noOneHeard`。该枚举在 `repository` 依赖里，本仓库读不到真实配置键名，鸿蒙不猜键；先用固定“无人接听”，命中时把 `runtimeConfigMap` 的 key 列表打进日志，取证后再决定接不接。

## 紧急呼叫（安卓现状，鸿蒙暂不实现）

- 触发不在端上：外部 app 发 Android 广播 `BroadcastEnum.CALL_URGENT`（action 就是中文“增援呼叫、紧急呼叫”）→ `CallCoreService.kt:207-211` 映射成 `CallEnum.EMERGENCY`（`isUrgent` 在枚举里硬编码）→ `CallAction.dialPeer`。call-lib 内没有任何 UI/按键直接发起紧急呼叫。
- 播报只有本地广播，没有 MQTT：`CallSendTypeUtils.callOut` → `sendCallTypeLocId` → `sendBroadcast(KEY_CALL_TYPE="URGENT_CALL")`，与普通呼出走同一条，仅文案不同。`sendCallBroadcast` 函数体为空。
- 无独立记录类型：`RtcConstants`（`mmkvSdk` 依赖）里没有紧急项，紧急通话与普通通话共用同一套挂断原因。
- 文案差异：安卓侧 isCallContent 比对的是“紧急增援”，鸿蒙现有 `URGENT_CALL` 分支拼的是“紧急呼叫”，落地前要先定口径。
- 安卓 `callOut` 没有 `isBed` 门控，任何设备只要是发起方都会广播；“只播床旁、不播主机”在安卓并未实现。

## 安卓播报规则（2026-10-16 逐行核实，鸿蒙按此对齐）

- 语音不重复：`TextToSpeechUtil.java:124` 只有 `speak(text, QUEUE_FLUSH)`，无计数、无重播延迟；新播报直接打断旧的，不排队、不去重。
- call-lib 里"xxx正在呼叫"那两条 TTS 调用是注释掉的（`VerticalCallStream2.kt:245`、`CdoCallActivity.kt:185`），实际生效的只有"为您自动接听"和"无人接听"。"正在呼叫"文本由 Go 网关下发给门口屏/走廊屏/TTS 外围设备，重复次数在 Go 侧，本仓库查不到。
- 重复的是铃声不是语音：`CallAudioUtil.java:48` 次数取后台 `ConfigEnum.playRingtoneVibratorCount`（值在 repository AAR 里），床旁呼出置 0 = 无限循环，`AudioPlayer.java:131-145` 播完立即续播无间隔。
- 未接超时：`TimeOutManagerUtils.kt:36` 呼出 95 秒 / 呼入 100 秒 → `CallManager.hangUp` + 停音频，再 2 秒关界面。
- 坑：`TextToSpeechUtil.java:51-56` 当前文本等于"为您自动接听"时 `stop()` 直接 return，不掐。

鸿蒙落地口径：**多条呼叫播报排队全念，不互相打断**（2026-10-16 用户定的，与安卓 QUEUE_FLUSH 有意不一致：
安卓 call-lib 根本不念"正在呼叫"，抢占不是经过验证的产品口径）；每条 CALL/CRASH 消息都念，不绑弹窗生命周期。
`stop()` 只掐正在播的那一条，排队的照常播。

## 来电是否响铃：网关 muteRingtone（2026-10-16 与服务端定稿）

响铃和本机播报同时出声很吵，产品口径改成默认只播报不响铃，由网关开关控制。

- 字段：`muteRingtone: boolean`，在 WS 注册成功响应 `eventName="c__register"`、`status=200` 的 `data` 里，
  与 `serveNumber` / `autoAnswer` / `enableMulti` 同层。`true` = 只播报不响铃；**字段缺省 = 响铃**（老网关、老客户端不受影响）。
- 生效时机：注册时下发，改配置后要设备重连/重注册才拿到新值，客户端不需要额外拉取接口。
- 优先级：只有病区一层 + 内置默认；病区队列不存在时按"只播报"。紧急呼叫本期不豁免，与普呼同一字段。
- 落点：`RtcServerInfo.muteRingtone` → `RtcHostCallController.options.onRegistered(server)` →
  床旁/主机各自的 `RtcCallHost` 存 `muteIncomingRingtone`，在 `onIncoming` 里和原有 `isPlayRingtone` 门控并列决定是否 `playIncomingRingtone`。
  床旁同时在 mute 时跳过铃声预热。
- 日志锚点：两端都打 `rtc_ring muteRingtone=<bool>`（TAG `RtcCallHost`），注册后立刻能看出拿到的值。

### 手工验收点

1. 后台把科室"来电响铃"关掉 → 设备重注册 → 日志 `rtc_ring muteRingtone=true`，来电只有播报没有铃声，接听/挂断流程不受影响。
2. 后台打开响铃（或网关未带该字段）→ 日志 `muteRingtone=false`，铃声行为与改动前一致。
3. 静音病区里播报失败时现场无任何提示，这是已知风险（服务端本期不豁免紧急呼叫），播报失败必须有日志。

## 手工验收点

1. 床旁开启自动接听、被叫：来电界面出现即听到"为您自动接听"，铃声立刻停止，通话仍能正常建立。
2. 床旁呼出、对端不接直到网关超时：听到一次“无人接听”，日志 `bed_announce reason=no_response`；再次呼出同样超时会再播一次。
3. 主机呼出、对方不接超时：主机播“无人接听”。
4. 主机被叫、本机侧超时：主机同样播（安卓这条没有“必须呼出方”门控）。
5. 与本机无关的第三方通话超时：主机和床旁都**不播**（`getInfo` 门控）。
6. hold 广播只切保持状态，不触发任何播报。
7. TTS 引擎未就绪或服务端合成不可达时，通话流程不受影响，且必须有失败日志，不能静默。
8. 主机点“发送广播”：主机与床旁各念一遍，主机不念自己发出去的那条（防双声）。
