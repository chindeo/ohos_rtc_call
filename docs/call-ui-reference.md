# 音视频通话 UI 参考实现说明

## 参考范围

本次界面以 Android `base/call-lib` 的实际布局和运行时可见性为准，只复刻 UI、交互状态和页面切换：

- 单路呼入：`call_fragment_incoming.xml`
- 单路呼出：`call_fragment_exhale.xml`
- 单路通话：`call_fragment.xml`、`call_view_main.xml`、`call_fragment_video_calling.xml`
- 多路呼入：`multi_call_fragment_incoming.xml`、`multi_include_call.xml`
- 多路通话：`call_view_abbreviation_camera.xml`、`MultiVideoCallingFragment.kt`、`VerticalCallStream2.kt`

不引入 Android 侧 RTC、MQTT、网关、设备控制或业务通信实现。

## 页面层级

通话页保持以下四层，后一层覆盖前一层：

1. 背景层：通话背景图，使用 `centerCrop` 对应的裁剪方式。
2. `callCenter`：本地和远端媒体流、音频头像占位及用户名标签。
3. `cvCenter`：通话计时和静音、免提、保持、挂断、挂断全部控制。
4. `llRoot_video_call`：呼入、呼出和接听等待覆盖层。

打开页面不等于接通。点击接听后进入连接中状态并显示媒体层和完整控制栏，只有目标 `subscribe` 媒体身份匹配并满足媒体条件后才切换为通话中。

## 尺寸和视觉

- 呼入/呼出主按钮：`120vp x 120vp`，距底部 `100vp`。
- 呼入拒接和接听按钮间距：中间各 `50vp`。
- 呼入/呼出按钮文字：`22fp`，距图标 `15vp`。
- 呼入名称：竖屏 `46fp`，横屏 `100fp`；呼出名称横竖屏均为 `46fp`。
- 呼入类型提示：`20fp`，距名称 `30vp`。
- 通话控制图标：`88vp x 88vp`，控制项间距 `30vp`。
- 控制容器：`#B3333333`，圆角 `40vp`，水平内边距 `50vp`，垂直内边距 `40vp`。
- 通话计时：`30fp`；音频用户名：`30fp`；视频用户名标签：`20fp`。
- 用户名标签背景：`#B3333333`，右下角 `20vp`，水平内边距 `25vp`，垂直内边距 `10vp`。
- 多路主画面与右侧栏比例：`75% / 25%`。
- 右侧缩略画面高度：`300vp`，外边距 `2vp`。
- 右侧缩略画面边框：选中 `#69F46E`，未选中 `#7E7F80`，宽 `3vp`，圆角 `3vp`。
- 多路呼入背景：`#212226`；两列网格，最多两行占满可视区域，奇数末项跨两列。
- 多路呼入名称 `38fp`，状态 `24fp`，操作图标 `70vp x 70vp`。

## 状态和可见性

- `INCOMING`：显示名称、邀请类型、拒接和接听；接听是否可点击由 `canAccept` 决定。
- `OUTGOING`：显示名称、等待提示和挂断。
- `CONNECTING`：显示媒体层和完整控制栏，状态文案为“连接中”，但不视为已接通。
- `CONNECTED`：显示媒体层和通话控制；视频未满足接通门禁时不得进入此状态。
- `HELD`：仅目标通话显示保持头像、保持文案和恢复按钮，其他通话不变。
- `visible=true` 但没有有效 `activeCall` 时不渲染通话背景，避免旧背景残留。
- 多路场景中，当前目标显示在主画面，其他目标显示在右侧缩略列表；选择目标只切换展示焦点。
- 静音、免提、保持及选中态均由状态模型回显，按钮点击不直接伪造最终状态。
- 护士站显示“免提”；床旁设备启用麦克风路由切换时显示“切麦”，该操作不得关闭播放扬声器。
- 转接和合并在参考运行时中保持隐藏，本次不实现。

## 媒体和关闭规则

- 本地 `publish` 流只更新本地画面，不触发接通页面切换。
- 单路音频通话的连接中、通话中和保持中媒体层使用音频头像占位和用户名，不依赖视频背景或远端视频 builder。
- 音频通话匹配到目标 `subscribe` 音频 track 后接通。
- 普通视频设备必须匹配到目标视频 track 后接通。
- 手表等仅音频设备的视频呼叫，匹配到目标音频 track 即可接通。
- 单路挂断只清理目标会话及其 renderer。
- 多路中单个目标断开后保留页面并选择剩余目标。
- 仅剩余会话为零或明确执行挂断全部时关闭整个通话页面。

## 资源

控制图标复用公共模块已有 `rtc_call_*` 资源。新增资源只来自参考项目实际使用的原图：

- `rtc_call_background.jpg`：`img_bg_call_landscape.jpg`
- `rtc_call_video_background.png`：`img_bg_videocall.png`
- `rtc_call_avatar.png`：`icon_call_head.png`
- `rtc_call_hold_avatar.png`：`icon_voice_call.png`
