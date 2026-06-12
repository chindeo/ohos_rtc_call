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

- 启动页状态检查完成后，等待约 2 秒再进入主界面。
- 启动页长按期间不自动跳主界面，长按完成进入管理员设置。
- 从管理员设置返回启动页后，启动流程可恢复。
- WebRTC 主叫、被叫、接听、挂断流程正常。
- 屏幕接听默认免提，通话音量约 90%。
- 手柄接听默认非免提，通话音量约 40%。
- 通话中拿起 / 放下手柄的路由和挂断策略符合对应设备角色。
- 通话结束后恢复接听前音量。
- WebRTC / SIP 协议切换和 runtime config refresh 不打断当前通话。

## 线上发布

设备验收通过后，在 `ohos_rtc_call` 项目根目录执行：

```powershell
.\tools\publish-ohos-rtc-call.ps1 -Publish
```

发布后再更新床旁和主机业务工程依赖版本到 `0.1.4-rc3`，分别重新构建和安装验证。
