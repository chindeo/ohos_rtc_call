# 设备厂家适配说明

## 总原则

- 厂家能力必须通过公共 adapter 或 `RtcDeviceCapabilityManager` 暴露。
- 页面、业务组件、通话 controller 不直接散落 `@company/device_sdk`、`@ohos.shimeta`、`@mili/hardware_service_sdk` 等判断。
- 未确认厂家默认 WebRTC；只有明确支持 SIP 的设备才进入 SIP 路径。
- 厂家能力缺失时应降级并记录低敏日志，不能阻塞基础 WebRTC 通话。

## Dnake

- Dnake 可使用 Dnake SIP、DMsg、SIP 铃声、手柄、按键、IO 和设备 SDK 能力。
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
