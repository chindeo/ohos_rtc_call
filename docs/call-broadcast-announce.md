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

## 缺口已补：挂断原因中文在端上有一张小表

原先这条写的是"先确认 `RtcServerInfo.i18n` 是不是那张码表再接，不要自己写一份错误码到文本的映射"。
结论：`i18n` 全仓仍未使用，等不到网关下发；改走 `c__hangup` 的 `reason`，端上只镜像四个播报要用到的码，
见下一节。**别把它当成完整码表的替代品**——除了这四条，其它错误文案还是走网关/安卓那条通路。

## 挂断原因的真来源：`c__hangup` 的 `reason`（2026-10-20 定案）

**网关不给呼叫方推带 `status` 的通话记录广播。** 真机取证（HAR `1020-090529`，`rtc_signal_recv` 逐条入站日志）：
21床 → 主机 拒接一次、放到超时一次，两端各自只收到 `c__invite` / `c__sdp` / `c__hangup`，
**整场 0 条 `c__broadcast`**。所以超时、拒接这类原因不能等广播，只能从挂断信令取。

网关在 `peer_grpc.go` 组 `HangUpRequest` 时写 `req.Reason = UnwrapErr(e).Error()`，`c__hangup` 里带的就是这条错误串，
取值与网关自己的中文码表（`type_error.go` 的 `I18nDefault`）对应：

| `reason` | 网关中文 | 播报 |
|---|---|---|
| `timeout` | 无人接听 | 念 |
| `rejected` | 对方拒接 | 念 |
| `other_answer` | 其他设备接听 | 念 |
| `is_calling` | 对方忙线中 | 念 |
| 其它（正常挂断、已接听、空） | — | **不念**，否则每次挂断都多一句噪音 |

鸿蒙拿不到 `errToGBK`（那是安卓在网关进程内调的），所以 `RtcBroadcastHistory.ets` 里
`rtcHangupReasonText()` 只镜像上面四个码——**按业务文案要求处理，不是取代网关码表**；网关补上广播时两处会同时命中，宿主各自做了去重。

方向门控和通路一（广播）一样在包内完成：`RtcWebRtcCallController` 解析到 `reason` 后，
只在**本机是呼出方**时上抛 `onHangupNotice(text, sessionKey)`，宿主只负责念。

**方向只在建会话那一刻定，后续信令不许改写。** 真机踩过：`.104` 主叫、`.93` 拒接，挂断信令里
`from` 是发起挂断的那一方（对端号码），照它折会把主叫侧判成被叫，日志
`rtc_hangup_reason reason=rejected notice=对方拒接 incoming=true` —— 文案都认出来了，
四句提示却被方向门控全挡掉。超时那条同理（`reason=timeout notice=无人接听 incoming=true`）。

取证锚点：`rtc_signal_recv` 每条入站信令打事件名/status/result/长度，
`s__apply` 与 `c__broadcast` 额外打**顶层键名**（`keys=`，值不打）——
网关异步生成的会话主键到底落在回执还是广播里、字段叫什么，靠这一层判。

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

- 自动接听：鸿蒙床旁固定 `自动为您接听`（2026-10-28 现场改口径），安卓 `AutoAnswerUtils.textToast` 仍是 `为您自动接听`，两边故意不一致。
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
  与 `serveNumber` / `autoAnswer` / `enableMulti` 同层。`true` = 只播报不响铃。
- **作用范围（2026-10-20 用户定）：只管主机**。床旁不读这个字段——主机拨打床旁时这台就是被叫，
  必须一直响铃，否则护士打过去整间房没有任何声音提示；床旁响不响由这通呼叫自带的 `isPlayRingtone` 决定。
- **主机默认口径（2026-10-17 用户定）：默认不响铃**。端上按 `server.muteRingtone !== false` 判定：
  只有显式 `false` 才恢复响铃，字段缺省一律按静音处理。
- **服务端配套义务（2026-10-17 定稿）**：既然缺省=静音，"开启响铃"就必须显式下发 `"muteRingtone":false`，
  不能靠 `omitempty` 把键省掉——否则开关变成单向（能静音、再也打不响）。
- 已知服务端根因（服务端侧 2026-10-17 定位）：设备注册的 200 响应由 `ServeWs`（`websocket_client.go`）构造，
  原先赋值放在了 `instance_ws.go` 的转发路径上，serve 路径从未赋值 → 键恒缺省。已移进 `ServeWs` 并加守卫测试。
- 生效时机：注册时下发，改配置后要设备重连/重注册才拿到新值，客户端不需要额外拉取接口。
- 优先级：只有病区一层 + 内置默认；病区队列不存在时按"只播报"。紧急呼叫本期不豁免，与普呼同一字段。
- 落点：`RtcServerInfo.muteRingtone` → `RtcHostCallController.options.onRegistered(server)` →
  主机 `RtcCallHost` 存 `muteIncomingRingtone`，在 `onIncoming` 里决定是否 `playIncomingRingtone`。
  床旁拿到同一个字段但**不用**，注册即预热铃声播放器。
- 取值路径（已逐段核对）：`status===200` 才做 `JSON.parse(message.data) as RtcServerInfo`（`RtcWebRtcSignalSession.applyRegisterMessage`），
  经 `RtcWebRtcCallController.onRegister` → `RtcHostCallController.onRegistered` 透传给宿主。字段按**布尔**下发；
  下发成字符串 `"true"` 时当前写法仍会静音，但任何改成 `=== true` 判定的版本都会失效。
- 日志锚点：主机打 `rtc_ring raw=<下发原值> muted=<端上判定>`，床旁打
  `rtc_ring muted=false reason=bedIgnoresWardSwitch raw=<下发原值>`（TAG `RtcCallHost`）。
  `raw` 用 `String()` 打，能区分 `undefined`（服务端没带字段）和 `false`（显式响铃）。

### 手工验收点

1. 后台"来电响铃"关闭 → 主机日志 `rtc_ring raw=true muted=true`，只播报不响铃；网关尚未下发该字段时同样是 `raw=undefined muted=true`。
2. 后台打开响铃且网关显式下发 `false` → 主机日志 `raw=false muted=false`，铃声恢复。**若 `raw=undefined` 说明服务端还在用 omitempty 省键，响铃开关打不开。**
3. 同一病区下主机呼床旁：不管后台这个开关开着还是关掉，床旁都要响铃（日志 `reason=bedIgnoresWardSwitch`）。
4. 静音病区里播报失败时现场无任何提示，这是已知风险（服务端本期不豁免紧急呼叫），播报失败必须有日志。

## 后台"参数设置"里的三个播报参数（2026-10-20 对接）

- 来源是智慧病房后台的"参数设置"，走 `GET /app/config/list?mac=`。**后台自己按设备类型过滤**
  （`CommonService.selectSysConfigList` 把这台设备的类型映射成 deviceClass，只返回 `deviceClasses`
  包含它的行），所以**端上不判设备类型**：后台没勾这台，这台就取不到这个键。
- `tts.TextToSpeechSpeechRate`（主机+床旁都勾）→ 语速倍率，取值口径见
  `docs/tts-models-and-native-build.md` 的"语速"一节。
- `device.maxCallNotifyCount`（只勾护士站主机）→ **同一条呼叫播报连念 N 遍**。弹窗只弹一次，
  不跟着重复；接通或挂断时剩余遍数要被停掉（`stopNurseTts()` 会同时掐掉正在播和排队的）。
- `call.noOneHearD`（只勾床旁屏）→ 「无人接听」这句的**文案**，非空即替换，空则用包内镜像的网关码表文案。
  对齐安卓 `NoResponseUtils.setNoResponse`：床旁优先取后台，非床旁固定用内置。
- 生效时机跟随 `/config/list` 的刷新节奏（主机：启动 + 周期轮询 + MQTT refreshConfig；床旁：启动 + MQTT）。

## 主叫等待音（回铃音）

- `audio/RtcRingbackTone.ets`：端上合成 450Hz 单音、响 1 秒停 4 秒的 5 秒 wav 落到 `filesDir`，
  AVPlayer `loop=true` 播，钉 `STREAM_USAGE_RINGTONE`。不引入音频素材，改节奏只改三个常量。
- 幅度固定 0.2 是刻意的：呼出阶段本机麦克风已经在采集，太响会从扬声器漏进上行，让对端听见嘟嘟声。
- 起停由宿主接：发出 invite 起，`onConnected` / `onEnded` / `onError` / 页面销毁 停。
  **手柄挂断不产生 `onError`，只产生 `onEnded`**，所以 stop 必须覆盖 `onEnded`。
- 与来电铃声是两个播放器，不共用同一个 `RtcRingtoneController` 实例，否则 `playIncoming` 的
  busy 门会把等待音直接吞掉。

## 手工验收点

1. 床旁开启自动接听、被叫：**全程一声不响**（起铃直接被跳过，不再"响一下再停"），只听到"自动为您接听"，通话正常建立。
2. 床旁呼出、对端不接直到网关超时：听到一次"无人接听"，日志 `rtc_hangup_reason reason=timeout notice=无人接听 incoming=false` + `bed_announce reason=hangup_notice text=无人接听`；再次呼出同样超时会再播一次。
3. 主机呼出、对方不接超时：主机播"无人接听"，日志 `host_hangup_notice text=无人接听`。
4. 主机呼出、对方手动拒接：播"对方拒接"（`reason=rejected`）；被第三方接听：播"其他设备接听"（`reason=other_answer`）；对方忙线：播"对方忙线中"（`reason=is_calling`）。
5. **本机作为被叫**挂断（`incoming=true`）或正常挂断/已接听：**不许播**任何一句，日志里 `notice=` 为空。
6. 与本机无关的第三方通话超时：主机和床旁都**不播**（`getInfo` 门控）。
7. hold 广播只切保持状态，不触发任何播报。
8. TTS 引擎未就绪或服务端合成不可达时，通话流程不受影响，且必须有失败日志，不能静默。
9. 主机点"发送广播"：主机与床旁各念一遍，主机不念自己发出去的那条（防双声）。
10. 主机或床旁**呼出**、对方还没接：本机听到"嘟—嘟—"等待音（响 1 秒停 4 秒），接通/挂断/失败立刻停；
    日志 `rtc_ringback stage=play ok=true` → `stage=stop`。**对端不能听到嘟嘟声**（幅度 0.2 就是为这个）。
11. 后台 `tts.TextToSpeechSpeechRate=0.7`：两端日志出现 `rtc_tts_perf stage=speed value=0.7`，
    之后每条播报都变慢；试听重点看短数字句有没有叠字（历史上 0.85 在中英模型会念成"211床正在呼呼叫"）。
12. 后台 `device.maxCallNotifyCount=10`：主机收到一条呼叫 MQTT 播报，同一条话连念 10 遍；
    弹窗只弹一次；念到一半被接听或挂断，剩余遍数当场停住。
13. 后台 `call.noOneHearD=请稍后`：床旁呼出超时挂断时念"请稍后"而不是"无人接听"；
    该键清空后回落"无人接听"。主机不受这个键影响。
