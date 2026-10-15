# 端侧离线 TTS 接入

## 目标 / 非目标

- 目标：在床旁 + 主机设备上，通过 `RtcTtsController` 用本地 sherpa-onnx Matcha 模型合成并播放中文播报，无网络依赖。
- 非目标：不做多音色切换、不做二次 DSP 处理、不做流式；本轮只跑通 ANNOUNCE/BROADCAST/CALL 三条播报链路。

## 首选档

- 模型：`matcha-icefall-zh-baker` + `vocos-22khz-univ.onnx`（~128MB）。
- 参数：`noiseScale=0.33`、`lengthScale=1.0`、`numThreads=4`。
- 音频链路：napi `sherpa.generate` → Float32 PCM → 落 wav → `AVPlayer` 播放。

## 触发点

1. MQTT `ANNOUNCE`：护理广播（`MqttMessageHandler`）。
2. MQTT `BROADCAST`：床旁 / 走廊广播。
3. MQTT `CALL`：呼叫文本播报（可选，避免与铃声冲突时关闭）。

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
