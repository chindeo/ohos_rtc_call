# 音视频统一维护路线图

## 目标

- 主机、床旁的音视频通话能力统一沉淀到 `@chindeo/ohos-rtc-call`。
- 业务项目只保留入口触发、业务数据适配、设备配置注入和页面挂载点。
- 任意音视频缺陷优先在公共包修复，再通过版本或本地 HAR 同步到主机、床旁。

## 当前边界

- 公共包维护：call-gateway WebSocket 生命周期、WebRTC/SIP 状态模型、通话 UI 投影、铃声、音频路由、SDP/ICE 路由、设备能力 adapter、接口环境配置弹窗。
- 业务项目维护：业务接口、MQTT 收发、首页入口、硬件事件来源、业务弹窗、具体厂家 SDK 依赖注入。
- 公共包不内置业务地址、账号、密码、MAC、设备 ID、接口域名、设备 IP 或本机路径。

## 路线图

### P0 盘点与接口冻结

- 冻结公共入口：`RtcCallService`、`RtcCallViewState`、`RtcHostCallController`、`RtcDeviceCapabilityManager`、`RtcRuntimeConfigCoordinator`。
- 业务层只通过配置和回调接入：本机信息、被叫列表、权限结果、MQTT `refreshConfig`、硬件按键和手柄事件。

### P1 WebRTC 能力统一

- 统一 WebSocket 注册、`c__invite/c__answer/c__candidate/c__hangup/c__offline/c__broadcast` 处理。
- `uid/commonRequest.uuid` 是业务通话主键；`rtcUID + channelType` 是 RTC 通道绑定字段。
- `publish` 是共享上行资源，`subscribe` 是目标通话下行资源；多通话操作必须按目标 `uid` 执行。
- WebRTC 铃声、低时延音频参数、SDP 优化、stats 采样和日志节流由公共包维护。
- WebRTC 铃声固定走公共包资源和铃声互斥控制，不播放业务配置里的后台 `music` URL 或 MP3 铃声。
- WebRTC 信令连接必须有注册 URL 构建、连接去重、注册状态、`<__>` 分包解析、原始信令发送和错误回调。
- 视频通话入口、`isVideo` 信令、本地摄像头 track、远端 video track 渲染由公共包统一；默认视频参数采用低码率优先策略。
- 铃声资源按场景统一：普通呼入、外呼等待、转接等待、保持、特殊护理、蓝码、卫生间呼叫分别使用公共资源，不由业务项目各自拼装。

### P2 SIP 和厂家能力统一

- SIP/Dnake SDK 只允许 Dnake 厂家路径使用；Shimeta、Aurine、Unknown 默认 WebRTC，除非专用 adapter 明确支持。
- SIP 模式启用 Dnake DMsg 与 SIP 铃声；WebRTC 模式关闭 Dnake SIP 铃声和 DMsg 干扰。
- 厂家能力通过公共 adapter 暴露 MAC、按键、手柄、LED、重启、关机、开机自启、静默安装、看门狗等能力。
- Dnake SIP 默认配置由公共包统一维护，包括 `deviceType=10002`、默认响铃时长 `30s`、禁用响铃时长 `0s`。
- 业务项目只注入真实厂家 SDK runtime；公共 SIP controller 统一拨号、接听、挂断、禁用和铃声开关语义。
- 公共包的 Dnake SIP runtime 不直接依赖业务项目 SDK；业务项目只提供薄 adapter 注入真实 `DeviceSdk` 调用。

### P3 通话 UI 抽离

- 主机保留多人通话布局，床旁保留单床旁通话布局，差异通过 `deviceRole` 和 UI 投影控制。
- 保持/恢复按钮仅主机主动显示；床旁仍能接收远端保持状态并进入保持画面。
- 通话状态提示、管理员长按倒计时、音量条和通话动作按钮由公共表现模型统一生成。

### P4 运行时配置适配

- `call.rtcServerHost` 变化触发 WebRTC/SIP 协议切换和重新注册。
- `call.micSwitching` 只触发麦克风路由调整，不重复触发通话注册。
- MQTT 和接口请求留在业务项目，公共包只消费标准化配置对象和 changedKeys。

### P5 主机/床旁替换接入

- 两端只从 `@chindeo/ohos-rtc-call` 引入音视频服务、UI、协议切换和设备能力。
- 主机首页按钮、床旁首页按钮、业务 MQTT 弹窗、硬件按键仍作为业务入口保留。
- 两端锁定同一公共包版本，不允许一端长期本地改实现而另一端不同步。
- 床旁 Dnake 呼叫按键兼容 `key=2` 或 `key=4` 且 `onoff=1` 触发呼叫，`onoff=0` 只作为释放事件，不重复呼叫。
- 管理员设置页应监听 WebRTC/SIP 通话可见状态；来电或拨号时自动关闭设置页，避免覆盖通话界面。
- 独立通话应用曾作为床旁历史方案，短期复制 native WebRTC host 风险较高；当前主线仍是把通话能力沉淀到公共包并由业务项目挂载。

### P6 删除重复代码

- 删除主机/床旁中已被公共包替代的 WebRTC、SIP、通话 UI、模型、常量和铃声重复实现。
- 删除业务项目中的临时路径依赖和旧文档副本。
- 本项目生成的 `ohos-rtc-call-*.har` 不提交到业务项目仓库。

### P7 验证和发布

- 主机、床旁真机覆盖 WebRTC 呼入/外呼、SIP 呼入/外呼、协议热切换、保持/恢复、多通话挂断、视频通话和音频路由。
- 发布门禁：主机和床旁真机验收通过后再发布或固化联调 HAR。
- 文档、CHANGELOG、手工验收清单随公共 API 或接入口径变化同步更新。

## 完成标准

- 主机和床旁没有两套音视频通话实现。
- 通话协议判断、WebRTC/SIP 状态机、铃声、音频路由、通话 UI 和设备能力均由公共包维护。
- 两端只保留业务数据适配和入口触发代码。
- 后续音视频缺陷只需修改公共包并同步版本即可覆盖两端。
