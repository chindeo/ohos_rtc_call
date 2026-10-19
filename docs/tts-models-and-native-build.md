# TTS 模型来源与原生库构建记录

模型**不进 Git**（放在宿主 HAP 的 `rawfile` 里，那边被 gitignore）；`libs/armeabi-v7a/*.so`
在本仓库是**被 git 跟踪的**（`git ls-files libs/` 可见），所以下面这些 sha256 是核对产物有没有被
覆盖过的依据，改完 shim 记得把新产物一起提交。
没有这份记录，新环境无法重建可用的 TTS，所以这里是唯一权威来源，请按 sha256 校验后使用。

## 模型文件（matcha-icefall-zh-baker 首选档）

放置位置：宿主 HAP 的 `entry/src/main/resources/rawfile/matcha-icefall-zh-baker/`，四个文件缺一不可。

| 文件 | 字节数 | sha256 |
|---|---:|---|
| `model-steps-3.onnx` | 75,624,188 | `FF1CC7F7ABDEDC4EEEC668A4A0DC2E72A0C314C5637D5FCE885345B490BD08DE` |
| `vocos-22khz-univ.onnx` | 53,884,024 | `0574A135AA1DB2DE6E181050DB2EC528496CACD4A4701FC5D7FAF9F9804C0081` |
| `lexicon.txt` | 1,363,705 | `38B886D46AEFA50DA6322A64D72FD595D5F4FAE1051ADB160D647541B1E0A4A2` |
| `tokens.txt` | 19,591 | `56209B2BF609D5AC1D66EDE6DAE7BF5254BD3F8AA24C4A6823713D5B884D87BA` |
| `number.fst` | 64,482 | `743F402181FCFEBF76CC2F0546B71FA26476E626FBE4E460FB7B4C3A7A8BD5BD` |
| `date.fst` | 59,154 | `EB8AA079AE3CB81D8F4404992F39D61A0CB990947512B5B8D1E54D1F6980E718` |
| `phone.fst` | 88,630 | `1AC2B6FA56B1442320C4DE7DB08353BAB8963A2B57F365EEBCDD3A2D3562F8D7` |

三个 `.fst` 不是可选装饰：matcha 的中文词典只认拼音，缺了它们句子里的阿拉伯数字会被直接吞
（"21床正在呼叫"只念出"床正在呼叫"）。真机对照：同一句带 fst 出 1.867 秒音频、不带只有 1.21 秒。

来源（两个不同的 release，**声码器不在 matcha 压缩包里**，这是最容易漏的一项）：

- 声学模型 + 词表：`https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/matcha-icefall-zh-baker.tar.bz2`
  （压缩包 75,480,460 字节；解压后取 `model-steps-3.onnx`、`lexicon.txt`、`tokens.txt`）
- 声码器：`https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos-22khz-univ.onnx`
  （官方资产 `size=53884024`，与上表字节数一致；同目录下 `vocos-16khz-univ.onnx` 是 53,882,848，**别下错**，两者只差 1176 字节）

获取与校验（本机只有 WSL 能连 github，Windows 侧 git/curl 连 443 不通）：

```bash
cd /tmp && wget -c https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/matcha-icefall-zh-baker.tar.bz2
bzip2 -t matcha-icefall-zh-baker.tar.bz2 && tar xjf matcha-icefall-zh-baker.tar.bz2
wget -c https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos-22khz-univ.onnx
sha256sum model-steps-3.onnx lexicon.txt tokens.txt vocos-22khz-univ.onnx   # 逐项比对上表
```

github release 大文件**经常截断**，必须 `wget -c` 续传、`bzip2 -t` 校验通过后再 `tar`，只凭下载退出 0 不可信。

推理参数与音频链见 `docs/tts-integration.md`；模型是 float 权重，`model.int8.onnx` 在这类包里多为 LFS 占位文件，不可用。

## 原生库（`libs/armeabi-v7a/`，随 HAR 分发）

| 文件 | 字节数 | sha256 |
|---|---:|---|
| `libsherpa_onnx.so`（本项目 napi shim，2026-10-16 那版） | 138,824 | `62ca93940ceba4118a68f9aef7ab89800249b5684c1e76cad86b7ecb365ac7c8` |
| `libsherpa-onnx-c-api.so` | 3,333,004 | `36fe763253fa5962a6d48a4eff25adfd5b829633176cc4e74068a4a0078e469f` |
| `libonnxruntime.so`（自研，非预构建） | 12,333,464 | `f1699d786e4af292359132e06950842996c337e1615256093e9f5d4df5d5fa68` |
| `libcargs.so` | 5,240 | `a90dbed7faa9eab26b5a432963b7e5bc7fecfaf042362e6058eed2b15e3bcb41` |

> 更正：本节原先记的 shim 是 `138,648 / 48fd705d1b69…`，与本机实际分发的那份对不上（应是更早一次构建的记录）。
> 2026-10-19 按下面「shim 重建」一节重编的产物已在 .104 装机跑通 baker（`stage=init ok=true create_ms=11404 fsts=3`）；
> 头一版结构体少字段导致 create 返回 null，修好后的那份以 `ohos_rtc_call/libs/armeabi-v7a/` 里的当前文件为准，
> 换机器重建请按「shim 重建」末尾的判据核对，不要照抄本文早期出现的任何字节数/sha256。

### ABI 前提（不满足就装不上/跑不起）

床旁目标是 **32 位 softfp**：设备有 `/system/lib/libc.so`、无 `/system/lib64`，可执行文件 `PT_INTERP=/lib/ld-musl-arm.so.1`（不是 `armhf`）。
OHOS clang 对 `armv7-unknown-linux-ohos` 裸默认是 pure soft，而 MLAS 的 `arm_neon.h` 直接拒绝 soft-float ABI，所以必须显式
`-mfloat-abi=softfp -mfpu=neon-vfpv4`（softfp 调用约定与 soft 二进制兼容，Cortex-A7 有 VFP/NEON 单元）。

### sherpa-onnx 侧

- 上游 `build-ohos-armeabi-v7a.sh`（含 master）强制 `-mfloat-abi=hard`，产物 `PT_INTERP=ld-musl-armhf.so.1`，在目标设备上跑不起来；上游也不发布任何 OHOS 预编译产物。去掉 hard 即可。
- 去掉 hard 后会撞 eigen 的 `EIGEN_OPTIMIZATION_BARRIER`：`__asm__("": "+g,w")` 里 `w`（VFP 寄存器约束）仅硬浮点合法，报 `invalid output constraint '+g,w'`。改 `_deps/eigen-src/Eigen/src/Core/util/Macros.h` 的 ARM 分支 `"+g,w"` → `"+g"`（须在 configure 之后、make 之前）。
- 构建开关：`-DOHOS_ARCH=armeabi-v7a`、BINARY=ON、C_API=ON；交叉编译只能用 Linux 版 OHOS Native SDK（Windows SDK 只有 clang.exe，不能用于 WSL 交叉）。

### onnxruntime v1.16.3 侧（自研，为解掉预构建 ORT 在 HAP 命名空间 `dlopen ... symbol not found`）

`build.py` 不识别 OHOS 平台，走 cmake 直调 + `CMAKE_TOOLCHAIN_FILE=.../ohos.toolchain.cmake`，
`--disable_ml_ops --disable_exceptions --disable_rtti --disable_contrib_ops` 减体积；**不要用 `--minimal_build`**（只吃 `.ort` 不吃 `.onnx`）。
需要三个源码补丁，缺一个都编不过：

1. `common/cpuid_info.cc`：OHOS 不匹配 `onnxruntime_target_platform` 白名单 → 不定义 `CPUINFO_SUPPORTED`、不链 cpuinfo，但 `ArmLinuxInit()` 里的 `if (pytorch_cpuinfo_init_){...}` 没被 `#ifdef` 包住，引用了未声明符号。把该 if/else 整体包进 `#ifdef CPUINFO_SUPPORTED`，无 cpuinfo 时落到已有的 `getauxval(AT_HWCAP)` 回退分支。
2. `platform/env.cc`（posix）：affinity 段的 `#if` 没排除 OHOS，会调 musl 没有的 `pthread_setaffinity_np`。给该 `#if` 追加 `&& !defined(__OHOS__)`。
3. 依赖获取：`cmake/deps.txt`（`name;URL;SHA1`）里 `github.com/.../archive/*.zip` 的 HTTP/2 重定向在 WSL curl 会卡住不 follow，改 `codeload.github.com` 直链；`eigen` 只在 gitlab 且 archive 字节会变、钉的 SHA1 对不上，用官方开关 `onnxruntime_USE_PREINSTALLED_EIGEN=ON` + `eigen_SOURCE_PATH=<Eigen 3.4.0 目录>`（eigen 纯 header-only，此路径完全不 fetch、不校验哈希）。其余依赖预取到本地后把 `deps.txt` 改写成 `file://`，并且**必须 `rm -rf build_ohos_armv7` 强制重配**——FetchContent 的 subbuild 会缓存旧 URL。

成功判据只认产物文件：`find build_ohos_armv7/Release -name 'libonnxruntime.so*'`。
不要看包装脚本的 exit 0——`bash build.sh; echo EXIT=$?` 这种写法会把 `build.py` 的真实失败吞掉，本项目曾据此误报过一次"构建成功"。

### napi shim 侧

- HAP 应用命名空间**不会**按 `RUNPATH=$ORIGIN` 解析兄弟目录里的 app `.so` 依赖，所以 shim 不把这些 `.so` 写成 `DT_NEEDED`，而是在构造函数里用 `dladdr` 取自身目录、按 `libc++_shared → libonnxruntime → libcargs → libsherpa-onnx-c-api` 顺序 `dlopen(RTLD_LAZY|RTLD_GLOBAL)`，再 `dlsym` 绑 6 个 C API 指针。
- `SherpaOnnxCreateOfflineTts` 要 mmap 上百 MB 模型，**跑在主线程会阻塞 ability 生命周期事务、被 sysfreeze `LIFECYCLE_TIMEOUT` 看门狗杀掉，表现像"启动就崩"**。因此 shim 提供 `createAsync`/`generateAsync`：`napi_create_async_work` 丢到 libuv 线程池、`napi_deferred` 回主线程 resolve，并用全局 `std::mutex` 串行化 create/generate（同一 `OfflineTts` 实例的 generate 非线程安全）。
- 真机取证：`SherpaShim` 应出现四条 `dlopen ... ok` + `sherpa symbols bound`；合成期日志的 TID 与主进程 PID 不同即证明已离开 UI 线程。

## 环境与版本基线（换机器先看这一节）

| 项 | 值 | 怎么确认 |
|---|---|---|
| OHOS Native SDK | apiVersion **12**、包版本 **5.0.0.71**，取 `5.0-ohos-sdk-windows_linux-public.tar.gz` 里的 **linux** 侧 `native` 包 | `cat <SDK>/native/oh-uni-package.json` 的 `apiVersion` / `version` |
| 交叉编译器 | `native/llvm/bin/armv7-unknown-linux-ohos-clang++`，OHOS (dev) clang **15.0.4** | `clang++ --version` |
| sysroot | `native/sysroot`，需要 `usr/include/napi/native_api.h`、`usr/include/hilog/log.h`、`usr/lib/arm-linux-ohos/{libace_napi.z.so,libhilog_ndk.z.so}` | 构建脚本会逐项检查并报错 |
| sherpa-onnx | **v1.12.18** | `strings libsherpa-onnx-c-api.so \| grep -E '^1\.[0-9]+\.[0-9]+$'` |
| sherpa C API 头 | `https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v1.12.18/sherpa-onnx/c-api/c-api.h` | shim 里的结构体必须与该 tag 一致 |
| onnxruntime | 1.16.3（自研，见上一节三个补丁） | — |

Windows 侧的 SDK 只有 `clang.exe`，不能产出 OHOS ELF；交叉编译只能在 Linux/WSL 里跑。
WSL 里解包位置不固定，构建脚本用 `OHOS_NATIVE` 环境变量覆盖，默认 `/root/ohos-native/native`。

## shim 重建

源码 **`src/main/cpp/sherpa_tts_napi.cpp`（已入仓）**。此前仓库里只有 `.so` 产物和 sha256，
没有源码，也没有任何编译命令——2026-10-19 想给 `dataDir` 加字段时发现本机已经找不到这份源码
（`sherpa_tts_napi.cpp` 这个文件名只能从产物里的 `_GLOBAL__sub_I_sherpa_tts_napi.cpp` 挖出来），
所以按本文的行为记录重写了一份。**下次别再只留产物。**

构建（在仓库根，WSL/Linux）：

```bash
bash tools/build-sherpa-shim.sh          # OHOS_NATIVE=<sdk>/native 可覆盖
```

脚本里的关键参数：`--target=armv7-unknown-linux-ohos -mfloat-abi=softfp -mfpu=neon-vfpv4`
（ABI 原因见上面）、`-std=c++17 -Os -DNDEBUG -fPIC -shared`、链 `ace_napi.z hilog_ndk.z c dl`，
并会把旧产物备份成 `libsherpa_onnx.so.before-<时间戳>`。

导出接口（与 `src/main/cpp/types/libsherpa_onnx/index.d.ts` 一一对应，改动要同步）：
`create` / `createAsync` / `destroy` / `generate` / `generateAsync` / `sampleRate` / `numSpeakers`，
模块注册名 `sherpa_onnx`，日志 tag `SherpaShim`。

两条踩过的坑：

1. **不要加 `-nostdlib++`。** 那样 `DT_NEEDED` 里就没有 `libc++_shared.so`，而产物里有
   `_ZTISt12length_error`、`_ZTV…` 这类**非 lazy 重定位**，加载期就要解析；构造函数里的
   `dlopen(libc++_shared.so)` 跑在重定位之后，救不回来，表现是模块直接加载失败。
   照旧产物那样正常链 libc++（`DT_NEEDED` 由系统侧的 `libc++_shared.so` 满足）。
2. 结构体字段**必须逐字段**照 v1.12.18 的 `c-api.h:1019-1100` 抄，少一个字段不会编译报错，
   只会让后面的字段整体错位。本项目踩的是 `SherpaOnnxOfflineTtsZipvoiceModelConfig` 少了
   `target_rms`/`guidance_scale`（40 字节写成 32 字节），外层 `silence_scale` 因此读成 0，
   真机表现：`sherpa_onnx: --tts-silence-scale '<private>' is too small` → `Errors in config`
   → `SherpaOnnxCreateOfflineTts returned null`，应用侧只剩"TTS 未初始化"。
3. C API 结构体没有默认值，`max_num_sentences=1`、`silence_scale=0.2` 这两个上游给在 C++
   结构体里的默认值必须显式赋；`Reject()` 要记一条原生日志并 reject 真正的 `Error` 对象，
   否则宿主侧 `error.message` 打成 `undefined`，排查时看不出失败在哪一步。

## 中英混读模型（matcha-icefall-zh-en，尚未接入）

换它的原因是 baker 只能念汉字：**给 `lexicon.txt` 补字母条目是无效的**（实测 52 行大小写条目、
`ABCDEFGHIJ` 仍然 `reason=empty_audio synth_ms=13`，字母在查词表之前就被中文前端丢了）。
zh-en 的英文走 **espeak-ng**，与词表无关。

包内文件（tar 79,033,838 字节，解压后约 93MB）：

| 文件 | 字节数 | 说明 |
|---|---:|---|
| `model-steps-3.onnx` | 75,717,082 | 与 baker 的 75,624,188 同级，算力同档 |
| `lexicon.txt` | 1,400,278 | 68,037 行，**以 ASCII 开头的键 0 条** |
| `tokens.txt` | 21,146 | 2,190 个 token，含 IPA/英文音素 |
| `espeak-ng-data/` | 约 19MB、120 个文件 | **必须随包分发**，`data_dir` 指向它的父目录 |
| `number-zh.fst` / `phone-zh.fst` / `date-zh.fst` | 64,482 / 88,630 / 59,154 | 文件名与 baker 不同，带 `-zh` |
| 声码器 | `vocos-16khz-univ.onnx` 53,882,848 | README 指定，22k 那只**不能用** |

接入要点：现有 `libsherpa-onnx-c-api.so` 的字符串里已有 `--matcha-data-dir` 和
`Failed to initialize espeak-ng with data dir`，说明 **c-api 不用重编，只需重编 shim**
（本仓库 shim 已加 `dataDir` 字段）；另外宿主侧 `ensureModelFiles` 目前只拷平铺文件，
接 espeak-ng-data 之前要补目录递归拷贝。

## 下载与环境坑

- **只有 WSL 能连 github**，Windows 侧 git/curl 走 443 不通。
- github release 资产返回的是带签名的临时地址，**过期时报 `618 jwt:expired`**；续传必须重新请求
  `github.com/<repo>/releases/download/...` 原始地址（脚本里包一层重试循环）。曾据此以为在下，
  实际以 35KB/s 卡了半小时。
- 大文件一律 `wget -c` + `bzip2 -t` 双校验；**判据是字节数和校验结果，不是 wget 的退出码**。
- 从 Git Bash 调 `wsl.exe` 时路径会被 MSYS 改写（`/mnt/d/...` → `C:/Program Files/Git/mnt/...`），
  要么加 `MSYS_NO_PATHCONV=1`，要么把命令写进 `.sh` 再调用；**改写后可能仍然返回 0**，
  所以每次都要验产物是否真的存在。
- 内联 `wsl.exe bash -c "V=...; echo \$V"` 里的变量会被外层吃掉，写脚本文件最省事。
- 本文档涉及的脚本必须是 LF 行尾，CRLF 会让 bash 在 shebang 处就失败。

## 装载顺序

`publish-ohos-rtc-call.ps1` 会把上面四个 `.so` 打进 HAR 的 `package/libs/armeabi-v7a/`；模型由宿主 HAP 的 rawfile 提供，两者都要齐，缺模型时 `RtcTtsController.init()` 会在 `getRawFileContent` 处失败。
