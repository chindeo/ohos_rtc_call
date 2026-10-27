# TTS 模型来源与原生库构建记录

> 代码与 `libs/*/{libsherpa_onnx,libsherpa-onnx-c-api,libonnxruntime,libcargs}.so` 已迁到独立仓库
> `@chindeo/ohos-tts-sherpa`（`harmony/ohos_tts_sherpa`），本包不再携带。这里保留模型来源、sha256
> 与构建过程记录，作为历史取证依据。

模型**不进 Git**（放在宿主 HAP 的 `rawfile` 里，那边被 gitignore）；`libs/armeabi-v7a/*.so`
在本仓库是**被 git 跟踪的**（`git ls-files libs/` 可见），所以下面这些 sha256 是核对产物有没有被
覆盖过的依据，改完 shim 记得把新产物一起提交。
没有这份记录，新环境无法重建可用的 TTS，所以这里是唯一权威来源，请按 sha256 校验后使用。

## 模型文件（matcha-icefall-zh-baker 兜底档，无字母能力）

放置位置：宿主 HAP 的 `entry/src/main/resources/rawfile/matcha-icefall-zh-baker/`，四个文件缺一不可。
**2026-10-20 晚起它不再是默认档**，默认档是下面「中英混读模型」一节的 `matcha-icefall-zh-en`；
本节保留是因为 baker 音色更亮（22kHz）、且是字母需求妥协时的回退目标。

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

## arm64-v8a（视美泰 RK3576 大屏，2026-10-22）

`AIOT-3576E`（ShiMetaOS-1.0.0，api 20）是**纯 64 位**：`const.product.cpu.abilist=arm64-v8a`、
`abilist32` 取不到、`/system/lib/ld-musl-aarch64.so.1`、`appspawn` 是 ELF64。上面那套 32 位产物在这类机器上
装不上也加载不了，所以 `libs/arm64-v8a/` 单独出一份。**模型、`.fst`、`espeak-ng-data` 与架构无关，仍是同一份文件**。

| 文件 | 字节数 | sha256 |
|---|---:|---|
| `libsherpa_onnx.so`（napi shim） | 38,808 | `f61198b116ccdd9294f810a0d5eee7e5203fd5e003b09e152f3a59d8f571a9d1` |
| `libsherpa-onnx-c-api.so` | 3,556,896 | `0da619dc05c8bb39d21f85037f3ae6a9d56b475fc76dc2facda393ac7fc38603` |
| `libonnxruntime.so`（上游预构建，**非自研**） | 12,930,856 | `f9fd9080a10f2b93323d597225fbaa63d06f93b384bdfdd7285db9a9115fcc2b` |
| `libcargs.so` | 6,816 | `1233646eea5e5c60037454bccca55c0c255b3d29671d9f87082647dfc3c40503` |
| `libc++_shared.so`（**64 位必须随包**，见下） | 1,262,104 | `f823e88713d586dc23f4a653a5f0aec7a241f951ca48b8e88e9bd12e586a1035` |

**`libc++_shared.so` 为什么要随包**：这类机型只有 `/system/lib64/libc++_shared.so`，**HAP 应用命名空间解析不到它**，
于是一进页面就 `Cannot read property createAsync of undefined`，日志里是
`Error loading shared library libc++_shared.so: No such file or directory (needed by .../libs/arm64/libsherpa_onnx.so)`，
`SherpaShim` 一条日志都不会打（shim 自己没加载）。包里的 `libcurl_http.so` 同样依赖它，所以这一步也修掉了通话侧的隐患。
32 位那批不需要：它们的 `/system/lib` 里有系统副本，现在的产物在真机已验证多年。

**上游预构建 ORT 在 HAP 里能用（2026-10-22 装机实测，风险关闭）**：补上 `libc++_shared.so` 后
`SherpaShim` 四条 `dlopen ... ok` + `sherpa symbols bound`、`RtcTts stage=init ok=true create_ms=6174 threads=4 noiseScale=1 fsts=3`，
6 条话术全部 `attempts=1`、`rtf=0.20~0.39`。**不需要自研 arm64 onnxruntime**——32 位当年那个
`symbol not found` 在这台 64 位上没有重演。

内存账（同一台实测）：引擎未就绪时探针 Pss 128,877kB，就绪后 345,081kB → **TTS 净增约 211MB**，
其中只有 26MB 是文件映射，其余是 onnxruntime 权重/arena 的匿名堆。

重建（都只在 WSL 跑，Windows 侧 SDK 没有能出 ELF 的 clang）：

- sherpa + CLI：参考仓 `build-arm64-ohos.sh`。本机 WSL 连不上 github，`FetchContent` 不能重新下载，
  脚本改成从 `build-ohos-armeabi-v7a/_deps/*-src` 拷依赖源码树 + `-DFETCHCONTENT_FULLY_DISCONNECTED=ON`。
  aarch64 没有软浮点那条坑，`"+g,w"` 那个 Eigen 补丁不需要。
- shim：`bash tools/build-sherpa-shim.sh arm64-v8a`（默认仍是 `armeabi-v7a`，行为不变）。
- 版本基线不变：`libsherpa-onnx-c-api.so` 里 `strings` 得 `1.12.18`，shim 结构体仍按该 tag 的 `c-api.h`。

已验（CLI 直跑）：推 `/data/local/tmp/tts64` 后合成三条，**RTF 0.236~0.358**、
峰值约 22000/32767（非静音），SenseVoice 回读 `体温三十六点五度`、`二十一床正在呼叫`（fst 生效）全对，
`I、C、U、三床请到护士站` 的字母对。同一次进程启动含模型加载约 6 秒，比 32 位那批的 12~16 秒低。
之后又用 `example/tts-probe` 装成 HAP 验过一遍（见上一节），CLI 与 HAP 两条路都通。

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
   **64 位不适用这条**：那类机型只有 `/system/lib64/libc++_shared.so`，HAP 命名空间解析不到，
   必须把 `libc++_shared.so` 一起放进 `libs/arm64-v8a/` 随包分发，见上面「arm64-v8a」一节。
2. 结构体字段**必须逐字段**照 v1.12.18 的 `c-api.h:1019-1100` 抄，少一个字段不会编译报错，
   只会让后面的字段整体错位。本项目踩的是 `SherpaOnnxOfflineTtsZipvoiceModelConfig` 少了
   `target_rms`/`guidance_scale`（40 字节写成 32 字节），外层 `silence_scale` 因此读成 0，
   真机表现：`sherpa_onnx: --tts-silence-scale '<private>' is too small` → `Errors in config`
   → `SherpaOnnxCreateOfflineTts returned null`，应用侧只剩"TTS 未初始化"。
3. C API 结构体没有默认值，`max_num_sentences=1`、`silence_scale=0.2` 这两个上游给在 C++
   结构体里的默认值必须显式赋；`Reject()` 要记一条原生日志并 reject 真正的 `Error` 对象，
   否则宿主侧 `error.message` 打成 `undefined`，排查时看不出失败在哪一步。

## 中英混读模型（matcha-icefall-zh-en，2026-10-20 晚起为默认档）

**10-20 上午那次退回里，"参数带错"是真的，但"改对参数就能用"是我下结论下早了。** 端上当时沿用 baker 的
`DEFAULT_NOISE_SCALE=0.2`，而作者脚本用 1.0；把同一参数、同一句话**重复合成 6~12 次**重测
（`D:\tmp\tts\noise_sweep.py`、`noise_sweep2.py`，SenseVoice 回读判"与预期不符"）：

| noise_scale | 内容错误率 | 说明 |
|---|---|---|
| 0.2 | 17/18 | 系统性错，每次都错同一处——就是现场报的那批 |
| 0.5 | 4/18 | 最好的档位 |
| 0.6 / 0.7 / 0.8 | 9/36 · 11/36 · 10/36 | 25%~31% |
| 1.0（现出厂值） | 5/18 | 28% |
| 1.3 | 8/18 | 44% |

错的只有两类，且**每一档都会错**：`为您自动接听` 约一半错（字字接听/自自动接听/赠送接听）、
`体温36.5度` 约三分之一错成 三十四点五/三三六点五/三十点五；`21床正在呼叫` 在 0.5 以上全对。
把数字在文本层先转成汉字、不挂 fst，错率一模一样（4~5/12，错法也相同）——所以**不是 fst、也不是 sherpa
中文前端的问题，是模型采样本身不稳**；issue #2847 那条"作者脚本正常、换 sherpa 才有叠音"的怀疑方向，
在我们这颗模型上不成立。

定档要求（少一条会退回"每次都错"那种更糟的状态，但满足四条并不等于可用）：

1. `noise_scale` 取 0.5~1.0 这一段（现出厂 1.0；0.5 样本上最低，但和 0.8/1.0 的差距不足以作为改动依据）；
2. **必须挂 fst**，不挂时整句崩（`体温36.5度`→"体温 forty six five度"、`A10床`→"a 探装正正在呼叫"）；
3. 字母串用**分号**逐个枚举**并且首尾都要有标点**：`I;C;U;三床请到护士站`。少尾部那个标点会把字母和中文连读出多余鼻音，
   整串不拆（`ICU`）则 espeak 当成一个英文单词拼读；只用空格分隔会连着念成一串、还会丢字母。
   **2026-10-22 由顿号改成分号**：同一句各 8 次回读 + 现场耳朵，`I、C、U、…` 3585ms 且八次跑出七种结果，
   `I;C;U;…` 只要 2481ms、八次回读完全一致；`JHC` 省 1.26 秒、`PICC` 省 1.35 秒。
   逗号、无空格逗号、顿号、句号、问号、叹号都挤在 3.3~3.6 秒这一档，只有分号掉下来——
   为什么分号更短**机制没查明**（`;` 在 `tokens.txt` 里 id=2，字母段走 espeak 那一段解释不了），按实测用。
   **逐字母念的时长代价主要来自字母音素本身，`silence_scale` 压不掉**
   （0.2→0.05→0.01 实测 3721/3735/3735 毫秒，0 会被配置校验直接拒绝，合法区间 0.01~10）。
4. **语速锁定 1.0，两个方向都不行**：`speed=0.9` 把 `体温36.5度` 念成"先三六点五度"、`为您自动接听` 念成
   "自自动接听"；`1.1` 把 36.5 念成"十六点五度"（丢"三"），`1.2` 把 `21床` 念成"床站呼叫"、`10:05` 丢"五"。
5. **≥14 字且原文无标点的中文句子，在词与词之间插半角逗号，最多两刀**（`splitLongSentence`）。
   `二十三床患者张三呼叫护士站请尽快前往处理` 不切是 **16/16 每次必错**（错在床号之后的 者/患/张，
   真机耳朵也是"患、三没发音"），切成 `…张三,呼叫护士站,请尽快…` 后 8/8 只有一种回读，代价 +0.74 秒。
   两条边界同样是测出来的，别越过：**不能按字数硬切**（每 4 字一刀把"护士站/请"切断后模型会把字序读乱，
   回出现"护士战""情紧快"，12/12 仍全错还多花 2 秒）；**中文里别用分号**（同位置分号 8 次跑出 5 种结果，
   现场听到"前往处理"的"往"偶发漏读）。**数字块前后都不能插**：`体温、36.5度` 比不切更差（6/12→9/12，
   丢"六"），因为它和 `number-zh.fst` 打架；体温这类目前无解，维持原样。

遗留，别当已解决：**内容错误率 25%~30%，集中在数字和轻声音节，可调项已穷尽**（noise / speed / silence /
挂不挂 fst / 数字走 fst 还是走汉字都试过），没有"下一个参数"可找。上游也没有任何"matcha 数字读错已修复"
的记录，自训 Matcha 踩同一个坑见 #3683。剩下的出路只有两条：高危话术在 PC 上多跑几次挑正确样音预合成，
或者自己微调（投工之前先定"含数字/含字母/含轻声"的话术验收集和达标线）。声码器只有 16kHz，高频比 baker 闷；
`A10床` 过 `number-zh.fst` 念成"A**十**床"，现场已认可这个读法。

两档的差异（模型目录名、声码器 16k/22k、fst 是否带 `-zh`、`noise_scale`、语速是否可调）现在集中在
`RtcTtsController.ets` 的 `profileFor(modelDir)`，宿主只靠 `rawfile` 里放哪个目录来选档，不再散着改常量。
`data_dir` 按 `filesDir/<model>/espeak-ng-data/phontab` 是否存在才传，baker 没这目录就是空串
（shim 里 `empty() ? nullptr`，等价于不设）。工程里的 Baker 备份在 `D:\tmp\tts\models\baker-from-bed`
和 `baker-from-host`，zh-en 备份在同级 `zh-en-from-bed`/`zh-en-from-host`（两份逐文件字节数一致）。

换它的原因是 baker 只能念汉字：**给 `lexicon.txt` 补字母条目是无效的**（实测 52 行大小写条目、
`ABCDEFGHIJ` 仍然 `reason=empty_audio synth_ms=13`，字母在查词表之前就被中文前端丢了）。
zh-en 的英文走 **espeak-ng**，与词表无关。

包内文件（tar 79,033,838 字节，解压后约 93MB，另加声码器约 143MB 进 rawfile）：

| 文件 | 字节数 | 说明 |
|---|---:|---|
| `model-steps-3.onnx` | 75,717,082 | 与 baker 的 75,624,188 同级，算力同档 |
| `lexicon.txt` | 1,400,278 | 68,037 行，**以 ASCII 开头的键 0 条** |
| `tokens.txt` | 21,146 | 2,190 个 token，含 IPA/英文音素 |
| `espeak-ng-data/` | 355 个文件 | **必须随包分发**，`data_dir` 指向这个目录本身（sherpa 查 `<data_dir>/phontab`，指到父目录会得到 `phontab does not exist` 然后 create 返回 null） |
| `number-zh.fst` / `phone-zh.fst` / `date-zh.fst` | 64,482 / 88,630 / 59,154 | 文件名与 baker 不同，带 `-zh` |
| 声码器 | `vocos-16khz-univ.onnx` 53,882,848 | README 指定，22k 那只**不能用** |

逐文件 sha256（2026-10-20 按 `zh-en-from-bed` 实测；三个 `.fst` 与 baker 那三份**字节完全相同**，只是改了名）：

```
524286bf6cf11be74329ae1c682ac69e34d6860c2ea9fd1290319d561540b16a  model-steps-3.onnx
b599142a1fb8ff03de3e84ac35ff537c619e56f4267a6fe894851a42844acf9e  vocos-16khz-univ.onnx
599efdcdaff4df2a123ce988c2cb90abcd59b919ef609ce36eb587d68b7ca2c0  lexicon.txt
77fee8e5e5dd96b3547119e6159292c648e99e065c54c97777722e3ce710b9a4  tokens.txt
```

来源：`https://modelscope.cn/models/dengcunqin/matcha_tts_zh_en_20251010`（声学模型/词表/espeak-ng-data），
声码器走 `https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos-16khz-univ.onnx`。

接入要点：c-api 不用重编（`--matcha-data-dir` 已在库里），只重编了 shim 加 `dataDir` 字段；
`ensureModelFiles` 用 `ensureRawTree` 递归解 `espeak-ng-data`，解完在目录里落一个 `.extracted`
标记，第二次启动直接跳过（355 个文件首次解包要几十秒）。`rawfile` 只读，所以模型一律先解到
`ctx.filesDir` 再喂引擎。

## 语速（后台可配，出货模型已验证）

`generateAsync(handle, text, sid, speed)` 的 `speed` 是靠拉长 duration 实现倍率的（sherpa 内部
`length_scale = 配置值 / speed`，小于 1 就是放慢）。**这条旋钮只对 baker 有效，zh-en 档一律锁 1.0**：
2026-10-20 晚在 `noise_scale=1.0` 下重测 zh-en，`speed=0.9` 仍把 `体温36.5度` 念成"先三六点五度"、
`为您自动接听` 念成"自自动接听"，0.85 更差（"三三四点五度度"）；同批 1.0 全部正确。
所以"zh-en 不支持调速"这条判据**当时不是被参数冤枉的**，被冤枉的只有中文丢字那一半。

现在取值来自后台"参数设置"的 `tts.TextToSpeechSpeechRate`（病区级，注册后随 `/config/list` 下发），
链路：宿主 `refreshRuntimeConfig` → `parseSpeechRate(value)` → `RtcTtsController.setSpeed()`，
下一次合成生效。baker 档的真机试听（2026-10-20，测试页逐条听）：

| 取值 | 现场判定（仅 baker） |
| --- | --- |
| 0.7 | 不叠字，但停顿很差、听着费劲，不要用 |
| 0.9 | 流畅、不叠字不卡字，比 1.0 舒服，**baker 推荐值** |
| 1.0 | 正常（后台留空/填错时的回落值；**zh-en 档恒为此值**） |

调节按 0.05~0.1 一档试听即可，0.01 的差别人耳在这条模型上分不出来。两端管理员设置里的 TTS 测试页
会在顶部只读显示**引擎实际在用**的语速；zh-en 档下后台填什么都显示 1，日志给一条
`stage=speed value=1 model_locked=true`，免得现场以为参数没下发。"无法播报英文字母"那句提示随默认档切到
zh-en 一起撤掉。

取值口径在 `tts/RtcSpeechRate.ets`（单独成文件是为了能被 Hypium import，控制器本体挂着 `libsherpa_onnx.so`
加载不了）：空/非数/越界一律回落 1.0，允许区间 0.5~2.0。后台填 `0` 或 `7`（少打小数点）不会把播报念成噪音。

## 停顿稳定性（noise_scale）

matcha 是扩散模型，`noise_scale` 越小采样越稳、但内容越容易丢/叠音节，**两个模型的最优值相反，不能共用**：

| 档 | 出厂 `noise_scale` | 依据 |
|---|---|---|
| `matcha-icefall-zh-baker` | 0.2 | 0.66/0.33/0.2 现场对比，`.93` 与 `.104` 判"几乎没区别"，0.2 听感认可 |
| `matcha-icefall-zh-en` | 1.0 | 0.2 下丢字/错数字（见上面中英档那节的扫参表），作者脚本硬编码 1.0 |

值仍可通过 `RtcTtsConfig.noiseScale` 由宿主覆盖，不传就用上面按档的默认值。句内停顿是模型自身
分词/韵律造成的，`tts-silence-scale` 只管句间，压不住；扫参也确认了 `silence_scale` 不影响文字对错。

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
