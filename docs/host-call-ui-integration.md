# 音视频通话 UI 宿主对接文档

## 1. 对接范围

本模块已经包含单路和多路音视频通话 UI、页面状态模型以及 WebRTC 通话运行时。宿主项目只负责：

- 提供信令地址、本机身份和设备角色。
- 在页面生命周期内创建、启动和销毁 `RtcHostCallController`。
- 使用 `RtcHostCallController.onUiModelChange()` 驱动页面。
- 将 UI 操作转发给同一个控制器实例。
- 提供本地、主远端和按会话远端视频的 `XComponent`。
- 根据 `model.visible` 决定通话页是否继续显示或关闭。

宿主不得根据按钮点击自行把通话改成已接通，也不得另建一套通话状态。

## 2. 依赖和导出

宿主安装：

```shell
ohpm install @chindeo/ohos-rtc-call
```

宿主还需提供兼容的 `@ohos/webrtc`，并配置相机、麦克风和网络权限。

主要导出：

```ts
import {
  RtcCallDeviceRole,
  RtcCallMode,
  RtcHostCallController,
  RtcHostCallUiModel,
  RtcHostMultiCallLayout
} from '@chindeo/ohos-rtc-call'
```

`RtcHostMultiCallLayout` 是兼容入口，内部使用 `RtcReferenceCallLayout`。现有宿主不需要更换组件名。

## 3. 创建控制器

控制器应由通话宿主页持有，并且同一页面只创建一个实例。

```ts
private callController: RtcHostCallController = new RtcHostCallController({
  serverUrl: this.rtcServerUrl,
  local: {
    number: this.localNumber,
    displayName: this.localName,
    clientType: this.localClientType
  },
  appVersion: 'host_webrtc',
  localVideoEnabled: true,
  deviceRole: RtcCallDeviceRole.HOST,
  onConnected: (sessionKey: string) => {
    console.info('rtc media connected: ' + sessionKey)
  },
  onError: (message: string) => {
    console.error('rtc call error: ' + message)
  }
})
```

部署相关的地址、号码和身份信息必须从宿主配置注入，不能写入公共模块或提交到仓库。

### 床旁设备“切麦”

护士站使用默认“免提”：

```ts
deviceRole: RtcCallDeviceRole.HOST
```

床旁设备需要把同一位置显示为“切麦”时：

```ts
deviceRole: RtcCallDeviceRole.BED,
speakerActionLabel: '切麦',
speakerActionIsMicSwitch: true,
onMicSwitch: async () => {
  await this.switchMicrophoneRoute()
}
```

启用 `speakerActionIsMicSwitch` 后，按钮不会修改播放扬声器状态，只调用宿主的 `onMicSwitch`。

## 4. 生命周期和状态订阅

```ts
@State private callUiModel: RtcHostCallUiModel = new RtcHostCallUiModel()
private unsubscribeCallUi?: () => void

aboutToAppear(): void {
  this.unsubscribeCallUi = this.callController.onUiModelChange(
    (model: RtcHostCallUiModel) => {
      this.callUiModel = model
      if (!model.visible) {
        this.closeCallPageWhenAppropriate()
      }
    }
  )
  this.callController.start()
}

aboutToDisappear(): void {
  this.unsubscribeCallUi?.()
  this.unsubscribeCallUi = undefined
  this.callController.dispose()
}
```

注意：

- `start()` 内部具有重复调用保护，但宿主仍应在明确的生命周期节点调用。
- `dispose()` 会释放监听、WebRTC 会话和按会话视频 Surface。
- 多路通话中单个目标挂断时 `model.visible` 仍为 `true`，宿主不能直接关闭页面。
- 仅当没有剩余通话，或明确执行挂断全部后，才关闭通话页面。

## 5. 视频画面

### 本地和当前远端画面

```ts
@Builder
LocalVideoSurface() {
  XComponent({
    id: 'rtcLocalVideo',
    type: XComponentType.SURFACE,
    controller: this.callController.getLocalVideoSurfaceController().getController()
  })
    .width('100%')
    .height('100%')
}

@Builder
RemoteVideoSurface() {
  XComponent({
    id: 'rtcRemoteVideo',
    type: XComponentType.SURFACE,
    controller: this.callController.getRemoteVideoSurfaceController().getController()
  })
    .width('100%')
    .height('100%')
}
```

### 多路远端缩略画面

每个 `sessionKey` 必须使用独立 Surface：

```ts
@Builder
SessionRemoteVideoSurface(sessionKey: string) {
  XComponent({
    id: 'rtcRemoteVideo-' + sessionKey,
    type: XComponentType.SURFACE,
    controller: this.callController
      .getSessionRemoteVideoSurfaceController(sessionKey)
      .getController()
  })
    .width('100%')
    .height('100%')
}
```

会话结束时控制器只解绑该 `sessionKey` 对应的 track 和 renderer，不影响其他通话。

## 6. 页面挂载

```ts
RtcHostMultiCallLayout({
  model: this.callUiModel,
  localVideoBuilder: this.LocalVideoSurface,
  remoteVideoBuilder: this.RemoteVideoSurface,
  sessionRemoteVideoBuilder: this.SessionRemoteVideoSurface,
  onAccept: (sessionKey: string) => {
    this.callController.accept(sessionKey)
  },
  onHangup: (sessionKey: string) => {
    this.callController.hangup(sessionKey)
  },
  onHangupAll: () => {
    this.callController.hangupAll()
  },
  onHold: (sessionKey: string) => {
    this.callController.hold(sessionKey)
  },
  onResume: (sessionKey: string) => {
    this.callController.resume(sessionKey)
  },
  onSelect: (sessionKey: string) => {
    this.callController.select(sessionKey)
  },
  onMute: () => {
    this.callController.toggleMute()
  },
  onSpeaker: () => {
    this.callController.toggleSpeaker()
  }
})
.width('100%')
.height('100%')
```

按钮回调只发起操作。静音、免提、保持、接通和挂断后的最终页面状态，必须等待下一次 `onUiModelChange()` 回显。

## 7. 发起通话

```ts
this.callController.startCall({
  number: targetNumber,
  displayName: targetName,
  clientType: targetClientType
}, RtcCallMode.VIDEO)
```

语音通话使用 `RtcCallMode.AUDIO`。呼入会话由控制器接收信令后自动加入 UI 模型，宿主不需要手工创建呼入卡片。

## 8. 接通门禁

页面状态遵循以下规则：

| 阶段 | UI 行为 |
| --- | --- |
| `INCOMING` | 显示呼入覆盖层和接听、拒接按钮 |
| `OUTGOING` | 显示呼出等待覆盖层 |
| `CONNECTING` | 点击接听后显示媒体层和完整控制栏，状态仍为“连接中” |
| `CONNECTED` | 目标 `subscribe` track 身份匹配且媒体条件满足后显示通话页 |
| `HELD` | 只更新目标通话的保持头像和恢复按钮 |

接通判定不能使用以下事件代替：

- 页面已经打开。
- 用户点击接听按钮。
- 收到 `c__answer` 信令。
- 本地 `publish` 已连接。
- 任意一个 WebRTC 连接状态变为 connected。

普通视频设备需要匹配到目标视频 track；手表等仅音频设备即使发起视频呼叫，匹配到目标音频 track 即可接通。
媒体状态回调中的 `sessionKey`、`sessionId`、`uid` 和目标号码会归一到同一路业务会话；归一失败时不得伪造接通。

## 9. 控制器接口

| 接口 | 用途 |
| --- | --- |
| `start()` | 启动注册和 WebRTC 运行时 |
| `startCall(target, mode)` | 发起语音或视频通话 |
| `accept(sessionKey)` | 接听目标通话，只进入连接中 |
| `select(sessionKey)` | 切换多路主画面 |
| `hold(sessionKey)` | 保持目标通话 |
| `resume(sessionKey)` | 恢复目标通话 |
| `hangup(sessionKey)` | 只挂断目标通话 |
| `hangupAll()` | 挂断全部通话 |
| `toggleMute()` | 切换本机静音 |
| `toggleSpeaker()` | 切换免提，或执行宿主切麦回调 |
| `onUiModelChange(listener)` | 唯一 UI 状态输入 |
| `getSessionRemoteVideoSurfaceController(sessionKey)` | 获取指定会话的远端视频 Surface |
| `dispose()` | 释放页面持有的运行时资源 |

多路场景调用 `accept`、`hold`、`resume`、`hangup` 和 `select` 时必须传入明确的 `sessionKey`。

## 10. 对接验收

至少验证：

1. 单路呼入、呼出、语音通话和视频通话页面。
2. 点击接听后先显示连接中，目标媒体满足门禁后才显示通话页。
3. 多路呼入两列网格及奇数末项跨列。
4. 多路主画面切换和右侧独立视频缩略图。
5. 单个会话保持、恢复和挂断不影响其他会话。
6. 最后一个会话结束后才关闭页面。
7. 静音、免提和切麦状态由模型回显。
8. 横竖屏切换后无拉伸、遮挡和控制栏错位。
9. 页面退出后摄像头、麦克风、track 和 Surface 均已释放。

视觉尺寸和参考来源见 [音视频通话 UI 参考实现说明](call-ui-reference.md)，完整手工检查项见 [手工测试与发布](manual-test-and-publish.md)。
