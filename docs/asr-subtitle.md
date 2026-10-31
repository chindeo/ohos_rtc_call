# 实时字幕（`c__broadcast` 旁路）

相关文档：

- `host-call-ui-integration.md`：宿主通话 UI 接入边界。
- `call-broadcast-announce.md`：同一条 `c__broadcast` 通道上的通话记录播报。
- `manual-test-and-publish.md`：出包、repin 和全量手工验收点。

## 需求锁定

- 目标：通话期间在通话页显示实时字幕，按通话和发言人分组，通道复用设备已注册的业务 WebSocket 下行事件 `c__broadcast`。
- 非目标：不引入 WebRTC DataChannel，不改 call-gateway 仓库与网关配置，不请求或补拉历史字幕，不做字幕持久化和导出。
- 成功标准：说话出字幕、多路不串话、字幕帧不影响信令与媒体、弱网高频帧不掉注册态、异常帧全部静默容错。
- 受影响入口：`RtcWebRtcCallController` 的 `c__broadcast` 分支与会话结束路径；`RtcHostCallController` 新增 store getter；宿主通话页新增一个字幕浮层。
- 不能破坏的已验证行为：`c__broadcast` 上既有的保持切换和通话记录分支的判定与返回值；来电铃声、接听门控、按 `uid` 挂断和 `publish`/`subscribe` 生命周期；`RtcReferenceCallLayout` 的 75% / 25% 布局和按钮条件。

## 帧通道与三层解析

设备注册的 WebSocket 收到的是 JSON 文本信封 `{"status","result","eventName","data",...}`，`data` 是字符串。字幕只处理 `eventName === 'c__broadcast'`，其余解析次数沿用网关既有约定：

1. 信封解析在 `RtcWebRtcSignalSession` 内完成，包内已存在。
2. `message.data` 解析成 `BroadcastRequest` 形态：`{"commonRequest":{...},"data":"<业务载荷字符串>"}`。
3. 内层 `data` 再解析一次才是字幕帧。

`RtcAsrSubtitle.ets` 的解析器同时接受「裸帧直接放在 `message.data`」这一形状。**任何一层解析失败都返回 `undefined` 静默丢帧，不抛异常**；`type !== 'asr_subtitle'` 的载荷一律不认，继续走原有的保持切换、通话记录与未知广播分支，字幕逻辑不吞任何非字幕帧。

## 字幕帧契约（v2：一句一帧）

```json
{"type":"asr_subtitle","uid":"01f1d40c-...","seq":7,"state":"partial",
 "utterance_id":4,"sentence_end":true,"sentence_text":"现在已经明确，所谓的996。",
 "begin_ms":34200,"end_ms":38150,"generation":1,
 "source_number":"1022","client_type":"bed","role":"bed",
 "language":"zh","ts":"2026-10-30T10:56:15+08:00"}
```

v2 是破坏性变更：**帧里已经没有 `text`**，显示内容只有 `sentence_text`。

- `uid` 是通话归属，多路通话按 `uid` 分容器，禁止用「当前最新通话」猜归属。
- **断行主键是 `(uid, source_number, utterance_id)`**：`utterance_id` 变了就新起一行，同一 `utterance_id` 再来帧就原地替换那一行的内容（位置不动）。端上**不再按 `。！？` 分行**——识别引擎会在半句中间打句号（真机出现过只有 8 个汉字的「整句」），标点不是句子边界。缺 `utterance_id` 时退回用 `seq` 当主键，一句一行。
- **只有 `sentence_end=true` 才冻结这一行**；`false` 表示同一 `utterance_id` 还会再来帧覆盖。`state` 是会话级（`partial`=会话进行中，`final`=会话收尾），不能当「一句结束」用；收到 `state=final` 时把当句一并冻结。
- `seq` 按 `(uid, source_number)` 单调递增，只数真正下发的帧。v1 是整场累计文本，漏帧下一帧会带回内容；**v2 漏一帧就是永久少一句**：网关不补发，端上也不补拉，只按 `seq` 跳号记一条 `rtc_subtitle gap ... missed=n` 供对表，界面上接受少一句。不大于已记录值的帧判为迟到/重复，直接丢，不覆盖行。
- 说话人显示文案取自 `role`（`host` / `bed` / `door` / `doctor` / `watch` / `pda` / `monitor` / `web` / `other`，另收 `nurse`/`nurses`），`other` 或没给时回落到裸 `source_number`。**不再枚举 `client_type`**：真机上 1033 显示成裸号码就是因为取值没覆盖到。**字幕态一律不加名称前缀**（区域本身就是那一路），只靠分色区分；展开成完整记录时才带名称。
- **只显示对方的字幕**：网关把每一路的麦克风都转字下发，本机这路的原文也会推回来，摆在面前就是自说自话。`RtcSubtitleStore.setLocalSpeakers()` 收到本机号码后按 `source_number` 丢掉自己那一路；控制器 `start()` 里配好，那时还没有帧到达。被抑制的帧仍然打对表日志（`self=true`），网关侧能看清"发到了、端上故意不显"。
- 没有可显示文字的帧（`sentence_text` 空或只有标点）不建行。旧 v1 帧（只有 `text`）解析得过但落不成行，不会显示也不会崩。静音期本来就没有帧，端上不判定链路失败、不显示占位符。
- `begin_ms` / `end_ms` 是本句相对「该 `generation` 第一帧音频」的媒体时间，`generation` 在 ASR 重启后 +1 且媒体时间归零重算；`utterance_id` 跨重连不断号，所以重连后端上不清历史。端上按 `generation` 分段维护基准（见下节）。

## 限流与旁路

网关 WS 单客户端发送队列只有 256 条且写满即失败，失败会把设备从 Hub 注销。字幕是纯旁路：

- 同一 `(uid, source_number)` 的更新合并到最小 200ms 一次快照；`state=final`（会话收尾）立即落，保证收尾不被吞。v2 一句一帧，帧本身稀疏，合并窗口只是兜住同一句被连续覆盖的情况。
- 每帧只写自己那一句，渲染不做整段字符串拼接；漏掉的句子不补拉。
- 解析错、渲染异常、容器堆积都不影响信令与媒体，不触发重连或挂断。所有进入字幕代码的路径都不会向外抛。

### 对表日志

每收到一帧打一行，字段和网关侧日志一一对齐，用来判「网关什么时候发的」和「端上什么时候收到的」：

```
rtc_subtitle: uid=<uid> src=<source_number> seq=<seq> utt=<utterance_id> end=<sentence_end>
  gen=<generation> self=<bool> begin_ms=<n> end_ms=<n> ts=<帧里的ts> local_recv_ms=<本机收到时刻>
  text_len=<n> text_hash=<h>
```

`text_len` / `text_hash` 是默认值：识别原文是病床上说出来的话，不进设备日志。排查时给 `RtcSubtitleStore` 传 `logFrameText: true` 才打 `text=<原文>`。

## 渲染

- 每路通话一格，按 `uiModel` 的可见 `uid` 生成，容器不共用；多路时并排且只占主画面的 `75%`，与控制条同宽。
- 位置在**画面底部居中**，像正常视频字幕：默认只显示当前一句，前一句弱显（半透明）垫在上面；
  净空按控制条尺寸留出，压住挂断按钮就没法挂断。
- 点一下字幕区展开成完整记录（可滚动的逐行列表），再点收起；展开态才加半透明底，字幕态只靠文字描边阴影保证可读。
- 发言人分色由 `source_number` 哈希取自固定色板，同一号码任何时候刷新颜色一致；字幕态不加名称前缀（区域本身就是那一路），展开态才带。
- 字幕态背后是一条很淡的半透明底（`#73000000`）：真机录屏里浅色画面（白底卡通、亮墙）会把彩色细字糊掉，只靠文字阴影不够；展开态用更实的底。
- 当前句是正在说的内容（`sentence_end=false`），用光标标记进行中；句子闭合后无光标。
- 展开态默认自动跟随最新；用户上滚后停止跟随并显示「回到最新」，触底后恢复跟随。
- 一行一句由 `utterance_id` 决定，端上不做时间片断行也不按标点猜句子：界面上只会同时出现当前句和上一句，不再把整场文本攒成一坨。字幕态每句最多两到三行，超出省略，展开态不限制。每个容器的行数有上限，超出丢最早的行。

## 生命周期

- 会话结束（本地挂断、远端挂断、离线、整组关闭）后按 `uid` 关闭容器：停止后续更新、把仍未 `sentence_end` 的行转终态、保留历史可滚动查看，不立即清空。
- 字幕浮层随宿主通话页销毁解除订阅并清掉节流定时器；切后台和锁屏同理走组件销毁路径。
- 重新注册成功后只接新帧，并重置 `seq` 基线，避免网关侧重新计数把新会话整批误判为乱序。ASR 重启（`generation` +1）不清历史：`utterance_id` 跨重连不断号，媒体时间归零重算，所以音画基准必须按 `generation` 分段记。
- 日志里 `uid` 和号码只出现在对表那一行（要和网关侧日志对得上），其余状态行只打哈希；识别原文默认不进日志，见「对表日志」。

## 手工验收点

- 单路床旁通话：说话出字幕，静音期无异常无占位，挂断后停止更新且历史仍可滚动。
- 一句一行：每句一帧、`sentence_end=true` 后该行冻结；同一 `utterance_id` 的修订只原地替换，不新起行；不再出现「那么如果求职者在。」这种被标点切碎的半句。
- 只显对方：本机自己说的话不出现在字幕上（日志里对应 `self=true` 的帧被抑制），界面上不出现"自己和自己对话"。
- 双路与多方（4 人以上）：字幕按 `uid` 和 `source_number` 正确分组，不串话；挂断一路不影响另一路容器。
- `role` 显示名：主机与床旁能区分，展开记录里不出现裸号码（`other` 才回落成号码）。
- 通话中重启 ASR 服务：`generation` +1、媒体时间归零，字幕继续且历史不被清空，`utterance_id` 不断号。
- 弱网/高频帧：字幕刷新不掉注册态，日志中后台在线列表仍在；快照更新频率不超过每 `(uid, source_number)` 200ms 一次；`rtc_subtitle gap ... missed=n` 只说明少了一句，不触发任何通话动作。
- 异常帧：缺字段、非 `asr_subtitle` 类型、乱序 `seq`、非法 JSON、只有旧 `text` 的 v1 帧全部静默容错，通话与铃声行为与改动前一致。
- 同一条广播上的保持切换和通话记录播报不能被字幕分支截走。

## 归属与未验项

字幕帧由网关侧 ASR 通路下发。端上实现与单元/编译验证不依赖网关上线，但真机出字必须先确认该机构网关已开启 ASR 字幕推送：若日志始终没有 `rtc_subtitle` 行，属网关未下发而非端上缺陷。

### 2026-10-30 真机录屏判给网关 / ASR 侧的三件事——已由 v2 契约答复

录屏（主机与床旁视频通话，床旁侧外放电视新闻）45s 通话只落约 8 句，端上合并窗口只有 200ms，出句节奏由上游决定：

1. 标点位置：ASR 在半句中间打 `。` → v2 给出 `utterance_id` + `sentence_end`，端上断行不再看标点。
2. 出句延迟：同一行挂 4–8s → v2 给出 `begin_ms` / `end_ms` / `generation`，可以按媒体时间对齐。
3. 发言人归属：`client_type` 取值不全（1033 显成裸号码）→ v2 给出 `role` 枚举，端上按 `role` 出文案。

### 还没做的

- **音画对齐只到"可对表"这一步**：端上现在按 `utterance_id` 即时显示，没有用 `begin_ms` / `end_ms` 排队。要做需要两件事——按 `generation` 维护 `T0 = 本地时钟 - end_ms` 的基准，以及设备自身的音频缓冲深度；后者目前包里没有可靠来源（`getStats()` 的 `media-playout` 在 ArkTS 声明里拿不到 `estimatedPlayoutTimestamp`）。帧日志已经把 `begin_ms` / `end_ms` / `local_recv_ms` 打全，先拿真机数据量出端到端延迟，再决定要不要做排队显示。
- 逐句显示、`role` 文案、漏帧计数都还没在真机上验过（依赖网关 v2 上线）。
