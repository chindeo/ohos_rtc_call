# 外链铃声失败回落本地铃声

## 需求锁定

- 目标：服务端下发外链 `music` 时，外链拿不到或起不来也必须有铃声；失败可定位；一次失败不影响后续来电。
- 非目标：不改 `externalUrlEnabled` 默认 `false`；不改 Dnake SIP / 厂家铃声通路；不改 `isPlayRingtone=0` 的静音语义；不把 AVPlayer 机制搬进公共包。
- 成功标准：无公网设备（如调试台 .93）来电能听到本地铃声并打出 `result=fallback`；有公网设备（.61）仍直接播外链、**不出现双音**；设备不再出现"派发了、无报错、无声音"。
- 受影响入口：`RtcRingtoneController.playUrl`、宿主铃声 driver、床旁 `RingtonePlayer` 的注册预热与来电播放。
- 不能破坏的已验证行为：来电铃声每次从头播；铃声走独立 `RINGTONE` 流、不跟 `VOICE_CALL` 建拆走；起音要落进近即时自动应答的短窗口（冷启动 create+prepare 已在注册阶段预热）；`c__hangup` 作用域修复与挂断清理。

## 现状缺陷

床旁与主机的外链分支和本地分支不等价，导致静默失效：

- `playUrl` 在只设置完 `url` 时就返回 `true`，不等 `playing`，控制器据此记成"已开播"，`ring_url_gate result=play` 因此不可信。
- `on('error')` 只 `doStop()`，不打错误码；`stateChange` 也不打，失败无从取证。
- 失败后播放器不进 idle，后续来电 `set url` 直接被拒（`5400102 current state is not idle`），一次网络失败把之后所有铃声一起打死。
- 外链播放器不设 `audioRendererInfo`，与本地分支钉 `STREAM_USAGE_RINGTONE` 的行为不一致。
- 循环靠 `completed` 里手动 `seek(0)+play()`，弱于本地分支的 `loop = true`。

## 设计决策

**回落策略下沉到 `RtcRingtoneController`，播放器机制留在宿主 adapter。** 理由是公共包负责"什么时候算失败、要不要回落、怎么记日志"这套决策；`AVPlayer` 的 usage、fd 预热和厂家差异属于设备能力，按仓库规则必须经 adapter 暴露，不能吸进公共包。

**用竞速 + 超时，不用串行 await。** 外链要等下载，串行等待 `playing` 会把起音推到数秒后，破掉自动应答窗口。做法是照常立即派发外链起播，同时开一个超时计时器；期内收到 `playing` 判定成功并取消回落，期内报错或超时则先把外链播放器复位（防止它之后突然出声造成双音），再播已预热的本地铃声，回落是瞬时的。

**回落必须按驱动能力开关，默认关。** 老驱动不回报真实结果时，超时计时器必然到期，会对"本来播得通"的设备叠加一条本地铃声造成双音。所以新增 `urlFallbackEnabled`（默认 `false`）与 `urlFallbackTimeoutMs`（默认 1200），只有宿主驱动确实通过 `onOutcome` 回报时才启用；驱动契约的 `onOutcome` 形参是可选追加，老签名不受影响。

## 驱动契约

- `playUrl?(url, onOutcome?)`：`onOutcome` 用于回报真实播放结果，取值 `playing` / `error` / `idle`。不传即维持旧行为。
- 宿主驱动责任：外链播放器钉 `RINGTONE` usage（设置时机为设 url → `initialized` 回调里设 renderer → `prepare`，否则 `5400102`）、`loop = true`、`stateChange` 与 `error` 带码打日志、失败后 `reset` 回 idle、并在 `onOutcome` 里把结果回报给控制器（控制器不靠"设完 url"判定出声）。
- 宿主预热责任：`music` 是外链时也要预热本地兜底 wav，否则回落会有冷启动延迟。

**回落意图必须挂在实例字段上，不能在 `playUrl()` 返回后只清计时器。** `AVPlayer` 的 IO 失败天然是异步晚到的：驱动的 `playUrl()` 先 `return true`，几十毫秒后 `on('error')` 才回调。若回落标记只是外层函数的局部变量，外层已经走完 `if (pendingFallback)` 判空并返回，晚到的回报只会把 `settled` 置真、清掉计时器，然后把值写进一个再也没人读的变量——结果既没有 `result=fallback`，也没有本地铃声，完全静音，"给无公网设备兜底"这个特性在真实时序下等于没实现。现在上下文 `RtcUrlFallbackCall` 挂在实例字段上，`onResult` 发现外层已返回（`returned`）就地触发回落；`stop()` 会取消上下文，避免挂断后晚到的 `idle` 把铃声重新拉起来。

**`audioRendererInfo` 的设置时机是驱动侧硬性要求：设 url → 在 `initialized` 回调里设 renderer → 再 `prepare`。** 顺序错了宿主侧会直接报 `5400102`，两端都会复现静音。公共包不碰播放器，所以这条只作为契约写在这里，宿主驱动必须遵守。

已知边界（不猜、留取证）：床旁本地常驻播放器在 `createAVPlayer()` 之后、赋 `fdSrc` 之前设 `audioRendererInfo`，在 .99/.93 真机上铃声确实出声；主机报告的是外链播放器在 idle 设报 `5400102`。两者不在同一条通路上，本仓库没法复现主机的外链设备，因此外链分支按上面的 `initialized` 顺序写死，本地常驻分支保持已验证顺序不动，等主机给出具体设备/API 级别再统一。

## 日志约定

- `ring_url_gate result=play|skip|started|fallback|driverRefused|fallbackStopFailed reason=<emptyUrl|policyDisabled|busy|channelDisabled|noDriver|driverNoUrl|io|timeout|refused> channel=<webrtc|sip>`
- 判定读法：`result=play` 只代表"门控放行并派发"，**不代表听到声音**；`result=started` 才是驱动回报过 `playing`；`result=fallback reason=io|timeout|refused` 表示外链没出声、已改播本地铃声。
