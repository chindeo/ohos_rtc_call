# 设备厂家适配说明

## 总原则

- 厂家能力必须通过公共 adapter 或 `RtcDeviceCapabilityManager` 暴露。
- 页面、业务组件、通话 controller 不直接散落 `@company/device_sdk`、`@ohos.shimeta`、`@mili/hardware_service_sdk` 等判断。
- 未确认厂家默认 WebRTC；公共包只保留 WebRTC 一条通路（SIP 已于 2026-10-27 移出）。
- 厂家能力缺失时应降级并记录低敏日志，不能阻塞基础 WebRTC 通话。

## Dnake

- Dnake 可使用 DMsg、厂家铃声、手柄、按键、IO 和设备 SDK 能力；SIP 相关能力已不在公共包内。
- Dnake 看门狗的正常停止只结束进程内屏幕唤醒定时器，不能在后台、窗口销毁或普通退出时自动移除生产看门狗。
- 卸载受看门狗保护的宿主前，必须通过 `RtcDeviceCapabilityManager.releaseKeepAlive` 显式调用厂家 `removeDog`，确认成功后才能继续卸载。
- 卸载前解除属于维护动作；远程控制服务不能冒充业务 bundle 调用 `feedDog`，也不能静默改变设备的生产重启策略。
- WebRTC 通话期间必须关闭 Dnake 厂家铃声和 DMsg 干扰，避免厂家通道抢走音频和信令。
- 厂家按键和手柄事件只作为业务入口来源，最终仍调用公共通话接口。

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

## JHC（主机手柄）

- 主事件源：厂家模块 `jhc-handset-napi`（原生 `libhandset.so` + `JhcHandsetMonitor` 封装），
  在应用进程内直读 `/dev/input/event*` 的 `EV_SW/SW_HEADPHONE_INSERT`，设备名按
  `Headphones/Headset` 匹配（实机 `audiocodec Headphones` = `event3`），不写死编号。
  接入位置仍是主机 `NurseMainHome`，回调汇入既有的 `applyHandsetState` 单一入口。
- 为什么事件路径还不通、但这条路可用：`audio_host` 长期 `EVIOCGRAB` 独占该节点，
  事件读不到（应用侧读返回 13900010）；`EVIOCGSW` 这个 ioctl **不受 grab 影响**，
  模块按 100ms tick 校验开关位、变化才上报，所以拿到的是电平而不是边沿。
  电平意味着冷启动就能定基线（"启动时话筒已被拿起"不再需要等一次新事件），
  厂家哪天放弃独占后事件路径自动生效、无需改代码。
- 兜底顺序：原生通道（`getLastNativeRc()===0`）→ 轮询
  `/sys/module/snd_soc_sunxi_common/parameters/jack_state`（400ms、首帧只建基线、连续两次同值才认）。
  原生通道返回 `-13`（SELinux/节点权限）或 `-2`（设备名未匹配）时轮询顶上，不能只靠
  `JhcHandsetMonitor` 自带的 `AudioRoutingManager` 兜底——这台板子 HAL 不上报设备，
  该通道实测 0 回调、`getDevices()` 恒为 `out=[2]SPEAKER in=[15]MIC`。
- 构建门槛：JHC api23 主机是 64 位内核 + **32 位应用运行时**（已装包只抽出 `libs/arm`），
  `externalNativeOptions.abiFilters` 必须带 `armeabi-v7a`，只写 `arm64-v8a` 会出现
  "页面能开、`import handset` 得到 undefined"。
- 通路真源不变：界面显示哪一路仍以 HAL 写的 `/sys/kernel/mic_switch/select` 为准，
  每 tick 对一次账，不一致只打一条日志；应用不写通路（HAL 未实现 `UpdateAudioRoute`）。
- 日志前缀统一 `话筒状态-`，真机 `grep -a 话筒状态-` 即可看全链路；来源取值新增
  `原生手柄监听`，与既有的 `轮询`/`dnake按键`/`deviceChange` 并列。

## 原始资料归档

- Dnake 原始文档：`docs/archive/vendor/dnake-v769-sdk.md`。
- Shimeta 原始文档：`docs/archive/vendor/shimeta-openharmony-device-api.md`。
- Aurine 原始文档：`docs/archive/vendor/aurine-hardware-services-ohos/`。
- 原始文档只作为能力查证来源；实现和协作规则以本项目顶层 docs 与 `AGENTS.md` 为准。

## JHC 手柄手工验收

1. 启动后第一行必须是通道判定：`原生手柄监听已启用, nativeRc=0, channel=native jack event`；
   出现 `nativeRc=-13/-2` 就是原生通道没通，此时必须同时看到"轮询顶上"那一行，否则这台设备没有任何手柄事件源。
2. 拿起/放下各一次：日志顺序 `话筒状态-基线` → `话筒状态-变化生效, 来源=原生手柄监听, pickedUp=true`，
   一次动作只有一行"变化生效"；出现"忽略重复状态"或两行同值即为抖动/双触发。
3. 床旁呼主机 → 拿起手柄接听、放下挂断，连续三次全对。
4. 手柄已被拿起（压在听筒上）时冷启动：只应有基线行，**不得自动接听**；
   这一条是原生通道上线后的新风险点，厂家模块 `getState()` 会在启动瞬间就把"拿起"报上来。
5. 未挂好检测不受影响：拿起不放满 30 分钟仍出常驻提示（见 `host-bed-project-notes.md`）。
6. 非 JHC 设备（Dnake 主机、床旁）：只有一条"轮询不启用/原生通道不启用"，
   Dnake 按键通路与通话流程不受影响。
7. 装机后先确认 `libs/arm/libhandset.so` 真的被抽出来（`ls /data/app/el1/bundle/public/<包名>/libs/`）；
   没有 `libs/` 或里面没有 `libhandset.so` 就是 ABI 漏了 `armeabi-v7a`，别看界面正不正常。

## Dnake 卸载前手工验收

1. 正常启动床旁应用，确认日志中 `keepAlive.success=true`。
2. 通过宿主维护入口请求 `prepareUninstall`，并使用唯一 `runId` 关联结果。
3. 只有日志出现同一 `runId` 的 `PREPARE_UNINSTALL_RESULT success=true` 后才卸载。
4. 卸载后等待超过设备原看门狗超时时间，设备不得因已移除的床旁 dog 重启。
5. 重新安装并启动床旁应用，确认看门狗重新注册，普通后台/窗口销毁没有调用 `removeDog`。
