# 视美泰 OpenHarmony 设备能力文档

## 来源与范围

本文整理当前项目已知的视美泰设备能力，来源包括用户提供的 ShowDoc 片段，以及 `5.0.1-SHIMeta` 历史提交中的既有对接代码。ShowDoc 页面需要验证码，后续新增接口以导出的原始文档为准。

适用场景：
- 视美泰固件设备上的系统能力调用。
- 与狄耐克 `@company/device_sdk` 分流，避免不同厂家 SDK 混用。
- 主机、床旁音视频与硬件能力统一适配。

## 模块声明

项目中使用系统扩展模块：

```ts
import shimeta from '@ohos.shimeta'
```

当前已知声明：

```ts
declare module '@ohos.shimeta' {
  namespace shimeta {
    function net_getMacAddress(type: string): string
    function sys_setSystemBootApp(app_param: string): number
    function sys_getSystemBootApp(): string
    function sys_setAutoPowerOnOff(
      enable: number,
      week: string,
      onHour: number,
      onMinute: number,
      offHour: number,
      offMinute: number
    ): number
    function sys_getAutoPowerOnOff(): Promise<string>
    function sys_doSilentInstallApp(hapPath: string, isRun: number, bundleName: string): number
  }

  export default shimeta
}
```

## 获取网卡 MAC

函数：

```ts
net_getMacAddress(type: string): string
```

说明：读取指定网卡 MAC。历史实现优先读取 `eth0`，失败后尝试 `eth1`。

参数：
- `eth0`：以太网。
- `eth1`：以太网 1。
- `wlan0`：WIFI，当前文档标注暂不支持。

示例：

```ts
const mac = shimeta.net_getMacAddress('eth0')
```

接入要求：
- 统一去除 `:`、`-` 和换行，并转为大写。
- 过滤空值、`000000000000`、`020000000000` 等无效 MAC。
- 视美泰设备优先用该接口或硬件服务读取 MAC；狄耐克设备继续使用 `DeviceSdk.getNetApi()`。

## 设置开机自启应用

函数：

```ts
sys_setSystemBootApp(app_param: string): number
```

说明：设置需要开机自启的应用。

参数 `app_param` 由三部分组成：

```text
Ability类名/包名/模块类型或模块名
```

示例：

```text
com.ohos.settings.MainAbility/com.ohos.settings/phone
```

取消开机自启：

```ts
const ret = shimeta.sys_setSystemBootApp('default')
```

当前应用参数可通过 `bundleManager` 获取：

```ts
import bundleManager from '@ohos.bundle.bundleManager'
import shimeta from '@ohos.shimeta'

async function setCurrentAppBoot(bundleName: string): Promise<number> {
  const flags =
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_ABILITY |
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE
  const info = await bundleManager.getBundleInfo(bundleName, flags, 100)
  const abilityName = info.hapModulesInfo[0].mainElementName
  const moduleName = info.hapModulesInfo[0].name
  const param = `${abilityName}/${bundleName}/${moduleName}`
  return shimeta.sys_setSystemBootApp(param)
}
```

返回值：`number`，表示调用结果，具体错误码以视美泰文档为准。

## 获取开机自启应用

函数：

```ts
sys_getSystemBootApp(): string
```

说明：获取当前设置的开机自启应用参数。

示例：

```ts
const currentBootApp = shimeta.sys_getSystemBootApp()
```

建议用法：
- 设置前先读取当前值，避免重复写入。
- 如果返回值已等于当前应用参数，不再调用 `sys_setSystemBootApp`。
- 如果需要取消，调用 `sys_setSystemBootApp('default')`。

## 设置定时开关机

函数：

```ts
sys_setAutoPowerOnOff(
  enable: number,
  week: string,
  onHour: number,
  onMinute: number,
  offHour: number,
  offMinute: number
): number
```

说明：设置设备定时开关机。

参数：
- `enable`：`1` 打开，`0` 关闭。
- `week`：7 天重复配置，格式为数组字符串，第一位为星期日，`1` 表示设置，`0` 表示不设置。例如 `1,1,1,1,1,1,1` 表示每天重复。
- `onHour` / `onMinute`：开机时间，24 小时制。
- `offHour` / `offMinute`：关机时间，24 小时制。

示例：

```ts
import shimeta from '@ohos.shimeta'

const week = [1, 1, 1, 1, 1, 1, 1]
const ret = shimeta.sys_setAutoPowerOnOff(1, week.toString(), 9, 30, 22, 0)
```

约束：
- 不设置重复、只设置一次时，关机时间必须在当前时间之后。
- 关机时间与当前时间需要间隔 3 分钟以上。
- 开机时间与关机时间之间需要间隔 3 分钟以上。
- 文档错误码中还说明当前时间与开机时间需要间隔 6 分钟以上。

错误码：

| 变量名 | 错误码 | 说明 |
| --- | ---: | --- |
| `SET_SUCCESS` | `0` | 成功 |
| `ERROR_UNKNOWN` | `-1` | 错误 |
| `ERROR_CONFIG` | `-2` | 参数有误 |
| `ERROR_EXCEPTION` | `-5` | 异常 |
| `ERROR_TIME_PASSED` | `100` | 设置时间已过 |
| `ERROR_COMPARE_ON_OFF_TIME` | `101` | 开机时间和关机时间没有相差 3 分钟 |
| `ERROR_COMPARE_NOW_OFF_TIME` | `102` | 当前时间和关机时间没有相差 3 分钟 |
| `ERROR_COMPARE_NOW_ON_TIME` | `103` | 当前时间和开机时间没有相差 6 分钟 |

## 获取定时开关机信息

函数：

```ts
sys_getAutoPowerOnOff(): Promise<string>
```

说明：获取定时开关机配置，返回 Promise JSON 字符串。

示例：

```ts
import shimeta from '@ohos.shimeta'
import { BusinessError } from '@ohos.base'

shimeta.sys_getAutoPowerOnOff()
  .then((data: string) => {
    console.debug('sys_getAutoPowerOnOff data:' + data)
    const json = JSON.parse(data) as Record<string, Object>
    const enable = Number(json.enable)
  })
  .catch((err: BusinessError) => {
    console.error(`error message: ${err.message}, error code: ${err.code}`)
  })
```

返回示例：

```json
{"enable":"1","offHour":"15","offMinute":"49","onHour":"15","onMinute":"53","week":"1,1,1,1,1,1,1"}
```

## 静默安装应用

函数：

```ts
sys_doSilentInstallApp(hapPath: string, isRun: number, bundleName: string): number
```

说明：静默安装应用。

参数：
- `hapPath`：待安装应用所在路径，必须是系统绝对路径，不能使用应用沙箱路径。
- `isRun`：安装后是否启动应用，`1` 启动，`0` 不启动。
- `bundleName`：需要启动的包名。

示例：

```ts
import shimeta from '@ohos.shimeta'

shimeta.sys_doSilentInstallApp('/data/Sogou.hap', 1, 'com.OpenHarmony.sogou.input')
```

注意：文档没有提供返回值错误码说明，当前只记录为 `number` 调用结果。

## APP 升级系统权限

当应用需要使用 `system_basic` 或 `system_core` 权限时，需要将普通应用升级为系统应用。权限要求参考 OpenHarmony 官方文档：

```text
https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/security/AccessToken/permissions-for-system-apps.md
```

项目配置：

```json5
{
  "app": {
    "runtimeOS": "OpenHarmony"
  }
}
```

业务权限声明示例，以重启权限为例：

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.REBOOT"
      }
    ]
  }
}
```

系统签名模板配置位置示例：

```text
C:\Users\smt\AppData\Local\OpenHarmony\Sdk\10\toolchains\lib\UnsgnedDebugProfileTemplate.json
C:\Users\smt\AppData\Local\OpenHarmony\Sdk\10\toolchains\lib\UnsgnedReleasedProfileTemplate.json
```

模板中需要为目标包名配置系统权限等级：

```json
{
  "bundle-name": "com.smdt.ostools.agingtest",
  "apl": "system_core",
  "app-feature": "hos_system_app"
}
```

操作流程：
- 在业务代码和 `module.json5` 中声明所需权限。
- 修改 OpenHarmony SDK 签名模板，设置目标包名的 `apl` 和 `app-feature`。
- 删除应用内旧签名信息。
- 重新生成签名并安装运行。
- 通过命令检查权限：

```bash
bm dump -n com.example.mydemo | grep system
```

## 特权应用：开机自启与进程守护

视美泰/OpenHarmony 设备如果需要实现特权应用级别的开机调起和进程守护，流程如下：

1. 实现 `ServiceExtensionAbility`。
2. 获取应用证书指纹。
3. 配置系统侧 `install_list_capability.json`。
4. 将应用安装为 `0` 用户。
5. 完成后可实现特权应用的开机调起和进程守护。

参考资料：

```text
声明为特权服务:
https://blog.csdn.net/q228931518/article/details/131520737

获取证书指纹:
https://ost.51cto.com/posts/21696
```

### 获取证书指纹

可通过安装 HAP 包时的系统日志获取证书指纹。

操作步骤：

1. 在 DevEco Studio 中打开 Log 界面。
2. 过滤关键字 `finger`。
3. 进入系统 Shell，设置 HiLog 等级：

```bash
hilog -b D
```

4. 在 DevEco Studio 中执行 `Run > Run '{模块名称}'`，运行任意 HAP 包。
5. 运行时会触发 HAP 安装。即使安装因配置问题失败，也可忽略安装错误，因为目标是从安装日志中获取指纹。
6. 回到 DevEco Studio Log 界面，查看包含 `finger` 的日志，记录证书指纹。

接入注意：
- 证书指纹与签名证书相关，重新签名后需要重新确认。
- `install_list_capability.json` 是系统侧配置，应用仓库内不应保存设备专用或客户环境专用配置。
- 开机自启可通过视美泰 `sys_setSystemBootApp()` 配置，进程守护能力需要结合特权服务与系统配置完成。

## 历史硬件服务适配

`5.0.1-SHIMeta` 历史提交曾使用：

```ts
import {
  AudioDeviceTypeEnum,
  DeviceModelEntity,
  HardwareServiceManager,
  ISerialDataCallback
} from '@mili/hardware_service_sdk'
```

已知能力：
- `getDevicePropertyModel()`：读取设备属性，包括 `mac`、`deviceModel`、`romModel`、`keyNum`、`enableHandle`、串口端口等。
- `onHandShankStateCallback()` / `offHandShankStateCallback()`：手柄状态回调。
- `initSerialDriver()` / `onSerialCallback()`：串口初始化与串口按键回调。
- `switchMicStatus(AudioDeviceTypeEnum.SPEAKER | AudioDeviceTypeEnum.EARPIECE)`：切换板载麦克风/手柄麦克风。

接入建议：
- 视美泰设备使用 `@mili/hardware_service_sdk` 处理硬件按键、手柄、串口和 `call.micSwitching`。
- 狄耐克设备使用 `@company/device_sdk`。
- 运行时通过公共厂家识别结果分流，不在同一设备上同时启用两套硬件 SDK。

## 当前项目接入约束

- `ws://`、`wss://` 地址继续走 WebRTC。
- `ip:port` 地址走 SIP，但视美泰 SIP 能力需单独确认，不能复用狄耐克 `CallApi`。
- 视美泰设备上应跳过狄耐克 `DeviceSdk.init`、看门狗、DMsg、SIP 铃声、手柄 IO。
- 项目业务层统一通过 `RtcDeviceCapabilityManager` 调用厂家能力，避免在页面或业务服务中散落厂家 SDK 判断。
- 开机自启仅在识别或探测为视美泰设备后调用。
- 文档内示例不包含真实环境地址、账号、密码、发布密钥等敏感信息。
