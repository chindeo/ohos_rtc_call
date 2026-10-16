# 端侧离线 TTS 接入

## 目标 / 非目标

- 目标：在床旁 + 主机设备上，通过 `RtcTtsController` 用本地 sherpa-onnx Matcha 模型合成并播放中文播报，无网络依赖。
- 非目标：不做多音色切换、不做二次 DSP 处理、不做流式；本轮只跑通 ANNOUNCE/BROADCAST/CALL 三条播报链路。

## 首选档

- 模型：`matcha-icefall-zh-baker` + `vocos-22khz-univ.onnx`（~128MB）。
- 参数：`noiseScale=0.33`、`lengthScale=1.0`、`numThreads=4`。
- 音频链路：napi `sherpa.generate` → Float32 PCM → 落 wav → `AVPlayer` 播放。

## 数字与时间读法（端上规整，必做）

- 现象：播报句子里的阿拉伯数字不响，前后汉字正常（例：`21床,正在呼叫。` 只念出"床,正在呼叫"）。
- 根因：matcha 中文词典只认拼音；sherpa 的数字规整靠 `rule-fsts`，而我们的软浮点 armeabi-v7a 构建一传 fsts 就崩（RC=255）。所以规整必须在端上做，不能指望模型。
- 规则（`RtcTtsText.normalizeTtsText`，`RtcTtsController.speak` 合成前调用）：
  - 1–3 位整数按整数读：`21床` → 二十一床、`105` → 一百零五、`110` → 一百一十；
  - 4 位以上按位读（年份、科室号、住院号）：`2026年` → 二零二六年、`7122515` → 七一二二五一五；
  - 带前导 0 按位读：`0117` → 零一一七；
  - 小数读"点"：`36.5度` → 三十六点五度；
  - 合法时刻读点/分/秒：`10:36` → 十点三十六分、`08:05` → 八点零五分、`10:00` → 十点整、`10:36:20` → 十点三十六分二十秒；
  - 不合法的时刻形状（`25:36`）不做点分解释，冒号直接丢弃（词典本来也念不出它）。
- 日期（`2026-10-16`）本轮**不处理**，需要时另定读法。
- 现场取证：管理员 TTS 测试页选中一条文案后，状态行会显示"念作: …"，即真正喂给引擎的文本。数字仍不响时，看这一行就能区分"规整没生效"和"引擎吞了"。

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

- [ ] 冷启动后第一次 `speak('床旁呼叫')` 有声音、无长静音；模型加载在 init 阶段完成。
- [ ] 断网状态下重复触发同样播报，能继续出声。
- [ ] `noiseScale=0.33` 相比 0.666 停顿更少，句间节奏自然。
- [ ] RTF ≤ 2.0（4 线程、单句 ≤ 3s）。
- [ ] 与铃声 / 通话音频不冲突；`stop()` 立即静音；`release()` 不泄漏 handle。

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
- 模型：宿主 HAP `entry/src/main/resources/rawfile/matcha-icefall-zh-baker/`
- **模型下载地址、逐文件 sha256 和原生库交叉编译配方（含 onnxruntime 三个源码补丁）见 `docs/tts-models-and-native-build.md`；这些二进制都不进 Git，新环境必须按那份记录重建。**
