# TTS 探针 App（最小单页）

只有一个页面的 HAP，用来在目标机型上单独验证端侧离线 TTS，不带通话、 MQTT、相机等任何宿主逻辑。
用途是回答一类问题：**这台机器上 HAR + sherpa 原生库 + 模型能不能真的出声**，以及换架构（例如 64 位大屏）
时上游预构建的 onnxruntime 能不能在 HAP 应用命名空间里 `dlopen` 成功。

## 目录约定

- `entry/src/main/resources/rawfile/matcha-icefall-zh-en/` —— 143MB 模型，**不入库**（`.gitignore`）。
  从任一宿主工程拷过来即可，来源、逐文件 sha256 和下载地址见 `docs/tts-models-and-native-build.md`。
- `libs/ohos-rtc-call.har` —— 本仓库 `dist/` 里最新 HAR 的固定名副本，**不入库**。
- `local.properties` —— DevEco 生成的本机 SDK 路径，**不入库**。
- 签名材料由开发者在 DevEco 里维护（Project Structure → Signing Configs → Automatically generate
  signature），口令写在 `build-profile.json5`，**提交前把 `signingConfigs` 清回 `[]`**。
  本机现成的三套自动签名 profile 各自钉死了包名（`com.chindeo.bed` / `com.chindeo.nursehost` /
  `com.ohscrcpy.watchdog`），借用哪套就必须把 product 的 `bundleName` 改成同一个，否则装机报签名校验失败；
  想保住 `com.chindeo.ttprobe` 这个独立包名，就得在 DevEco 里给本工程生成一份自己的签名。

## 接这个 HAR 必须自己补的一条声明

`entry/src/main/ets/@ohos.shimeta.d.ts` 不是探针专用的：**公共包里 `device/RtcShimetaDeviceAdapter.ets`
`import shimeta from '@ohos.shimeta'`，而这个名字既不在 oh-package 依赖里、也不是系统模块，必须由宿主自己
声明**。床旁工程是靠 `entry/src/main/ets/@ohos.shimeta.d.ts` 这份同名声明编过的，探针照抄了一份。
任何新宿主少了它就报 `Cannot find module '@ohos.shimeta'`——这不是探针问题，接入文档要按这个写。

## 构建 / 装机

```powershell
# 出 HAR + ohpm install + assembleHap（只构建，不签名也不装机）
pwsh -File example/tts-probe/build-probe.ps1

# 已经生成过签名材料后，装到指定设备并冷启动
pwsh -File example/tts-probe/build-probe.ps1 -Target 192.168.30.118:5555 -Install
```

页面**不会自己播报**：引擎就绪后只显示"已就绪"，一句一句由人点（底部有「连播全部用例」和「停止播报」）。
装机取证时按这个顺序看日志：

```
hdc -t <ip:port> shell "hilog -x -T SherpaShim"   # 期望四条 dlopen ... ok + sherpa symbols bound
hdc -t <ip:port> shell "hilog -x -T RtcTts"       # 期望 stage=init ok=true noiseScale=1 fsts=3
```

## 用例设计

| 句子 | 想验的点 |
|---|---|
| `ICU三床请到护士站` | 字母走 espeak、顿号逐个拼读（`fed=` 应是 `I、C、U、三床请到护士站`） |
| `A10床正在呼叫` | 字母与数字交界，`A10` 现读"A十"（现场已认可） |
| `体温36.5度` | 带小数的数字，`number-zh.fst` 生效与否 |
| `为您自动接听` | 轻声音节，这个模型的内容错率就集中在这类 |
| `21床正在呼叫` | 基线句，实测 36 次全对，用来区分"引擎坏了"和"采样不稳" |
| `二十一床患者张三呼叫护士站请尽快前往处理` | 21 字无逗号长句，已知任何参数下都丢字 |

中英混读档**同一句要连听 3~5 次**，只听一次不算结论（内容错率是按次数统计出来的）。
