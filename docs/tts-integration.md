# 端侧离线 TTS 接入

## 目标 / 非目标

- 目标：在床旁 + 主机设备上，通过 `RtcTtsController` 用本地 sherpa-onnx Matcha 模型合成并播放中文播报，无网络依赖。
- 非目标：不做多音色切换、不做二次 DSP 处理、不做流式；本轮只跑通 ANNOUNCE/BROADCAST/CALL 三条播报链路。

## 首选档

- 默认模型：`matcha-icefall-zh-en` + `vocos-16khz-univ.onnx`（约 143MB，含 `espeak-ng-data` 355 个文件）。
- 兜底模型：`matcha-icefall-zh-baker` + `vocos-22khz-univ.onnx`（约 128MB，纯中文、念不出字母）。
- 参数按模型分档（`RtcTtsController` 里 `profileFor(modelDir)`）：zh-en 用 `noiseScale=1.0` +
  `number-zh/date-zh/phone-zh.fst` + 语速锁定 1.0；baker 用 `noiseScale=0.2` + 无 `-zh` 的三个 fst + 语速可调。
- 音频链路：napi `sherpa.generate` → Float32 PCM → 落 wav → `AVPlayer` 播放。

## 数字与时间读法（交给 sherpa 的 rule-fsts）

- 现象：播报句子里的阿拉伯数字不响，前后汉字正常（例：`21床,正在呼叫。` 只念出"床,正在呼叫"）。
- 根因：matcha 中文词典只认拼音，数字必须由文本规整层先展开。
- 现在的做法：`RtcTtsController` 把三个 `.fst`（zh-en 档文件名带 `-zh`）作为 `ruleFsts` 传给
  `sherpa.createAsync`。端上的 `normalizeTtsText` 只补 fst 覆盖不到的三类：时刻（`10:05`）、
  ≥4 位编号的逐位读法、算符与字母枚举，避免和 fst 的两套规整互相覆盖。
- **别再踩的坑**：TTS 的开关/字段叫 `rule_fsts`（CLI 是 `--tts-rule-fsts`），`--rule-fsts` 是 ASR 的；
  给 TTS CLI 传 `--rule-fsts` 会走"未知选项"分支 `exit(-1)`，也就是 RC=255。这个 255 曾被误判成
  "软浮点构建带 fst 会崩"，实际是名字用错。
- 取不到 fst 文件时（老宿主工程没打进包）引擎仍能起，只是数字不响——`ensureModelFiles` 对缺文件容忍，
  `ruleFstsArg` 只拼实际存在的。
- 日期（`2026-10-16`）等更复杂读法以 fst 的规则为准，端上不再单独实现。

## 触发点

1. MQTT `ANNOUNCE`：护理广播（`MqttMessageHandler`）。
2. MQTT `BROADCAST`：床旁 / 走廊广播。
3. MQTT `CALL`：呼叫文本播报（可选，避免与铃声冲突时关闭）。

## broadcast 链路核对（2026-10-15，按安卓代码逐处验证）

结论（2026-10-16 修正）：**安卓侧的"通话事件转 MQTT broadcast"生产端不存在**（空壳 + 注释掉的调用，见下），但**主机 OHOS 工程里已有一个可手动触发的生产端**：`v1.0_nurse_SHIMeta` 的 `pages/broadcast/BroadcastMain.ets` `sendOrSave()` 组装 `MqttPayloadBean(CategoryEnum.BROADCAST,'nurseHost','all',ContentBean,'2')`，实时分支走 `sendBroadcastMqtt(mqttBean,'app/ims/group/'+locCode)` publish，定时分支走 `api.postAddBroadcast`。也就是说端到端"主机发一条广播 → 床旁 speakBedTts"现在就能真机验证，不必先补自动转发生成端。缺的只是"通话事件自动生成 broadcast"这一环。

- 消费端契约（床旁）：`CategoryEnum.BROADCAST = 'broadcast'`，注释即"护士站主机广播"；
  分支取 `msg.content` 走 `speakBedTts`，`msg.roomState == true` 时另外触发一次消息回调。
  字段全表见宿主 `NursesBroadcastMsgBean.ets`：`content / type(1文本 2音频) / repeat / delayTime / creatTime /
  roomState / doorState / hallwayState / nurseState / annex{name,url,action}`。
  注意消费端字段名是 `creatTime`（少一个 e），生产者若按 `createTime` 发会对不上。
- 生产端缺失的三处证据（安卓仓库 `bis_call_gateway_jdk17_merge`）：
  - 网关常量只有 `CategoryCall="call"`、`CategoryCallEnd="callEnd"`（`gateway/Gateway.java:110-113`），**没有 broadcast category**；`WsEventBroadcast="__broadcast"`（:229）是内部 websocket 事件名，不是 MQTT category。
  - `CallSendTypeUtils.sendCallBroadcast(...)` 是**空方法体**（`utils/CallSendTypeUtils.kt:165`）。
  - `RtcManager.noticeInvite` 里 `Gateway.instance().broadcast(...)` 整段被注释，并标注"不能这么用"。
  - 仓库内 `roomState` / `NursesBroadcast` / `ContentBean` 无任何出处，即这套字段口径不由该仓库定义。
- 可照抄的现有范式：`utils/MqttRepository.java` 有 `IMS_GROUP="app/ims/group/"`（:26）与 `answerCall()` 的"组装→按 locCode 拼 topic→发送"完整路径（:62-92）；床旁自身的 `sendCallMqtt`/`sendCallEnd` 也复用同一 `MqttPayloadBean`/`MqttMsgBean` 结构（`content/createTime/msgNo/title/type`）。补齐 broadcast 时应沿用这套外层信封，只把 `category` 换成 `broadcast`、`msg` 换成上面的 ContentBean。
- 真机证据：床旁 .99 拨测期间收到 5 条 MQTT，`消息处理 category=callEnd` 全部，**0 条 broadcast**；`speakBedTts` 从未被调用。

因此 `speak → 合成 → 播放` 这条链在设备上**还没有实际跑过一次**，TTS 端到端验收必须等生产端补齐；另外 `roomState/type` 的字段口径归谁定，需要与后端/主机端确认后再动消费端。

补充（2026-10-16）：安卓的**通话播报**（`为您自动接听`、`无人接听`）根本不走 MQTT broadcast，而是本地事件 + `TextToSpeechUtil.speak`，见 `docs/call-broadcast-announce.md`。这一条已经在鸿蒙侧接通，可以作为不依赖生产端的 TTS 出声验收；MQTT broadcast 转发仍是独立的一步。

## 手工验收清单

取证工具：管理员设置 → TTS 测试页（`aa start -b <bundle> -a SettingHostAbility` 可直接落到设置页，
绕开需要按住 3 秒的入口），按文案定位控件点击，读 `hilog -x -T RtcTts` 里的 `rtc_tts_perf`。
注意引擎日志的 tag 是 `RtcTts`，不是 `console.info` 的 `JSAPP`。

2026-10-19 回填，包 `ohos-rtc-call-1019-095021`，四台设备：床旁 `.104`(api23)、主机 `.93`(api23)、
床旁 `.20.58`(api12)、主机 `.61`(api12)，全部 32 位 softfp。

- [x] 冷启动后第一次 `speak` 有声音、无长静音：`create_ms=9751 threads=4 noiseScale=0.33 fsts=3`，
      首次播报 `rtf=1.18 attempts=1` 无 watchdog。**"有声音"仍要现场听，日志只能证明播放器走完了。**
- [x] 断网状态下重复触发同样播报：`ifconfig wlan0 down` 后用"ping 网关 0% packet loss"判据确认真断网
      （通 → 不通 → 恢复后又通），断网期间连播 3 条不同文案全部 `ok`，`rtf≤1.14`。
- [x] RTF ≤ 2.0：床旁 33 条最大 **1.28**，主机 30 条最大 **1.78**，两台 api12 单条 1.29/1.44。
- [x] 连续播报不失效（本轮新增项）：床旁 3 轮 33 条、主机 3 轮 30 条，队列水位最终归零。
      床旁有 2 条（`seq=18/29`，都是音频 2972ms 那条）渲染器起不来，看门狗到点后重试成功，
      代价是该条延迟约 10 秒；主机 30 条一次都没重试。
- [x] `stop()` 立即静音：正在播的一条音频全长 1451ms，发出 stop 后 **261ms** 结束；
      还在合成就被停的走 `stage=skip reason=cancelled`，排队中的后续条照常播（设计如此）。
- [ ] `release()` 不泄漏：**现网没有调用点**——床旁和主机都没有任何地方调 `release()`，引擎是进程级一次创建。
      该项已改为"create 只发生一次"并取证通过；真要验泄漏得先给测试页加 release 入口或写单测。
- [ ] 与铃声 / 通话音频并发不冲突：日志证明不了抢声道，只能现场听，未做。
- [ ] `noiseScale=0.33` 对比 0.66：0.33 是当前生效值，0.66 对比待单独出包。

### 残留风险

`PLAY_ATTEMPTS=2`（即一条最多重试一次）。两条都超时的那条会**静默丢失**，且没有"引擎已经废了"的聚合告警——
2026-10-19 早上"播报跑一阵就不念、重启才恢复"就是落在这个面上：连续失败时每条都白等 10 秒再丢，
日志上只有零散的 watchdog 行。要收口得加连续失败计数和一条聚合告警。

### 切到 zh-en 后的验收点（2026-10-20 晚定档，四台未验）

- [ ] `stage=extract model=matcha-icefall-zh-en espeak_files=355`（首次解包，第二次同一行应是 `-2`）
      → `stage=init ok=true noiseScale=1 fsts=3`。`fsts=0` 说明 `-zh` 文件名没对上。
- [ ] 字母话术逐字可辨：`ICU三床请到护士站`、`CCU两床呼叫护士站`、`JHC鸿蒙6.1床头`，
      喂给引擎的 `fed=` 应是 `I, C, U, 三床请到护士站`（字母串**首尾都有**逗号）。
- [ ] 数字没被念错：`体温36.5度`→三十六点五度、`21床正在呼叫`→二十一床、`10点05分`→十点零五分。
      这是 10-20 上午退回 baker 的那条判据，本轮必须在真机上复听，不接受只有 PC 数据。
- [ ] 后台语速对 zh-en 不生效：把 `tts.TextToSpeechSpeechRate` 填 0.9，日志应出现
      `stage=speed value=1 model_locked=true`，播报仍常速。测试页顶部的生效语速显示 1。
- [ ] RTF 不劣化：zh-en 与 baker 同架构同尺寸，PC 侧 0.07–0.16，沿用现有 `rtf≤2.0` 那条线。
- [ ] 设备 `filesDir` 里残留的 `matcha-icefall-zh-baker/` 已删，不占 128MB。

## API

```
import { RtcTtsController } from '@chindeo/ohos-rtc-call'

const tts = new RtcTtsController()
await tts.init(getContext(this))
await tts.speak('12 床旁请求增援')
await tts.stop()
await tts.release()
```

## 依赖

- HAR 打包：`libs/armeabi-v7a/{libsherpa_onnx.so,libsherpa-onnx-c-api.so,libonnxruntime.so,libcargs.so}`
- 类型：`src/main/cpp/types/libsherpa_onnx/index.d.ts`
- 模型：宿主 HAP `entry/src/main/resources/rawfile/matcha-icefall-zh-en/`（主机在 `nurse/src/main/resources/rawfile/`），
  两个目录都被各自工程 gitignore
- **模型下载地址、逐文件 sha256 和原生库交叉编译配方（含 onnxruntime 三个源码补丁）见 `docs/tts-models-and-native-build.md`；这些二进制都不进 Git，新环境必须按那份记录重建。**
