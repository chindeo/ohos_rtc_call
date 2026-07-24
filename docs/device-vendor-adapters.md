# 设备厂家适配说明

## 总原则

- 厂家能力必须通过公共 adapter 或 `RtcDeviceCapabilityManager` 暴露。
- 页面、业务组件、通话 controller 不直接散落 `@company/device_sdk`、`@ohos.shimeta`、`@mili/hardware_service_sdk` 等判断。
- 未确认厂家默认 WebRTC；只有明确支持 SIP 的设备才进入 SIP 路径。
- 厂家能力缺失时应降级并记录低敏日志，不能阻塞基础 WebRTC 通话。

## Dnake

- Dnake 可使用 Dnake SIP、DMsg、SIP 铃声、手柄、按键、IO 和设备 SDK 能力。
- Dnake 看门狗的正常停止只结束进程内屏幕唤醒定时器，不能在后台、窗口销毁或普通退出时自动移除生产看门狗。
- 卸载受看门狗保护的宿主前，必须通过 `RtcDeviceCapabilityManager.releaseKeepAlive` 显式调用厂家 `removeDog`，确认成功后才能继续卸载。
- 卸载前解除属于维护动作；远程控制服务不能冒充业务 bundle 调用 `feedDog`，也不能静默改变设备的生产重启策略。
- WebRTC 模式必须关闭 Dnake SIP 铃声和 DMsg 干扰。
- SIP 模式下由公共 SIP runtime/controller 统一注册、拨号、接听、挂断、禁用和铃声开关语义。
- Dnake 按键和手柄事件只作为业务入口来源，最终仍调用公共通话接口。

## Shimeta

- Shimeta 能力通过 Shimeta adapter 接入，重点包括 MAC、开机自启、定时开关机、静默安装、唤醒/电源、LED、硬件按键和麦克风切换。
- Shimeta 固件上禁止调用 Dnake SDK。
- 兼容 SDK 限制或系统特权限制时，adapter 应提供可检测的降级结果，业务层不直接绕过公共能力入口。
- 设备厂家未知时可以通过 Shimeta MAC 能力做一次低风险探测；探测成功后切换到 Shimeta 路径并跳过 Dnake 初始化。
- 进程守护、静默安装、开机自启等特权能力必须在 adapter 内显式标记权限要求，业务层不能假定所有固件可用。

## Aurine

- Aurine 能力通过 Aurine adapter 接入，重点包括硬件服务绑定、网络、系统设置、电源、时间、LED、手柄、串口、刷卡和看门狗。
- Aurine 原始资料已归档到 `docs/archive/nurse/docs/aurine-hardware-services-ohos/`，公共实现只摘取必要能力，不复制示例站点结构到源码。
- 调用 Aurine 硬件能力前应检查硬件服务绑定状态，并通过 adapter 给出失败原因。

## 原始资料归档

- Dnake 原始文档：`docs/archive/vendor/dnake-v769-sdk.md`。
- Shimeta 原始文档：`docs/archive/vendor/shimeta-openharmony-device-api.md`。
- Aurine 原始文档：`docs/archive/vendor/aurine-hardware-services-ohos/`。
- 原始文档只作为能力查证来源；实现和协作规则以本项目顶层 docs 与 `AGENTS.md` 为准。

## Dnake 卸载前手工验收

1. 正常启动床旁应用，确认日志中 `keepAlive.success=true`。
2. 通过宿主维护入口请求 `prepareUninstall`，并使用唯一 `runId` 关联结果。
3. 只有日志出现同一 `runId` 的 `PREPARE_UNINSTALL_RESULT success=true` 后才卸载。
4. 卸载后等待超过设备原看门狗超时时间，设备不得因已移除的床旁 dog 重启。
5. 重新安装并启动床旁应用，确认看门狗重新注册，普通后台/窗口销毁没有调用 `removeDog`。
