# api23 设备通话回声消除（AEC）全过程与结论 · 2026-10-13 ~ 11-03

内部分析记录，不是对外材料。

这条线在 2026-10-22 落过一次文档（床旁工程一份、call-gateway 一份），本文把那两份正文、
10-22 之后的两轮后续（主机音频路由取证、api12 关 3A）以及全部推进过程合并成一份。
**以后只在这里追加**；床旁那份 `docs/aec-echo-cancellation-analysis-20261022.md` 保留作当日原始记录。

**范围（用户 2026-10-20 定）**：只处理 api23 机型。api12 床旁是手柄收音，回声问题轻得多，不为它做设计。

**厂商归属（同日纠正，别再叫"视美泰"）**：在架四台里 api23 两台（床旁台架机、主机）= **JHC 金海创**，
api12 两台（床旁、主机）= **DNake 狄耐克**。设备日志自证 `DeviceVendor: vendor=jhc … Cdo-I101 … 23`；
工程目录名里的 SHIMeta 只是历史命名，不代表这批硬件是 Shimeta 的。

**现象（现场对照）**：同族主板分别跑鸿蒙与安卓，同一模拟主机、同一份固定音频各打一通
⇒ **安卓床旁上行几乎干净，鸿蒙床旁上行满屏远端声**（对端持续听到自己刚才说的话）。
安卓那台并非靠平台 AEC：它的录音线程 `0 Effect Chains`，一个 AEC/NS/AGC 都没挂，
干净全靠应用侧软件 AEC3 ⇒ 这是鸿蒙端缺陷，不是"外放形态必然漏"。

---

## 一、当前口径（先给结论，避免重复劳动）

1. **移植的 AEC3 代码没有问题**：fork 与上游 m124 在同一素材上输出逐位相同。
2. **AEC 参数、上报延迟、采样率补偿、电平/削顶都不是原因**：全部实测排除（见第五节）。
3. **失效点在"我们交给渲染器的音频"与"麦克风采到的音频"之间**：鸿蒙这一路，
   麦克风信号与 AEC 参考信号之间找不到任何线性关系（γ²=0.024~0.036，等于噪声底），
   同一块板刷安卓后是 0.834，且安卓处理后 γ²(far,out)=0.001（回声被摘干净）。
4. **断点不在我们自己的 ADM**：把采集侧块状重采样关掉重测，相干性没有恢复（4.4% → 4.6%）。
5. **归属**：应用/HAR 无责、移植代码无责、我们的 ADM 无责 ⇒ 剩余范围是平台播放/采集链路
   （厂商 HAL 内部处理或声学链路本身），端侧无法再往下定位。

一句话：**AEC 没有"消得差"，而是根本没有可消的线性回声参考关系。**

**2026-11-03 用户裁定**：不再拿"回声/降噪代价"拦"关 3A"——原话是"不用管回声和降噪的问题，
因为鸿蒙设备本身无法兼容 WebRTC 的 3A 模块，之前 api23 设备已经有过详细的调试和分析"。
所以 api12 机型整组关掉 AEC/NS/HPF/AGC 是被接受的口径，不要再提"关掉会把回声放回通路"作为反对理由，
也不要反复要求真机听感复核。真要恢复，优先只回开 AEC、或把 NS 从 `.so` 默认的 `kVeryHigh` 降档，
而不是整组回开。

---

## 二、两侧对照实测（同一块 A537 PRO 板、同一份固定激励、同一网关拨测）

| 指标 | 安卓（刷安卓，对照机） | 鸿蒙 Cdo-I101（api23） |
| --- | --- | --- |
| APM 实例数 | 1（48k↔48k） | **3**：16k 空实例、48k/reverse16k 活 4.05s 且从未拿到 reverse、48k↔48k 为实际发送路 |
| 每帧上报 `Stream.delay` | 90 ms | 216 ms |
| APM 配置（CONFIG 事件） | aec开 / ext关 / agnostic关 / drift关 / sup=0 / aecm关 / agc关 / hpf开 / ns=kVeryHigh / `EchoController;` | **逐字段相同** |
| near→out 中位 ERLE | **56.8 dB**（逐窗 42–65 dB，跑满 58s） | 1.5 dB |
| γ²(far, near) | **0.834**（100–4000Hz 0.60~0.89） | **0.024 / 0.036**（噪声底） |
| γ²(far, out) | **0.001**（回声被摘干净） | 0.026 / 0.037（什么都没摘） |
| 10ms 块相关 | 11.5% 块 \|ncc\|>0.5，**71% 落在同一个 100ms 桶** | 4.4%，lag 散在 450~700ms 无主峰 |
| 削顶 | 0.00% | 0.00% |
| 对端实收上行 | −83…−85 dBFS 平底 | −28…−35 dBFS，满是播放内容 |

鸿蒙 far 抽头的**内容**已验证就是网关推送那段语音的原样（三个不同位置匹配到源内同一偏移 4.61s、
尺度 1.0000）⇒ 不是"参考取错了内容"。

---

## 三、推进过程（按阶段，含每一步的判定与撤回）

### 阶段 0（10-13 ~ 10-19）：先确认"上行到底有没有声音"

起点是"对端听不到床旁说话"的现场报告。读安卓侧同硬件日志（MTK + YLD 板）对照出：
采集链路是通的，差别在采集场景 —— 录音机用 `inputSource=1 (MIC)` 能录到，
通话用 `inputSource=7 (VOICE_COMMUNICATION)` 走同一条硬件通路却录不到。
这一阶段把"权限/被抢占/路由条目"这些常见嫌疑排掉，问题收敛为"通话形态下的采集与 3A 行为"。

同期一次定性错误已作废：看到安卓上行 rms 只有 −85 dBFS 就判"安卓根本没发出去"。
用户在同一台机上做了个我没想到的物理实验——同样的播放与音量，**一通敲麦克风、一通不敲**：
敲的那通上行有 −7…−28 dBFS 瞬态，不敲的那通只剩底噪 ⇒ 发送链路一直是活的，
低电平是 3A 把回采和杂音压掉、只有过阈值瞬态才被打进去。**教训：现场对照实验优先于我的电平读数。**

### 阶段 1（10-20）：采集节奏与时间缩放

探测页自激 1370Hz 纯音送扬声器、同一个 ArkTS capturer 回采 15 秒落盘，FFT 量主峰：

```
主峰 1259.95 ~ 1260.13 Hz（4 个窗一致）⇒ 缩放比 0.9197 ≈ 44100/48000
交付 720,000 样本 / 15.910s 墙钟 = 45,255 样本/s（占实时 94.3%）
900→0.9146 / 1370→0.9197 / 2000→0.9177；1370 走 voice 通路同值 ⇒ 不是声学假象
```

**丢样本不会改变音调，只有时间缩放会** ⇒ 早先"250ms 突发在采集里只剩 220ms 所以是整块丢失"的推断是错的
（两种模型都让样本数变短）。AEC3 要的是参考与回声**波形尺度一致**，所以"按墙钟插静音"改不了根因，
对症的做法是把采集流按实测比例重采样。

节奏侧同时量到（HAL 协商 / 每块实测 / 占实时）：

| 配置 | HAL 协商 | 每块实测 | 占实时 |
| --- | --- | --- | --- |
| `SOURCE_TYPE_VOICE_COMMUNICATION`（旧默认） | 44100 | 23.22 ms | 86.1% |
| 同上 + 请求 `inputSampleRate: 48000` | 仍 44100 | 23.22 ms | 86% |
| `SOURCE_TYPE_MIC` + 48000 | 48000 | 21.33 ms | 93.8% |
| 纯 ArkTS capturer + MIC@48k + 回调只计数 | 48000 | 21.17 ms | 94.5% |

这一轮排除掉：AEC/APM 负载（出关 AEC 的包 89.5% vs 开 AEC 89.2%）、CPU（采集回调线程只占单核
14.8~18.5%，8 核里 700%+ 空闲）、应用侧 JS 开销（回调整成只计数，94.5% 不动）、视频负载、
aecdump 文件 I/O、客户端请求采样率（ArkTS 设 48000 改不了 HAL 协商结果）。

### 阶段 2（10-21 上午）：三条各自独立的缺陷浮出

1. **换 MIC 顺手把平台 3A 绕开了**。华为文档口径：平台 3A 只在 renderer `usage=VOICE_COMMUNICATION`
   **且** capturer `source=VOICE_COMMUNICATION` 时才挂。为拿 48k 把采集换成 MIC ⇒ 平台 EC 整条被绕开。
   这是缩放之外的第二个原因，两者会叠加，别混成一个结论。
2. **软件 AEC 可能从来没被打开过**。上游 `EchoCanceller::enabled` 默认 false；
   fork 的 `audio_processing_factory.cpp::Create()` 拿到 JS 传的 options 后写着 `// nothing to do` 整段丢弃。
   唯一还能救活的通路是 getUserMedia 约束在 `webrtc_voice_engine.cc:614` 回写 APM。
   顺带排除"因为有硬件 AEC 所以自动关软件 AEC"：`BuiltInAECIsAvailable()` 硬编码 false。
3. **AEC3 被告知"回环延迟 0ms"**（详见阶段 4）。

同日上午还定下一条读源码纪律：**别再读 `modules/audio_device/ohos/ohaudio_player.cc`** ——
那套只有 `ohos_test.cc` 在用，运行时走的是 `sdk/ohos/src/ohos_webrtc/audio_device/`。在这里白读了两轮。

### 阶段 3（10-21 中午 ~ 下午）：尺度钉死、探针上线、机制定案

- **AEC 确实开了**：真机日志 `OhosWebRtcApm: apm echo=1 … aec3=1`，怀疑 2 关闭。
- 抑制量实测（aecdump）11:07 通 4.17 dB、11:09 通 0.97 dB ⇒ **有出力、没收敛**（收敛的 AEC3 一般 20–40 dB）。
- 根因先落在探针取数缺陷：`align` 每 5 秒用最新一窗重算 ⇒ permille 一路跳 `1168→1069→1072→1050`；
  通话头 ~12 秒压根没重采样。逐窗序列排出来才发现**只有起播第一窗脏**（priming 追帧），
  因为探针数的是"回调向我要了多少帧"= 软件拉取节奏，不是硬件消费点。
- **概念更正：交付速率比 ≠ 波形时间尺度。** 速率比给 ≈1067，音调法直接量到的尺度是 1089（=1/0.91875），
  差 2%；AEC3 要后者。修尺度用音调标定值，别用速率比。
- 用户拍板"按序都一一尝试"四条：A 手工钉 permille、B 探针丢首窗+累计+冻结、
  C 换硬件时间戳 `OH_AudioRenderer_GetTimestamp`、D 设备内音调自标定。
  A 落地后（`rtc_capture_resample permille=1089 vendor=jhc align=false`、`in=480 out=522` 全通话恒定）
  **抑制量没涨**：相干抑制量 +0.3 dB、电平比 0.83 dB ⇒ 钉死尺度没有带来可测改善。
- C 落地证明这台固件**确实暴露 renderer timestamp**（`path=render src=hw`），但同一个 commit 里有单位 bug：
  `OH_AudioRenderer_GetTimestamp` 的 timestamp 是**纳秒**，我按微秒除了 ⇒ `measured=16` 而不是 16000，
  `frozen/stable` 全是垃圾值。因为 align 已关，没造成错误重采样。
- 14:04 轮一度判"参考与回声不相干（ρ≈0.09）"，**当晚自己撤回**：ρ 用的是波形相关，
  点击串经混响信道是 `far * h(t)`，h 展宽几十 ms 时波形相关本来就会塌；阳性标定只造了"纯延迟"回声、
  没造混响 ⇒ 检测器有未发现的假阴性模式。改到能量包络域：near↔far ρ=0.963，控制组挪 200ms 掉到 0.168。
  **教训：否定性结论之前先问"我的检测器在真实信道上标定过吗"。**

### 阶段 4（10-21 晚）：延迟怎么丢在链路里 —— 两层断点

第一层：`EstimateLatencyMillis()` 在平台 API 失败、或 `framesWritten-framePosition<=0` 时 **return 0.0**，
而 0 被当成真读数交给 AEC3（实测真实回环 216ms）。四个 aecdump 的 `Stream.delay` 全 0（4834/4842/4881/3962 块无一例外）。
修法是"不可信就退回上次可信值、再退 75ms 常数，绝不交 0"。装上后日志对了（`hw_latency_ms 126~165`），
**但同一通新 dump 的 `Stream.delay` 依然 4433 块全 0** ⇒ 假设的那条传递链根本不成立。

第二层（真断点）：这套 ADM 给播放和采集**各建了一个 `FineAudioBuffer` 实例**。
`AudioRenderer::fineAudioBuffer_` 在 `GetPlayoutData()` 里缓存 `playout_delay_ms_`，
而唯一会调 `SetVQEData(playout_delay_ms_, rec)` 的 `DeliverRecordedData()` 跑在 ADM 那份实例上，
**那份的 `playout_delay_ms_` 永远是初值 0**。上游是同一个实例包住两路，fork 拆成两个就把这个数弄丢了。
**教训：跨层传一个数，必须从"读端"倒着验到"写端"，别看到中间有个看起来对的字段就当链路通。**

采集侧延迟恒 0 还有两个各自独立的缺陷（同日读源码定案）：
`AudioCapturer::EstimateLatencyMillis()` 用 `framesPerBurst_` 算，而该字段全文件只在 `Terminate()` 里被赋 0、
从没赋过真实值；就算返回 20，`NotifyDataReady(..., deleyUs)` 的第 4 个形参是微秒，ADM 那边按 `/1000` 转毫秒
⇒ **毫秒当微秒用，再被整除 1000 变成 0**。修法改用 `OH_AudioCapturer_GetTimestamp` + `GetFramesRead`
（`queued = framePosition - framesRead`，与 renderer 的 `framesWritten - framePosition` 成镜像），
IPC 限频到每秒一次。装机后量到：这台固件两个 API 都 SUCCESS 但 **framePosition ≡ framesRead**
⇒ 采集队列深度对应用不可见，采集延迟只能取 burst 时长 20ms。

机制级定案（21:33）：先前写的"外部上报值会经 `AlignFromExternalDelay()` 覆盖自带匹配滤波器"
**在这套配置下不成立** —— `use_external_delay_estimator` 默认 false，于是每块走
`delay_controller_->GetDelay()` + `AlignFromDelay()`，`AlignFromExternalDelay()` 永不被调用；
外部值只在 `Reset()` 里当一次初值。
捞 `RTC_LOG` 的办法不用改 `.so`：ArkTS 调 `NativeLogging.enableLogToDebugOutput(1)` 给 `rtc::LogMessage`
挂 `HilogSink`（tag `libjingle`），一轮 40s 通话 23,884 行。读数直方图显示内部估计把 52 块（=208ms，我们钉的值）
拽到 **15 块 = 60ms**（真实 216ms），还会跳到 118/132 块 ⇒ 参考缓冲与回声差 150ms 以上，线性滤波器在错误窗口里。

`extDelay=1` 装机实测又被另一件事淹没：AEC3 实际对齐逐秒完全等于 `call_gap + 54`，
而 `call_gap` 因采集节奏只有实时的 93.75% 而以 −5.6（permille=1089）或 +4.4（1045）块/s 漂移
⇒ **"延迟钉对到底能不能消"这个实验一次都没做成**；两个标定点插值出零漂 permille ≈ 1064，
与点击法 1068 互相印证。下一步本是把计数差钳到 ±2 块并补钳位，**用户当晚叫停**：
已改了好几轮还没定位，先等安卓 m124 vs 鸿蒙 webrtc 源码对照分析，别再自行加跨机轮次。

同轮一次自伤：为从 dump 直接读 AEC3 线性滤波器而打开 `exportLinearAecOutput: true` ⇒ **接听瞬间 SIGSEGV**
（故障线程 `OS_AudioReadCb`）。根因在 fork 的 `echo_canceller3.cc`：`linear_output_*` 缓冲一律按
num_bands=1（=16kHz）分配，而本机 APM 跑 48kHz（num_bands=3）⇒ 越界踩堆。已回退并在注释里写明不能再开。

### 阶段 5（10-21 深夜 ~ 10-22 上午）：交付版 `.so` 全生效，消除量仍 ≈0；电平天花板与 HiPAE

外机离线 A/B 报告先给结论：**fork 与 m124 的 AEC3 逐字节一致、六路输出逐位相同**；
合成回声（216ms + 8.8%/s 漂移）两版都能消 32–55 dB，换真机录音对全部配置塌到 1–4 dB
⇒ 算法代际差异排除。该报告同时证否了我正在推的 ext 模式（理想路径下 ext+216 只有 21.8 dB vs 内部估计器 54.6 dB）。

交付版 `.so`（Android m124 配方默认化）装机核验全过：`apm echo=1 ns=1 agc=0 hpf=1 extDelay=0`、`permille=1068`、
`applied_blocks=52`（=208ms）全程稳定。**结果 `erle_db` 还是恒 0.2**，`erl_db` 26~30，`has_delay` 41 条里只有 3 条。

新查到的机制嫌疑（日志实证）：播放链整条跑在 **HiPAE** 里 ——
`HpaeRendererStreamImpl / HpaeRenderEffectNode / hpaeLoudnessGainNode / hpaeGainNode / Limiter / eq:57`。
限幅器+响度增益是随电平变化的非线性环节，正好是"合成线性回声能消、真机不能消"预测的那种东西。

点击回环电平阶梯（不打电话、单流无拼接）给出硬结论：**存在与电平无关的回声天花板**。
激励 900→5091 时回声严格成正比（±0.4 dB）；再往上回声一点不涨，钉在 ~12,300~12,650（≈ −8.3 dBFS），
相对低档偏离 7200→−2.5 dB、10182→−5.5、14400→−8.6、20365→−11.6、28800→−14.5。
全程 **0 个削顶样本、rho 仍 0.96~0.99** ⇒ 不是波形被削平，是**增益随电平被压**。
`usage=media` 那轮天花板只到 ~3,100 ⇒ **天花板位置跟着播放侧走，不在采集链里**。
拐点在标注 −19~−16 dBFS 附近，这就是"小声能消、大声消不掉"的机理。
同轮还证明路径本身线性且 15 秒内不漂：27/28 击与平均模板相关 rho 中位 0.988、拟合增益 1.00~1.03、
单模板+标量增益的最优线性拟合 ERLE 中位 16.3 dB，模板能量 99% 落在前 14.4 ms ⇒ 抽头长度不是瓶颈。

想自动压电平失败：接听后连发 10 次 `uitest uiInput keyEvent 16`（音量减，keyID 必须是数字，
`VolumeDown` 报 Invalid parameters）⇒ `ring_volume` 仍 14/15、`erl_db` 反而动了 3.7 dB、
下一通上行 rms 从 845 涨到 1035 ⇒ **按键没落到通话流的播放电平上**。真杠杆只有后台 `deviceVolume` 或手按实体键。

### 阶段 6（10-22 上午 ~ 下午）：三实例混流作废 → γ² 一刀 → 断点定位

1. **11:32 自我作废**：鸿蒙一份 aecdump 里是 **3 个 APM 实例混流**（`INIT#1 16000/16000`、
   `INIT#2 48000(reverse 16000)`、`INIT#3 48000/48000`），安卓只有 1 个。
   Stream 帧字段没有采样率，只能按块长分实例，而两个 48k 实例在 dump 层面无法区分
   ⇒ **撤回**所有基于拼接的"3A 净贡献 0.23 dB / AEC 开关无差别"这类逐窗读数。
   工具 `dump-split.js` 按 `INIT` 边界归属实例；用它重切安卓 dump 得到的 near/far/out 与官方
   `unpack_aecdump` 产物 **md5 逐字节相同**（仪器自检通过）。
2. **11:47 新读数**：切分后鸿蒙 apm2 前 6 个 2s 窗 ERLE 40.8/45.9/39.1、之后掉到 1.7…−0.1
   ⇒ 当时改口"不是不行，是锁不住"。
3. **午后再次撤回**：`who-did-it.js` 判那 6 秒的衰减**来自 NS 增益，不是 AEC**
   （AEC 只能移除"far 的线性滤波"那一份；NS 只是整体乘增益）。
   安卓 far↔near \|ncc\| 0.48~0.68 @90ms 每个窗都锁住、out≈0.0；鸿蒙 ≤0.15、lag 在 530~600/2365/1424/92ms 之间乱跳。
   换算"near 中可由 far 预测的能量占比"：安卓 ~56%、鸿蒙 ≤1% ⇒ **正确说法是全程没有可检出的回声消除**，
   不存在"先好后塌"的时间形状，与设备自读 `erle_db=0.2` 自洽。
4. **γ² 是本案最硬的一刀**（`coh2.js`，窗长 65536 点=1.37s）：γ² 对固定延迟与固定尺度都不敏感，
   只在路径不平稳/非线性/两边非同一信号时塌 ⇒ 一次排除"参数没调对"。
   仪器自检四组已知答案 0.721 / 0.025 / 0.036 / 0.026（噪声底）；安卓 0.834、鸿蒙 0.024/0.036。
   trim 0→1600ms 扫描：安卓在 1200ms 处出 0.879 尖峰（与波形法 1221ms、设备自报 90ms 三方对上），
   鸿蒙全区间 0.030~0.053 无峰 ⇒ 鸿蒙不是"也有落盘起点差"。
   尺度×延迟联合扫描（0.90~1.10 × −400…600ms）找不到任何把 \|ncc\| 抬过 0.26 的组合 ⇒ **恒定采样率比这条被真正排除**
   （此前的 sweep 报告只排除了三个点）。
5. **HAL 曲线判"漂移 vs 跳变"**（不用等新 `.so`，11:30 那通的 hilog 就够）：
   capture 增量恒 46080/1.024s ⇒ 45028 样本/秒（比标称低 6.19%），累计拟合残差 rms 11.5ms、**无负增量、无台阶**；
   render 每秒抖动 ±8% 但累计 48007/秒（+0.01%），`frame_position` 恒后于 `frames_written` 7362 样本=153ms，
   与自报 `hw_latency_ms=153.4` 对上 ⇒ 两个都是真硬件计数，两曲线速率比 1.0662，**走"恒定漂移"这一支**。
   同一通 dump 里 far 3938 块 vs near 3910 块（差 0.7%）⇒ 两个抽头在 APM 调用域里同速，
   所以 6.2% 的差不在 far 链与 near 链之间，而在**硬件时钟 vs APM 名义 48k** 之间。
6. **最后一个自家嫌疑 A/B**：把 ADM 采集块状重采样关掉（permille=0）同机同脚本再拨一通
   ⇒ 10ms 块 \|ncc\|>0.5 占比 4.4% → 4.6%，无改善；探针 `has_delay` 从 0/39 变 4/39（112ms、296ms 闪现后回落），
   是 matched filter 抓到瞬时候选、不是锁定 ⇒ **否定**，断点不在我们 ADM。
   附带发现：关掉后第一通甚至没能建立下行媒体，说明这个补偿在当前链路上不是可有可无的。
7. **AEC 开/关同机对照**（两份 HAR 除开关外逐字相同）：AEC 关 near→out −0.22 dB、AEC 开 +0.01 dB
   ⇒ 净贡献 0.23 dB；用户在拨测工具里把两通录音叠着看波形："这两个看起来没有任何区别"。
   这条同时证伪了"会不会是 `erle_db` 低估了实际出力"的担心。**开关 AEC 必须同时改 APM 工厂与 getUserMedia 约束两处**，
   只改一处会被 `webrtc_voice_engine.cc:615` 写回；`apm echo=0/1` 那行日志是唯一实证。

### 阶段 7（10-22 下午 ~ 10-23）：主机音频路由取证 —— 厂商 HAL 不可控的同型证据

回声线叫停后转去做主机（同一批 api23/JHC 硬件）的通话音频路由改造。取证结果与本案归属判定直接相关：

- **厂家 HAL 没有实现 HDI `UpdateAudioRoute`**：`libaudio_render_adapter.z.so` / `libaudio_capture_adapter.z.so`
  （mtime 比同目录其它库新半个月）对框架每次推路由都返回 error -2；同一批库里的私有 handset 模块独占 `/dev/input` 节点。
  实测"手柄拿起 + 屏幕接听"这一从未被测过的冲突组合：播报无声、铃声在听筒、对端声音从听筒出来
  ⇒ **通路完全由手柄状态决定，应用的 `setCommunicationDevice(SPEAKER)` 压不住 HAL**。
- 由此得到的口径：通路真源改读只读节点 `mic_switch`，应用只同步界面不写通路（写下去也会被盖掉）。
  扬声器按钮两台都只翻图标、不听感变化 ⇒ 恢复显示但置灰。
- **对本案的意义**：这台机器的厂商 HAL 会不登记地改写应用请求的音频行为。
  这正是 γ² 断点剩下的两种可能之一（① 厂商 HAL 内部对通话链路做了不登记的处理；
  ② 我们 ADM 的 reverse 抽头取的那一路不是实际到扬声器的那一路）的旁证。

### 阶段 8（11-03）：性能线把 api12 整组关 3A，回声不再是拦路项

视频通话 CPU 归因（api12 主机与床旁各一台台架机）量到：采集回调线程 `OS_AudioReadCB` 在通话中平均吃单核 13–14%，
是应用内最贵的线程；整机从约 100~134% 单核涨到 237~253%（4 核机约 59~63% 负载）。
于是按机型注入 3A 档位：api12 整组关掉 AEC/NS/HPF/AGC，三台日志均为
`rtc_audio_processing_policy api=12 decision=disable_3a`；api23 保持包内默认（`decision=keep_defaults`）。
同轮把 native 日志的 sink 默认关掉（`enableLogToDebugOutput` 的入参在本 fork 里只做范围校验、
sink 恒按 `LS_VERBOSE` 注册，所以按档位传 WARNING 是无效改动，越界值才等于"只移除不重装"），
细节与验收点在 `docs/webrtc-audio-diagnostics.md`。

`.so` 里那批周期诊断打点（`Aec3/AecDelay/CaptureDelay/PlayoutDelay/RateProbe`）实测只占系统 hilog 的
4.3 行/秒（约 6%），洪流主因是 `libjingle`（约 190 行/秒）⇒ 诊断打点不必为性能拆除，取证仍然留着。

**用户裁定见第一节。** 这一轮之后，回声消除不再作为 api12 性能优化的拦路项，也不再用它反推 3A 档位。

---

## 四、当前代码落点（2026-11-06 核对）

- 厂家能力已出库：采集时钟与整环延时由宿主注入（`captureCalibration`），公共包不认厂商。
  床旁侧现值在 `common/src/main/ets/utils/device/RtcDeviceVendor.ets`：
  `captureResamplePermille()` = JHC 1068 / 其它 0（两个独立标定：点击串 +1.96%/s ⇒ 1089/1.0196≈1068；
  AEC3 调用计数差 −5.6/+4.4 块/s 插值 ⇒ ≈1064）；`aecStreamDelayMs()` = 216。
- 3A 档位由宿主按 `sdkApiVersion` 注入 `RtcAudioProcessingPolicy`（`RtcAudioController` 消费），
  **APM 工厂与 `createAudioSource` 约束层必须同写**；APM 实例随 `PeerConnectionFactory` 只建一次，
  所以只能在 controller 构造前注入，工厂已存在时只记 `late_configure ignored reason=pcf_exists` 不假装生效。
  档位细节与手工验收点在 `docs/webrtc-audio-diagnostics.md`。
- 这两项都是**取证留下的补偿量与档位**，不是本案的修法：本案结论是端侧无法恢复线性回声参考。

---

## 五、排除清单（每项都有实测数，别再重复验）

上报延迟 0/90/150/216/280/350/500 · `drift_compensation` · `extended_filter`（13→30）·
`delay_agnostic`（`audio_processing_impl.cc` 里是死字段，硬编码 false）· 延迟搜索加宽
（`num_filters`/`default_delay`/候选阈值/选择阈值，反而更差）· `linear_and_stable_echo_path` ·
放宽近端检测（反而更差）· 以上组合 · near 按 0.9375/1.0667/1.0886 重采样（一律更差、塌陷提前）·
尺度×延迟全域扫描 0.90~1.10 × −400…600ms（无一点过 0.26）· 削顶（两侧 0.00%）·
缓冲跳变/丢块（HAL 计数器无台阶、无负增量、无重复/零块）· 恒定采样率比 ·
播放侧我们自己的环形缓冲（`enableRendererRingBuffer` 默认关，日志 0 条 `buffered_write`、`underflow_count=0`）·
采集块状重采样（A/B 已否）· AEC/APM 负载与 CPU（89.5% vs 89.2%；采集回调线程只占单核 14.8~18.5%）·
应用侧 JS 开销 · 视频/H264 负载 · aecdump 文件 I/O · 客户端请求采样率（改不了 HAL 协商）·
激励太轻（far 每秒 peak p50 ≈ 13,000 = −7.7 dBFS）· 算法代际（fork ≡ m124 逐位）·
硬件与声学（同板刷安卓消得干净；ERL 28~30 dB 是正常外放耦合量级）。

## 六、作废/撤回清单（防止再被引用）

| 曾下的结论 | 现状 |
| --- | --- |
| "网关收到的安卓上行本身就是静音，对端没听到床旁说话" | **错**，被"敲麦/不敲"对照推翻；低电平是 3A 压掉了回采与杂音 |
| "鸿蒙 AEC 开头消到 39~46 dB，6 秒后失锁" | **错**，那 6 秒是 NS 增益压制，不是回声消除。正确说法：全程没有可检出的回声消除 |
| "鸿蒙 aecdump 的 in→out 逐窗读数" | 作废：三实例混流，按 `INIT` 切分后才可用 |
| "3 个 APM 里真正发送那路没拿到 reverse 参考" | **错**：3938 个 reverse 块全在第 3 个实例（48k↔48k，就是发送那路）上 |
| "内容缩放 0.91875 与补齐实时需要的 ×1.0630 互斥 ⇒ 端侧无解只能厂家修" | 推得太快：要对齐的是两路各自除以自己的 label 之比（实测 1.0887），不是采集一路的绝对亏损 |
| "播放 250ms 突发在采集里只剩 220ms ⇒ 是整块丢失" | 错：丢样本不改音调，只有时间缩放会改 |
| "参考与回声不相干（波形相关 ρ≈0.09）" | 当晚自撤：检测器没在混响信道上标定，属假阴性；包络域 ρ=0.963 |
| "包络法测出的 τ 无效" | 我判错了：它给的安卓 1220ms 与后来三方确认的 1221ms 落盘偏移一致 |
| 旧 `coh.js` 的 γ² 全为 0 | 仪器错：窗长 21ms 小于回声延迟，两段窗不重叠；`coh2.js` 用 1.37s 窗才对 |
| "播放侧 render ring buffer 在制造时变输出延迟" | 排除：`UseRendererRingBuffer()` 默认 false，我们没传 |
| 远端分析会话提的"factory 默认值没执行/探针有盲区/AEC 开关只是应用层标志" | 在我们这两通上都不成立（那是按"第三方 App"假设推的）；其中"factory 日志≠最终生效"一条正确，已按它补 CONFIG 复核 |
| "OHOS 没重写 `SetMicrophoneMute`，禁麦是空操作" | 已过时：现在有实现，但函数体只有 `mute_ = mute`，采集流照跑 ⇒ 挡不住平台把铃声暂停 |

## 七、量具与取证手册（下次直接用）

**判"配置到底生效没有"必须读 aecdump 的 CONFIG 事件**：`.so` 里 `OhosWebRtcApm apm echo=…` 那行是工厂
`Create()` 打的，不等于引擎最终应用的配置（`WebRtcVoiceEngine::Apply()` 会用 getUserMedia 约束覆盖）。

| 量具 | 用途 | 关键设计 / 读数边界 |
| --- | --- | --- |
| `dump-split.js` | 按 APM 实例切分 aecdump | 官方 `unpack_aecdump` 是全局拼接；鸿蒙一台一次通话起 3 个实例，混流后任何逐窗读数无意义。切分结果与官方产物对单实例样本 md5 一致 |
| `coh2.js` / `coh-sweep.js` | 相干函数 γ²(f) | **窗长必须远大于回声延迟**（65536 点=1.37s）；自检四组已知答案不过就不出数 |
| `blockcoh.js` | 逐 10ms 块相关 | 10ms 尺度上漂移 ≤0.7ms，可排除"漂移抹平" |
| `who-did-it.js` | 分辨衰减来自 AEC 还是 NS | AEC 只能移除"参考的线性滤波"那一份；NS 只是整体乘增益 |
| `win-table.js` / `erle-dump.js` / `ab3a.js` | near→out 逐窗能量与 ERLE | 10ms 帧、−45 dBFS 活动门限；**必须逐窗**，全段平均会把有效段摊平 |
| `erle5.js` | 按事件顺序把 far 摊到 near 时间轴 | 取代"拼接后互相关"的 `erle4.js`（后者对齐假设不可靠） |
| `clickir.js` / `clickfit.js` / `rampline.js` | 点击回环求路径冲激、拟合增益、电平阶梯 | 远端内容由我们自己生成、单流无拼接 ⇒ 没有双流起点/缝隙混淆 |
| `tone-check.js` | 自激音调量时间缩放 | 先用人造信号标定（48k 版算出 1.0000、45k 版算出 1.0667） |
| `logcurves.js` | 从 hilog 读两条 HAL 计数曲线 | 判"恒定漂移"还是"缓冲跳变"，两者修法完全不同 |
| `echores.js` | 服务端录音量回声残留 | **只能当"明显被播放内容淹没"的阳性检测器**，不能当电平计、不能比两通优劣（标定下限 0.466；必须逐 6s 块自由搜索 + 活动度门控） |
| `aecdump-wav.js` | dump 转 near/out/far 三路 wav | far 比 near 短 ~1.8s（接听前那段没参考），别拿它做严格时间对齐比较 |
| `config-check.py` / `delay-read.py` | 解 CONFIG 事件 / 读逐帧 `Stream.delay` | 按 `debug.proto` 直接解，不用 `unpack_aecdump` |
| `OhosWebRtcAec3` 探针 | AEC3 内部状态每秒一行 | `Aec3ProbeStatus` 是**进程级单例、逐字段写入** ⇒ 同一行里 `erle_db` 与 `call_gap` 可以来自不同实例；节流是函数内 static ⇒ 全进程每秒一行。单位坑：`delay_samples` 是 16k 块域（ms=/16）、`MinDirectPathFilterDelay()` 是块（1 块=4ms）、`FullBandErleLog2()` 是 log2 域、而 `ErlTimeDomain()` 是线性功率比必须 `10*log10` |
| `RtcAudioEnvProbe`（`--ps rtcDebugAction audioEnv`） | 一次问清播放音效/采集溢出/输入设备 | 量到 `getAudioEffectMode()` 一创建就是 `EFFECT_NONE` ⇒ "摘掉 HiPAE"这个旋钮根本不覆盖 Limiter/loudness 节点；`getOverflowCountSync()=0` ⇒ 采集不足额不是丢帧 |

**设备与开关**
- aecDump 开关必须放 **HAP 作用域目录** `.../haps/entry/files/rtc-aecdump.on`（放上一层 `files/` 应用读不到，
  曾因此白跑两通）；dump 落在同目录 `aecdump/`。挂断时 `close aec dump error … code=13900008` 不影响文件已写出。
- 拨测：`gateway_admin_ctl test --transport gateway-ws`，对端推固定 `data/cdo.opus`，接听延后 ≥6s。
- AEC 开关同机对照要出两个 HAR（`echo0`/`echo1`），其余参数逐字相同。
- 纯诊断可原地换 `.so`：`cp` 覆盖 bundle 目录下 `libs/arm/libohos_webrtc.so` + `chown installs:installs` +
  `chmod 644`，SELinux 上下文自动保留；**重装 HAP 会被换回去**，要再换一次。32 位机真正加载的是 `libs/arm` 那份。
- Git Bash 下 `hdc file send/recv` 必须 `MSYS_NO_PATHCONV=1`；本地路径给裸文件名并先 `cd` 到目标目录，
  远端绝对路径写成 `//data/...`，否则被拼到 `C:/Program Files/Git/...` 或静默写到别处。
- 刷机后取证复位：干净镜像里 chindeo 包全没，要用安装脚本重装（`-Target` 只收 host:port，USB 序列号会被拒）。

**方法与激励纪律**
- aecdump 的 STREAM 与 REVERSE_STREAM 是两条独立时间线（安卓侧落盘起点差 1221ms），**必须先裁齐**；
  裁剪单位是 **10ms/960 字节块**，不是 AEC3 的 4ms/64 样本块 —— 算错会得到"消 27~35dB 持续 4s 后塌"这种假结果。
- 人工敲击只当时间标记，不能比电平；电平比较只能用同一份可复现激励（网关固定推送文件）。
- 固定推送文件必须**一页恰好一个 Opus 包、每包 20ms**（DTX 的 3 字节空包也不行），否则推流工具把整段当一个样本烧完。
- 各版本目录里的 `data/cdo.opus` 是**硬链接共享**（链接数上百），覆盖一处等于全变；还原要原位 `cp` 保住 inode。
- 跨轮的绝对电平不可比（会话间音量/增益状态没控住，曾差近 14 倍）⇒ **只有同一轮内的相对曲线可引用**。
- 提"再测一次 X"之前先核对哪些组合已经真机听过，别把听过的当新实验。

**取证脚本位置**：aec 工具集随本轮素材一起归档，路径记在项目记忆（`bed-bench-devices` / 本条记忆），
不进仓库文档，避免把本机绝对路径写进入库内容。

## 八、责任归属分层（用户 2026-10-21 明确要过的口径：分层结论、过程省略）

| 层 | 判定 | 依据 |
| --- | --- | --- |
| 硬件 | **无证据指向坏** | ERL 28~30 dB 是正常外放耦合量级；同族主板刷安卓能消干净 ⇒ 不能回答"外放形态必然漏" |
| 固件（厂商 HAL/平台） | **本案断点所在** | 标注 48k 的采集只交付 93.75% 速率且带 0.9197 时间缩放；平台 3A 即使走通话源也不挂（`HpaeCaptureEffectNode: scenetype: 7 not supported`）⇒ 没有硬件 AEC 可用；采集 timestamp 的 `framePosition ≡ framesRead` ⇒ 队列深度对应用不可见；输出簇跑在 44.1k/2ch（`HpaeOutputCluster … input:[44100_2]`）；播放链全程 HiPAE 带 Limiter/响度增益；同厂 HAL 另一处已实证会不登记地改写应用请求（未实现 `UpdateAudioRoute`） |
| `.so` 源码（移植层） | **曾判主因，后被实测降级** | 当时依据：AEC3 默认不信外部延迟、播放/采集各一个 `FineAudioBuffer` 把实测值丢在渲染侧、采集延迟函数除过从未赋值的字段还把毫秒当微秒传、APM 工厂整段丢弃 JS 配置。这些都真、也都修了；修完 γ² 仍是噪声底 ⇒ 不是本案根因 |
| 应用 / HAR | **有该收的口子，但不是根因** | AGC 默认开着（顺带放大回声）已关；接听前麦没门控已加；为拿 48k 换 MIC 的代价是主动绕开平台 EC —— 这是取舍不是 bug |

兜底路线（软件全失败时）：拿实测数据要求厂家修 HAL 的真实交付率与播放链限幅 / 播报期半双工抑制（用户此前未选）/
改手柄收音形态。

## 九、还没做完的（下次接着走，别从头再查一遍）

1. **拐点在音量增益之前还是之后**（决定能不能"既响又能消"）：同一份电平阶梯跑两轮不同系统音量，
   看拐点在"标注电平"坐标下是否不动（不动=在音量前，则可把写进 renderer 的信号压在拐点以下、再抬设备音量）。
   还要补一轮**低峰均比激励**（正弦/语音形状）复测拐点：点击是 2ms 方波、峰均比极高，真实语音要更响才触发限幅。
2. **离线重放**（安卓素材喂 fork 的 `audioproc_f`）：包已备好，卡在构建机，跨机动作归用户。
   安卓那路是正对照，必须先复现 `out.pcm ±1dB`。
3. **一次通话起 3 个 APM 实例**（安卓 1 个），其中 48k/reverse16k 那个活了 4 秒且从未拿到参考
   —— 与回声结论无关，但需要查清是谁在建、为什么建。
4. **`SOURCE_TYPE_VOICE_COMMUNICATION` 这条 session 上平台到底挂没挂内部处理**：
   `/vendor/etc/hdfconfig/audio_effect.json` 里只有 `mock_effect`，HDI 这层看不到 HAL 内部行为。
   悬案：`HpaeCaptureEffectNode: scenetype: 7 not supported` 里那个 7，与 SDK 的 `SOURCE_TYPE_VOICE_COMMUNICATION = 7`
   数值撞车 —— 但 MIC 源那轮同一位置打的是 `sceneType[1]/[21]` 而同行 `SetCapturerInfo with SourceType 0`，
   所以**倾向于**"效果节点自己的 SceneType 枚举"，仍是推断，别当定论。验法=换 source 看那个数字跟着谁变。
5. 挂断时 `close aec dump error reason=last session ended` 这步失败值得顺手查（文件其实已写出、能解析）。

## 十、网关侧取证方法（原 call-gateway 那份文档的补充节）

本轮所有"对端到底收到了什么"的电平结论都来自网关这一侧，不依赖端上自报。

- **录音是网关另开的一路 WebRTC 订阅**：`chan.go` 的 `RECORD_ACTION_START` 分支按 chat 成员把各自 track
  `AddTrack` 到新建的 `PeerConnection`，再用本地描述去 `RecordToDisk`。所以落盘文件里听到什么，
  等价于"该 sender 实际发出去的流"，可以直接判定上行内容，而不是端上"我以为我发了什么"。
- **录音文件名就是参与者标识**：床旁侧是号码或其 `eth0` MAC（去分隔符），工具/对端侧是 MAC。
  对不上号时读一次 `/sys/class/net/eth0/address`，不要靠猜。
- **方向**（谁是主叫/被叫）以 `chan.go` 里建立会话时的判定为准，不要从号码或 UI 反推。
- 一通只落一个录音文件的现象与端侧 aecDump 开关无关（同机同开关既有两文件的通话也有三通只有单路的），
  本机日志看不到工具那一路是否落盘；要定案需要网关实时日志。本轮未追，与回声结论无关。

## 十一、文档关系

- 本文（`ohos_rtc_call/docs/aec-echo-cancellation-api23.md`）= 唯一权威记录，含 10-22 之后的两轮后续。
- 床旁工程 `docs/aec-echo-cancellation-analysis-20261022.md` = 10-22 当日原始记录，只读，不再追加。
- call-gateway 工程 `docs/analysis/ohos_bedside_aec_echo_analysis_20261022.md` = 同一份当日记录 + 网关侧取证节，
  **只存在于 `v0.0.16` 分支**，当前分支上取不到；其第十节已并入本文。
- 3A 档位与 native 日志档位的工程规则、手工验收点在 `docs/webrtc-audio-diagnostics.md`。


## 十二、2026-11-08：reference trial v2 真机首次跑通

- v2 基于 `2925cb8c889216078816db22fa0680656f0ce49a`，ARM32 so SHA256 `d15eafe04b15dda38943fde40ba3f21a1217fd19f347bd2775b118b643c3a91b`；Mac Docker 构建回包经源码、哈希和 HAP 内库核验后，已安装到原指定 JHC/API23/ARM32 测试机。
- 无标记模式实际运行 APM：同一 chain/generation 的初始化成功、参考与采集成功计数持续增长，返回码 0，AEC 开启。不能把历史默认模式的低消除量解释为没有运行 APM。
- 有标记模式约 7.37 秒完成 LOCKED，随后 mapped 模式同链 reference/capture 成功计数同步增长至 5800；未锁定期间正常 APM 兜底，延迟含 20ms 缓存；映射时延迟 0。两轮 70 秒拨测均正常结束。
- 校准仍有性能不足：队列峰值 100，丢弃 21 个分析副本后锁定；Analyze 最近窗口 p95≈55ms，尚未达到原定 20ms 目标。此次自然积压没有再使 APM 永久旁路。真机没有逐样本边界录制，不能声称已实测上行逐样本连续。
- 真实上行录音在锁定后明显受抑制，AEC3 辅助探针亦出现消除量；后段采集非零、播放计数前进。仅凭输出减小不能把全部衰减归给 AEC，更不能证明近端保真。用户不在设备旁，近端单讲、双讲和真人听感未验收。此前“本设备所有试验均未真正进入 APM”的现状已被本轮更新，但具体平台根因仍未认定。
- 原始证据组名 `aec-v2-integration-1108`：包含 A-normal/B-trial 的进程日志、工具日志、上行 Opus/WAV、runtime-summary.json、RESULT.md、构建安装记录与回退包。当前保留 v2 且试验开关开启；无系统配置修改或 namespace 注入。
