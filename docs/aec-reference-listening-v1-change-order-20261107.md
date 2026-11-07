# reference-listening trial v1 修改单 · 2026-11-07

交付件：`api23-aec-reference-listening-v1-20261107.zip`，ARM32 `libohos_webrtc.so`
sha256 `b1db7f64f2ebf19ccabf6a368284d02cd0dc0132e30a2e8f7f18f1a8b840a8e3`。

验收设备：api23、32 位 ARM 床旁（JHC Cdo-I101），bundle `com.chindeo.bed`。
拨测：网关 `gateway_admin_ctl` 音频通话，激励 `data/cdo.opus`（72s 语音），70s 自动挂断。

**判定：本次 A/B 未能验证 trial 的回声消除收益。** trial 在验收设备上从未进入 `LOCKED`/`ACTIVE`。
两个阻塞缺陷都在交付的 `.so` 源码内，宿主应用侧无问题（ADM 满足 48k/mono/direct-renderer 前置条件，
trial 构造成功）。历史口径与量具见 `docs/aec-echo-cancellation-api23.md`。

---

## 缺陷 1（阻塞·确定）：开关标记路径在应用沙箱内不存在

**位置**：`modules/audio_device/include/ohos_reference_trial.h:9`

```cpp
FILE* f = std::fopen("/data/app/el2/100/base/com.chindeo.bed/files/aec_reference_trial.enable", "r");
```

**实测证据**：应用进程运行在独立 mount namespace，与 shell 不同：

```
app  ns/mnt -> mnt:[4026532914]
shell ns/mnt -> mnt:[4026531841]
```

在该 namespace 内：

```
/proc/<pid>/root/data/app                                  -> No such file or directory
/proc/<pid>/root/data/storage/el2/base/files/aec_reference_trial.enable -> 存在（同一个文件）
```

`/data/app` 在应用 namespace 里**整个目录不存在**；`/data` 是 root 私有 tmpfs（`drwx--x--x`），
只 bind-mount 了 `/data/storage/...`、`/data/service/...` 等子树。

**后果**：按交付 README 在 shell 侧 `touch` 真实路径后重启应用，`OhosReferenceTrialEnabled()`
永远返回 false，`OhosReferenceTrial` 标签零条日志，行为与未开标记完全一致。**开关静默失效**，
且没有任何日志提示路径不对。本次 A 与第一轮 B 的录音指标因此不可区分。

**要求改成**：与同仓 `sdk/ohos/src/ohos_webrtc/audio_device/audio_boundary_diagnostics.cpp:12`
一致的 sandbox 路径，并去掉 bundle 硬编码：

```cpp
FILE* f = std::fopen("/data/storage/el2/base/files/aec_reference_trial.enable", "r");
```

理由：该路径是应用进程自身视角的稳定别名，对主机/床旁/门旁同一份代码都成立；
boundary recorder 用这个路径历史上能正常产出 pcm，是已验证写法。

**代价**：一行。需外机重编 ARM32 `.so`。

**验收**：shell 侧 `touch /data/app/el2/100/base/<bundle>/files/aec_reference_trial.enable`
后重启应用，通话开始即出现 `reference_trial_v1 COLLECTING`；删除标记重启后该标签零条日志。

> 本次为绕过该缺陷取得 B 轮数据，用 `nsenter -t <pid> -m` 在应用进程私有 tmpfs 内补出了原硬编码路径
> （标签 `u:object_r:tmpfs:s0`，宿主真实路径未改动，进程重启即消失）。这是取证手段，不是修复方案。

---

## 缺陷 2（阻塞·确定）：校准队列溢出后永久关闭 AEC

**位置**：`sdk/ohos/src/ohos_webrtc/audio_device/reference_listening_trial.cpp:141-152`、`:83-89`

**实测时间线**（缺陷 1 绕过后，trial 真正启动的那一通）：

```
22:31:37.876  OhosReferenceTrial: reference_trial_v1 COLLECTING ratio=0.91875 capture_buffer_samples=960
22:31:38.225  OhosReferenceTrial: reference_trial_v1 COLLECTING ratio=0.91875 capture_buffer_samples=960
22:31:43.967  OhosReferenceTrial: reference_trial_v1 FAILED calibration queue overflow; mic passthrough
```

启动 6.09s 即失败，整通 70s **没有 `LOCKED`、没有 `REJECTED`、没有 `ACTIVE`**。

**机制**：

- `Capture()` 每 20ms 入队一个 job（50 job/s），`:141` 上限 `jobs_.size() < 100`，即只容 2s 积压。
- 超限走 `:152` `Fail()`；`Fail()`（`:83-89`）把 `failed_` 永久置真、`locked_=false`、清空队列，
  只在首次打日志。`Reset()` 才会清除，而 `Reset()` 只在 ADM 构造/录音启动时调用 → **本通不可恢复**。
- `failed_` 为真后 `:147` `*mapped` 恒 false → `audio/audio_transport_impl.cc:181-185` 给
  `ProcessCaptureFrame` 传 `nullptr` APM，且 `:246` 在 trial 下切断正常 reverse feed
  → **整通无 AEC/NS/HPF/AGC**。

**成本量级（按源码静态推算，非逐块实测）**：

- `Analyze()` → `Correlate()`（`:36-58`）：稳态 `x` 长度 ≈ 96000/(6×0.91875) ≈ 17415，
  FFT 补到 n=32768，每块 3 次 FFT ≈ 7.4×10^5 蝶形；50 块/s ⇒ ≈3.7×10^7 蝶形/s。
  `Fft()`（`:13-35`）用 `std::complex<double>` 且旋转因子靠 `w *= step` 递推（无预计算表）。
- `Joint()`（`:244-292`）：100 个相位 × 最多 150 条 observation × score 长度最多 ≈17415
  ⇒ 单次可达 ≈2.6×10^8 次累加，另加遍历全部 candidate 的次峰搜索；每 50 块（1s）尝试一次。
- 由溢出时刻反推：6.09s 内到达 ≈305 块、队列留 100 ⇒ worker 约处理 205 块
  ⇒ **≈30ms/块 vs 20ms 预算**。这是平均值，无法区分 `Analyze` 与 `Joint` 各占多少。

**要求改动**（(a) 是其余各项定尺寸的前提，必须先做）：

- **(a) 补计时日志**：每次 `Analyze` 与 `Joint` 的 wall ms、`jobs_.size()` 峰值、
  `observations_.size()`、是否触发丢弃。当前一条计时日志都没有，无法判断该优化哪一层。
- **(b) 溢出不得致命**：`:152` 不再调用 `Fail()`。改为丢弃最旧 job 并限速告警，继续收集。
  `failed_` 只保留给真正的格式/时钟错误（`:91` render format、`:119` capture format or clock）。
  理由：best-effort 校准绝不能把整通电话降级成无 AEC。
- **(c) 让 drain 不被搜索阻塞**：按 (a) 的实测数二选一 ——
  把 `Joint()` 移到独立低优先级线程（交接 `observations_` 快照，注意它现在是 worker-only），
  或降低其成本（相位粗到细、限制参与 observation 条数、score 降采样、float + 预计算旋转因子表）。
  若 (a) 显示 `Analyze` 本身已超 20ms，则必须同时降 `Correlate` 成本，(c) 单独做不够。
- **(d) 明确 pre-lock 兜底策略**：书面说明 `audio_transport_impl.cc:181/246`
  「未 locked 即完全绕过 APM 且切断 reverse feed」是有意设计还是过渡态。
  本次台架实测 AEC 全开(A) 与全关(B2) 的上行回声指标几乎不变，所以绕过不是本次 A/B 持平的原因；
  但在声学耦合真实的设备上，校准失败=整通无 AEC 是明确回归。要求 LOCKED 前保留可用兜底。

**代价**：(a)(b) 小；(c) 中等且会动校准数值，必须重新在验收设备上验到 `LOCKED`；(d) 是设计确认。

---

## 不得改动的已验证语义

- `kRatio = 0.91875`、capture 缓冲 960 样本（20ms）、reference 领先 capture 一块（`:144-148` 注释）。
- `LOCKED` 后 reset APM 并使用 external delay 0；mapped reference 取代 APM reverse，**不得双喂**。
- 标记每进程只读一次（`static const bool`），改标记必须重启进程，避免 ADM 与 APM 在同一通里选到不同策略。
- ADM 前置条件校验（48k/48k/mono/mono/非 ring buffer）与不满足时抛错的行为。
- 宿主侧 3A 策略注入（api≥23 `keep_defaults`，否则 `disable_3a`）不在本单范围内。

## 验收清单（验收设备上，70s 音频通话）

1. sandbox 路径标记可开可关，日志可见/不可见 `COLLECTING`，与缺陷 1 验收一致。
2. 通话内出现 `LOCKED calibration_block=… phase=… offset=… corr=… margin=…`，
   随后 `ACTIVE mapped_reference external_delay_ms=0 capture_buffer_samples=960`。
3. 全程无 `FAILED`；`REJECTED` 可接受但必须最终收敛到 `LOCKED`。
4. (a) 的计时日志显示 `Analyze` p95 < 20ms，队列深度稳定不单调增长，峰值 < 100。
5. 人为制造溢出（如临时压低队列上限）时，通话仍保留 AEC 兜底，不再整通 bypass。
6. 回声收益必须在**回声可闻**的条件下另做 A/B：本次台架远端→麦克风耦合弱
   （上行 γ²(300-3400Hz) ≈0.014~0.016，仪器「完全无关」标定底 0.038；包络最佳 r ≈0.13，无关底 0.112），
   AEC 开/关量不出差别，不能作为收益判据。

## 本次录音与指标（上行 = 工具 OnTrack 收到的床旁 track）

| 轮次 | 条件 | 上行 RMS | γ²(300-3400) | 包络最佳 r | 远端静音段最深 |
|---|---|---|---|---|---|
| A | 无标记，平台默认 AEC | −32.4 dBFS | 0.014 | 0.133 | −88 dBFS |
| B（无效） | 标记未被读到，等同 A | −32.5 dBFS | — | 0.142 | −87 dBFS |
| B2 | trial 启动→校准失败→AEC 全关 | −31.7 dBFS | 0.016 | 0.136 | −69 dBFS |

唯一可见差别是远端静音段抑制深度 −88→−69 dBFS，与 B2 关闭 APM 的 NLP 一致。
录音为双单声道（`cmd/admin_ctl/main.go:2304` 硬编码 channels=2，opus 流本身单声道）。

## 2026-11-08 实施边界与验收补充

- 目标：先证明同一音频链中的 APM 初始化、reverse、capture 调用成功；校准失败不得关闭正常 APM。随后验收真机校准，最后比较回声效果。
- 非目标：不修改 M124 参数或 AEC3 核心算法，不重做历史排除实验，不据默认模式 A 的低消除量推断 APM 未运行。
- 上次失败原因：marker 使用应用不可见的宿主路径；校准积压被当作永久失败，且未锁定路径直接向采集处理传空 APM。
- 入口与状态源：进程级 marker；ADM 的采集/播放回调、mapper 的块编号与映射状态；AudioTransport 的参考模式及 APM 返回码。信令、业务接听状态和 UI 沿用宿主，不增加第二套状态源。
- 保持：固定比例 0.91875、960 样本缓存、当前参考配前一采集块、格式守卫、宿主 3A 配置；丢弃只能作用于分析副本，不能改音频块编号或丢上行。
- 兜底：试验未锁定、过载、映射缺失均继续正常参考和 APM；正常整环延迟加现有 20ms 缓存，映射模式延迟 0。保留交付试验的外部延迟估计设置，不新增参数扫描。参考模式切换与 reset 序列化，禁止双喂。
- 最小测试：缓存/编号连续、积压可恢复、零参考不误锁、既有回放映射兼容；正常→映射→正常的参考互斥、reset、延迟与处理错误不发送未处理音频。
- 手工验收顺序：①重启后 marker 开关正确；同链 init/reverse/capture 成功计数增长且 AEC 配置开启，强制校准积压仍有正常 APM；②真机 LOCKED 后映射 reverse/capture 成功，检查计时和队列稳定；③另做远端单讲/近端单讲/双讲效果对照。ACTIVE 单条日志、离线结果都不能替代上述验证。
- 初始授权覆盖代码、测试和 ARM32/API23 构建；后续已明确授权 native 提交推送及指定测试机安装、重启和拨测。native 构建只在 Mac Docker 执行，不在本机执行；不改设备系统配置。

源码修复已提交推送，Mac Docker 的 v2 so 已回包并接入真机；正常 APM、未锁定兜底与锁定后的映射处理均已验证。校准性能仍有不足，近端单讲、双讲和真人听感未验收，详见 `aec-echo-cancellation-api23.md` 第十二节。R1/R2 离线回放的 reference/capture/valid 与原版一致；native 仓库 `sdk/ohos/tests/README-reference-trial.md` 保留具体取证字段与验收口径。
