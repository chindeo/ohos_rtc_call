# 手工安装测试和线上发布清单

## 目标版本

- 公共包：`@chindeo/ohos-rtc-call@0.1.4-rc3`
- 床旁验证分支：`5.0.1-SHIMeta`
- 主机验证分支：`v1.0_nurse_SHIMeta`

## 发布包预检

在 `ohos_rtc_call` 项目根目录执行：

```powershell
.\tools\publish-ohos-rtc-call.ps1
```

预检通过后会生成：

```text
dist\ohos-rtc-call-0.1.4-rc3.har
```

## 业务工程构建

如果验证的是尚未线上发布的公共包改动，先将业务工程中所有 `@chindeo/ohos-rtc-call` 依赖临时替换为本次生成的
HAR 或本地源码路径，例如：

```json5
"@chindeo/ohos-rtc-call": "file:<本机 harmony 工作目录>/ohos_rtc_call/dist/ohos-rtc-call-0.1.4-rc3.har"
```

床旁工程至少检查根目录、`common` 和 `entry` 模块的 `oh-package.json5`；主机工程至少检查 `nurse` 模块的
`oh-package.json5`。验证完成后再按线上发布结果恢复为正式版本号。

如果使用临时克隆的业务工程验证，先确认 `ohos_webrtc\libs` 下包含 `armeabi-v7a\libohos_webrtc.so` 和
`arm64-v8a\libohos_webrtc.so`。如果临时克隆缺少 `.so`，从本机床旁工程复制：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
Copy-Item -Recurse -Force `
  "$HARMONY_ROOT\5.0.1-SHIMeta\ohos_webrtc\libs" `
  <临时业务工程>\ohos_webrtc\libs
```

床旁：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
cd "$HARMONY_ROOT\5.0.1-SHIMeta"
.\tools\build-call-app.ps1 -BuildMode debug
```

主机：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
cd "$HARMONY_ROOT\v1.0_nurse_SHIMeta"
.\tools\build-nurse-app.ps1 -BuildMode debug
```

## 设备安装

床旁：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
cd "$HARMONY_ROOT\5.0.1-SHIMeta"
.\tools\install-call-app.ps1 -Target <device-ip>:5555
```

主机：

```powershell
$HARMONY_ROOT = "<本机 harmony 工作目录>"
cd "$HARMONY_ROOT\v1.0_nurse_SHIMeta"
.\tools\install-nurse-app.ps1 -Target <device-ip>:5555
```

## 手工验收点

### 通用启动和基础通话

- 启动页状态检查完成后，等待约 2 秒再进入主界面。
- 启动页长按期间不自动跳主界面，长按完成进入管理员设置。
- 从管理员设置返回启动页后，启动流程可恢复。
- WebRTC 主叫、被叫、接听、挂断流程正常。
- 屏幕接听默认免提，通话音量约 90%。
- 手柄接听默认非免提，通话音量约 40%。
- 通话中拿起 / 放下手柄的路由和挂断策略符合对应设备角色。
- 通话结束后恢复接听前音量。
- WebRTC / SIP 协议切换和 runtime config refresh 不打断当前通话。

### 床旁启动降级

- 业务接口不可访问但已有缓存配置时，床旁可进入主界面并保留通话能力。
- 使用缓存进入主界面时显示“网络异常，请检查网络”提示。
- 后续接口请求恢复成功后，网络异常提示可自动清除。
- 首次安装且没有成功缓存过床旁配置时，允许停留在启动页并提示必要数据缺失。

### 主机多床旁来电

- 两个床旁同时拨打主机时，主机列表显示两个独立条目，第二路保持待接听状态，不继承第一路接听状态。
- 主机右侧设备区域顶部固定显示本机信息；支持视频且本机视频可用时显示本机视频预览。
- 主机右侧设备区域下方只显示床旁列表，列表超出区域时可在列表区域内滚动，不再出现上下两套床旁列表。
- 点击主机列表中的床旁条目时，选中样式立即切换；仅选择条目不应把待接听来电改成已接听。
- 主机来电默认保持手动接听；即使配置中带自动接听标记，床旁拨入后也应先停留在待接听页面。
- 主机通话 UI 可通过临时版本标记和日志确认实际进入的是 WebRTC 主机组件，而不是 SIP 组件或旧页面。
- 主机收到 `c__answer` 或 `publish connected` 后不能直接进入通话中；点击接听后应先进入接听中 / 等待媒体状态。
- 主机只有在对应 `subscribe` 路收到对端音 / 视频 track，且从 `track.id` / `stream.id` 解析出的号码匹配当前床旁后，才显示通话中和保持按钮。
- 音频通话接听后，匹配到对应 `subscribe` 音频 track 即可进入通话中。
- 普通视频设备的视频通话接听后，必须匹配到对应 `subscribe` 视频 track 后才进入通话中；只收到音频 track 时保持接听中 / 等待视频，不显示保持按钮。
- 手表等仅音频设备的视频通话接听后，匹配到对应 `subscribe` 音频 track 即可进入通话中，不等待视频 track。
- 多床旁通话时，每接听一路床旁只建立并绑定该床旁的一路独立 `subscribe`，不能把其它床旁来电串成已接听状态。
- 主机左侧当前床旁详情按状态显示操作按钮：待接听显示接听，通话中显示保持，保持中显示恢复，并始终保留当前通话挂断。
- 主机床旁列表条目按待接听、通话中、保持中显示不同背景色，当前选中项额外显示边框高亮。
- 已接听通话条目显示通话中状态和保持按钮，不显示接听按钮。
- 待接听来电条目显示来电 / 待接听状态和接听按钮，不显示保持按钮。
- 按顺序执行“床旁 1 拨打 -> 主机接听 -> 床旁 2 拨打”时，床旁 1 保持已接听状态，床旁 2 保持待接听状态。
- 继续执行“主机接听床旁 2”后，两个通话条目的接听 / 保持 / 挂断按钮状态分别符合当前通话状态。
- 挂断第二路时只结束第二路，第一路仍保持原通话状态。
- 挂断第一路时只结束第一路，第二路仍保留并维持原来电或通话状态。
- 多路通话时主机通话列表显示“挂断全部”，点击后所有床旁通话同时结束。
- 多路通话时主机话筒放下触发“挂断全部”，所有床旁通话同时结束。
- 单通话接听后点击保持，条目切换为保持中；再次恢复后回到通话中。
- 多路通话中对当前活动通话点击保持 / 恢复，不应误改变其它床旁条目的保持状态。

## 线上发布

设备验收通过后，在 `ohos_rtc_call` 项目根目录执行：

```powershell
.\tools\publish-ohos-rtc-call.ps1 -Publish
```

发布后再更新床旁和主机业务工程依赖版本到 `0.1.4-rc3`，分别重新构建和安装验证。
