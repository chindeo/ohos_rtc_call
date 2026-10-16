# TTS 模型来源与原生库构建记录

模型与预构建 `.so` 都**不进 Git**（体积大、且与 `*.har` 一样按本地分发产物处理）。
没有这份记录，新环境无法重建可用的 TTS，所以这里是唯一权威来源，请按 sha256 校验后使用。

## 模型文件（matcha-icefall-zh-baker 首选档）

放置位置：宿主 HAP 的 `entry/src/main/resources/rawfile/matcha-icefall-zh-baker/`，四个文件缺一不可。

| 文件 | 字节数 | sha256 |
|---|---:|---|
| `model-steps-3.onnx` | 75,624,188 | `FF1CC7F7ABDEDC4EEEC668A4A0DC2E72A0C314C5637D5FCE885345B490BD08DE` |
| `vocos-22khz-univ.onnx` | 53,884,024 | `0574A135AA1DB2DE6E181050DB2EC528496CACD4A4701FC5D7FAF9F9804C0081` |
| `lexicon.txt` | 1,363,705 | `38B886D46AEFA50DA6322A64D72FD595D5F4FAE1051ADB160D647541B1E0A4A2` |
| `tokens.txt` | 19,591 | `56209B2BF609D5AC1D66EDE6DAE7BF5254BD3F8AA24C4A6823713D5B884D87BA` |

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
| `libsherpa_onnx.so`（本项目 napi shim） | 138,648 | `48fd705d1b6940ebf8bb2955aa7794649b61ad62d387502cdcb7d8befa7e1b5f` |
| `libsherpa-onnx-c-api.so` | 3,333,004 | `36fe763253fa5962a6d48a4eff25adfd5b829633176cc4e74068a4a0078e469f` |
| `libonnxruntime.so`（自研，非预构建） | 12,333,464 | `f1699d786e4af292359132e06950842996c337e1615256093e9f5d4df5d5fa68` |
| `libcargs.so` | 5,240 | `a90dbed7faa9eab26b5a432963b7e5bc7fecfaf042362e6058eed2b15e3bcb41` |

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

## 装载顺序

`publish-ohos-rtc-call.ps1` 会把上面四个 `.so` 打进 HAR 的 `package/libs/armeabi-v7a/`；模型由宿主 HAP 的 rawfile 提供，两者都要齐，缺模型时 `RtcTtsController.init()` 会在 `getRawFileContent` 处失败。
