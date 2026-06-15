# 769 设备端鸿蒙 5.0 SDK 文档

> 来源：`狄耐克v769SDK文档_OH5_20250825.pdf`
>
> 说明：此 Markdown 由 PDF 自动转换生成，已尽量保留标题、目录、API 说明、代码片段和主要截图。

厦门狄耐克物联智慧科技有限公司
福建省厦门市海沧区海景北二路8 号

---

<!-- Page 2 / 41 -->

## 目录

## 一、变更记录............................................................................................................................................................ 2

## 二、声明.....................................................................................................................................................................3

## 三、注意事项............................................................................................................................................................ 3

## 四、文档目标............................................................................................................................................................ 3

## 五、应用场景............................................................................................................................................................ 3

## 六、集成说明............................................................................................................................................................ 4

### 6.1. 环境准备.....................................................................................................................................................................4

### 6.2. 集成方式.....................................................................................................................................................................4

### 6.3. API 调用......................................................................................................................................................................5

## 七、API 接口说明.....................................................................................................................................................8

### 7.1. DeviceSdk......................................................................................................................................................................8

### 7.2. SdkConfig 配置模块........................................................................................................................................... 11

### 7.3. CallApi 对讲模块................................................................................................................................................16

### 7.4. BroadcastApi 广播模块.....................................................................................................................................23

### 7.5. UartApi 串口模块................................................................................................................................................27

### 7.6. IOApi IO 控制模块...............................................................................................................................................27

### 7.7. PowerApi 电源管理模块.....................................................................................................................................31

### 7.8. EventObserver 事件监听模块.........................................................................................................................32

### 7.9. NetApi 网络配置模块.......................................................................................................................................... 33

### 7.10. ProcessApi 进程管理模块...............................................................................................................................36

### 7.11. WatchDogApi 看门狗模块.................................................................................................................................36

### 7.12. CommonApi 模块................................................................................................................................................... 37

## 八、错误码.............................................................................................................................................................. 37

## 九、签名...................................................................................................................................................................38

## 十、鸿蒙开发参考资料......................................................................................................................................... 40


---

<!-- Page 3 / 41 -->

## 一、变更记录

日期
版本
作者
说明
2026-01-13
### 1.0.7

苏东剑
初稿
2026-04-08
### 1.0.8

苏东剑
增加人脸功能、监仓接口板接口

---

<!-- Page 4 / 41 -->

## 二、声明

本文档是厦门狄耐克物联智慧科技有限公司（下文简科物联智慧）提供接口使用文档，便
于合作的企事业单位使用，物联智慧保留所有接口使用权利，未经许可不得公开接口使用信息
给任何非授权企业和个人。

## 三、注意事项

1.该SDK 通话不支持QoS 策略，所以使用WiFi 通信方案的请另行使用其他通话方式。
2.程序初始的时候要有个网络判断的逻辑，判断网络设备是否可用后再进行一些网络操作，并
做好重连逻辑，因为SDK 初始化的时候会重置网络。
3.应用开发需使用在签名配置中将应用权限（apl）提升为系统应用权限（system_core），否则
部分功能异常，参考下文中“签名”相关说明

## 四、文档目标

介绍v769 鸿蒙5.0 SDK 的集成方式,并对SDK 中的对应接口的作用以及开发步骤进行说
明，有助于开发者快速实现相应功能。

## 五、应用场景

适用于设备端APP 中集成语音通话、呼叫报警、门禁应答功能、门灯控制、IO 控制等。

---

<!-- Page 5 / 41 -->

## 六、集成说明

### 6.1. 环境准备

#### 1、开发工具：DevEco Studio 5.0.4 Release

#### 2、运行环境：OpenHarmony 5.0.0.71 （API 12）

#### 3、替换fullsdk，参考【官方文档-如何替换fullsdk】

(https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/faqs/full-sdk-switch-
guide.md)，将OpenHarmonySdk 替换为
version-Master_Version-OpenHarmony_5.0.0.71-20250118_060411-ohos-sdk-full-5.0.
0-release.tar.gz
Fullsdk 下载地址：
https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_5.0.0.71/2
0250118_060411/version-Master_Version-OpenHarmony_5.0.0.71-20250118_060411-
ohos-sdk-full-5.0.0-release.tar.gz
官网会定期废弃旧版本文档如上述链接无法访问自行到官网
（https://docs.openharmony.cn）搜索fullsdk 替换指南
### 6.2. 集成方式

将call_module-1.2.22.har 和device_sdk-1.0.7.har 置于工程根目录libs 文件夹：依赖包
版本号以实际为准

#### 1、

#### 2、在工程根目录的oh-package.json5 中添加依赖配置：


**页面图片：**

![page 5 image](assets/page-05-image-01.png)


---

<!-- Page 6 / 41 -->

"dependencies": {
"@company/call_module": "file:./libs/call_module-1.2.22.har",
"@company/device_sdk": "file:./libs/device_sdk-1.0.7.har"
}

#### 3、以上libs 目录可自定义为其他目录，依赖配置中的libs 目录做对应修改即可

#### 4、在工程根目录和entry 目录下分别执行ohpm install：

### 6.3. API 调用

#### 1、初始化：在EntryAbility 的onWindowStageCreate 方法对SDK 进行初始化

onWindowStageCreate(windowStage: window.WindowStage) {
...

```ts
DeviceSdk.getInstance().init(this.context)
DeviceSdk.getInstance().setDebug(true)// 是否开启debug 日志
```

...
}

#### 2、调用API：通过DeviceSdk.getInstance()获取对应的功能模块从而调用对应模块的

方法

**页面图片：**

![page 6 image](assets/page-06-image-01.png)


---

<!-- Page 7 / 41 -->

```ts
DeviceSdk.getInstance().getSdkConfig()
// Sdk 配置模块
DeviceSdk.getInstance().getPowerApi()
// 电源管理模块
DeviceSdk.getInstance().getCallApi()
// 对讲模块
DeviceSdk.getInstance().getBroadcastApi() // 广播模块
DeviceSdk.getInstance().getUartApi()
// 串口模块
DeviceSdk.getInstance().getIOApi()
// IO 控制模块
DeviceSdk.getInstance().getNetApi()
// 网络配置模块
DeviceSdk.getInstance().getDMsgApi()
// DMSG 模块
DeviceSdk.getInstance().getProcessApi()
// 进程管理模块
DeviceSdk.getInstance().getWatchDogApi()
// 看门狗模块
DeviceSdk.getInstance().getFaceApi()
// 人脸识别模块
DeviceSdk.getInstance().getCommonApi()
// 通用模块
DeviceSdk.getInstance().getEventObserver()
// 事件监听
DeviceSdk.getInstance().getSdkConfig().setCardSecret(secretType, bytes)// 设置读
```

卡参数

#### 3、退出应用时调用SDK release 方法：

```ts
aboutToDisappear() {
DeviceSdk.getInstance().release()
}
```

#### 4、SDK 配置：

let result = await DeviceSdk.getInstance()
.getSdkConfig()

```ts
.setDeviceType(DEVICE_TYPE)// 设备类型
.setBindingCode(deviceCfg.bindingCode)// 唯一绑定码
.setSipConfig({
ex_enable: deviceCfg.sipEnable ? '1' : '0', // sip 是否可用
proxy: `sip:${deviceCfg.sipServer}`, // sip 服务器proxy 地址
realm: deviceCfg.sipServer,// sip 服务器realm 都在
ex_user: deviceCfg.sipUser,// sip 用户名
passwd: deviceCfg.sipPwd,// sip 用户密码
```

expires: '0',

---

<!-- Page 8 / 41 -->

outbound: 'sip:'

```ts
})
.setNtpServer(deviceCfg.sipServer)// ntp 服务器
.setSeatGroups([{
group: deviceCfg.group, // 呼叫组
type: DEVICE_TYPE.toString(),// 呼叫组对应设备类型
timeout_seconds: '0',// 超时时间
timeout_group: '', // 超时呼叫组
enable: '1' // 是否启用该组
}])// 呼叫组
.setRingTime(RING_TIMEOUT)// 呼叫振铃时长
.setTalkVolume(TALK_VOLUME)// 通话音量取值0-5 值越大音量越小
.setOfflineLinkageDevices([{
ip: deviceCfg.superiorIp, // 离线联动呼叫对方的ip
user: deviceCfg.superiorSipNo, // 离线联动呼叫对方的sip 号
```

timeout: '0',

```ts
enable: deviceCfg.superiorEnable ? '1' : '0' // 离线联动呼叫是否启用
}])// 离线联动最多支持6 条
```

.save()

#### 5、系统事件监听：

```ts
aboutToAppear() {
for (let index = 0; index < 16; index++) {
this.sectorList.push({ value: index.toString() })
}
let systemEvent = DeviceSdk.getInstance().getEventObserver()
// 订阅触摸事件
systemEvent.on('touch', this.touchEvent)
// 订阅按键事件
systemEvent.on('key', this.keyEvent)
// 订阅刷卡事件
systemEvent.on('card', this.cardEvent)
// 订阅防区事件
systemEvent.on('security', this.securityEvent)
// 订阅ip 冲突事件
```


---

<!-- Page 9 / 41 -->

```ts
systemEvent.on('ipwatchd', this.onIpWatchEvent)
// 订阅网络状态变化事件
systemEvent.on('netState', this.onNetStateEvent)
// 订阅门磁事件
systemEvent.on('termGate', this.onTermGateEvent)
// 订阅防拆检测事件
systemEvent.on('tamperDetect', this.onTamperDetectEvent)
// 订阅sdk 未被处理的自定义dmsg 事件
systemEvent.on('dmsg', this.onDmsgEvent)
}
aboutToDisappear() {
let systemEvent = DeviceSdk.getInstance().getEventObserver()
// 取消订阅触摸事件
systemEvent.off('touch', this.touchEvent)
// 取消订阅按键事件
systemEvent.off('key', this.keyEvent)
// 取消订阅刷卡事件
systemEvent.off('card', this.cardEvent)
// 取消订阅防区事件
systemEvent.off('security', this.securityEvent)
// 取消订阅ip 冲突事件
systemEvent.off('ipwatchd', this.onIpWatchEvent)
// 取消订阅网络状态变化事件
systemEvent.off('netState', this.onNetStateEvent)
// 取消订阅门磁事件
systemEvent.off('termGate', this.onTermGateEvent)
// 取消订阅防拆检测事件
systemEvent.off('tamperDetect', this.onTamperDetectEvent)
// 取消订阅sdk 未被处理的自定义dmsg 事件
systemEvent.off('dmsg', this.onDmsgEvent)
}
```

## 七、API 接口说明

### 7.1. DeviceSdk

#### 1、初始化


---

<!-- Page 10 / 41 -->

函数名
init(context)

参数说明
context : Context
应用上下文
userCall?: boolean
是否使用对讲模块

备注
userCall 为false，无法使用CallApi

#### 2、调试开关

函数名
setDebug(debug: boolean)

参数说明
debug：是否开启调试日志

备注

#### 3、获取SDK 配置模块

函数名
getSdkConfig(): ISdkConfig

参数说明

备注
通过该模块配置对讲以及其他相关参数

#### 4、获取电源管理模块

函数名
getPowerApi(): IPowerApi

参数说明

备注
熄屏、亮屏、重启、关机等

#### 5、获取串口模块

函数名
getUartApi(): IUartApi

参数说明

备注
串口通讯

#### 6、获取IO 控制模块

函数名
getIOApi(): IIOApi

参数说明

备注
LED 灯控、防区报警等

#### 7、获取对讲模块

函数名
getCallApi(): ICallApi

参数说明

备注
呼叫、对讲、报警等初始化的时候要开启对讲模块

---

<!-- Page 11 / 41 -->

#### 8、获取广播模块

函数名
getBroadcastApi(): IBroadcastApi

参数说明

备注
下发麦克风喊话、音频广播到其他设备

#### 9、获取人脸识别模块

函数名
getFaceApi(): IFaceApi

参数说明

备注
人脸识别功能

#### 10、获取网络配置模块

函数名
getNetApi(): INetApi

参数说明

备注
获取/修改网络配置

#### 11、获取进程管理模块

函数名
getProcessApi(): IProcessApi

参数说明

备注
杀死应用、重启指定应用

#### 12、获取看门狗模块

函数名
getWatchDogApi(): IWatchDogApi

参数说明

备注

#### 13、获取通用模块

函数名
getCommonApi(): ICommonApi

参数说明

备注

#### 14、获取dmsg 模块

函数名
getDMsgApi(): IDMsgApi

---

<!-- Page 12 / 41 -->

参数说明

备注
用于发送自定义dmsg 消息

#### 15、设置读卡参数

函数名
setCardSector()

参数说明
secretType 加密方式
0：默认密码
2：自定义密码
sector 需要读取的扇区
cipher 自定义密码（只有加密方式为2 时才需要给，且一定为6 个字节
即12 位字符串如FFFFFFFFFFFF)

备注
监听系统触屏、刷卡、按键、防区报警、广播等事件

#### 16、获取系统事件监听模块

函数名
getEventObserver(): IEventObserver

参数说明

备注
监听系统触屏、刷卡、按键、防区报警、广播等事件

#### 17、释放SDK

函数名
release()

参数说明

备注
退出应用时释放SDK 资源
### 7.2. SdkConfig 配置模块

#### 1、设置设备类型

函数名
setDeviceType(deviceType: number): ISdkConfig

参数说明
deviceType: 自定义设备类型需大于10000

备注

#### 2、获取设备类型

函数名
getDeviceType(): number

参数说明

备注

---

<!-- Page 13 / 41 -->

#### 3、设置绑定码

函数名
setBindingCode(bindingCode: string): ISdkConfig

参数说明
bindingCode:设备唯一绑定码格式“SN+数字”，如SN0001

备注

#### 4、获取绑定码

函数名
getBindingCode(): string

参数说明

备注

#### 5、设置sip 参数

函数名
setSipConfig(sipCfg: SipConfig): ISdkConfig

参数说明
sipCfg：

```ts
ex_enable:string //1 启用0 禁用
proxy: string //sip 服务器proxy 地址,格式sip:<device-ip>
```

realm: string

```ts
//sip 服务器地址，格式<device-ip>
ex_user: string // sip 用户名
passwd: string // sip 用户密码
expires?: string // 生存周期
outbound?: string
nvideo?: string
// 0 开启摄像头
```

1 关闭摄像头

备注

#### 6、获取sip 参数

函数名
getSipConfig(): SipConfig

参数说明

```ts
ex_enable:string //1 启用0 禁用
proxy: string //sip 服务器proxy 地址,格式sip:<device-ip>
```

realm: string

```ts
//sip 服务器地址，格式<device-ip>
ex_user: string // sip 用户名
passwd: string // sip 用户密码
expires?: string // 生存周期
outbound?: string
nvideo?: string
// 0 开启摄像头
```

1 关闭摄像头

备注

---

<!-- Page 14 / 41 -->

#### 7、设置ntp 时间校准服务器

函数名
setNtpServer(serverIp: string): ISdkConfig

参数说明

备注

#### 8、获取ntp 时间校准服务器

函数名
getNtpServer(): string

参数说明

备注

#### 9、设置呼叫组

函数名
setSeatGroups(groups: Array<SeatGroup>): ISdkConfig

参数说明

```ts
class SeatGroup {
group: string = '' // 呼叫组号
type: string = '' // 呼叫组对应的设备类型
timeout_seconds: string = '0' // 超时时间
timeout_group: string = '' // 超时呼叫组
enable: string = '1' //1 启用0 不启用
}
```

备注

#### 10、获取呼叫组

函数名
getSeatGroups(): Array<SeatGroup>

参数说明

```ts
class SeatGroup {
group: string = '' // 呼叫组号
type: string = '' // 呼叫组对应的设备类型
timeout_seconds: string = '0' // 超时时间
timeout_group: string = '' // 超时呼叫组
enable: string = '1' //1 启用0 不启用
}
```

备注

#### 11、设置呼叫振铃时间


---

<!-- Page 15 / 41 -->

函数名
setRingTime(ringTime: number): ISdkConfig

参数说明
ringTime: 单位秒，入参需大于30

备注

#### 12、获取呼叫振铃时间

函数名
getRingTime(): number

参数说明

备注

#### 13、设置通话音量

函数名
setTalkVolume(volume: number): ISdkConfig

参数说明
volume 取值范围[0,5] 值越大声音越小0 最大5 最小

备注

#### 14、获取通话音量

函数名
getTalkVolume(): number

参数说明

备注

#### 15、设置离线联动配置

函数名
setOfflineLinkageDevices(devices: Array<Superior>): ISdkConfig

参数说明

```ts
class Superior {
user: string = '' // sip 用户名
ip: string = '' //对方ip
timeout: string = '0' //超时时间
enable: string = '1' //1 启用0 不启用
}
```

备注
在线呼叫不通时转离线呼叫，上限6 条

#### 16、获取离线联动配置

函数名
getOfflineLinkageDevices(): Array<Superior>

---

<!-- Page 16 / 41 -->

参数说明

```ts
class Superior {
user: string = '' // sip 用户名
ip: string = '' //对方ip
timeout: string = '0' //超时时间
enable: string = '1' //1 启用0 不启用
}
```

备注

#### 17、设置对讲配置

函数名
setTalkConfig(talkCfg: TalkCfg): ISdkConfig

参数说明

```ts
class TalkCfg {
timeout: string = '1800' //通话时间上限s
}
```

备注

#### 18、获取对讲配置

函数名
getTalkConfig(): TalkCfg

参数说明

```ts
class TalkCfg {
timeout: string = '1800' //通话时间上限s
}
```

备注

#### 19、修改刷卡参数接口

函数名
setCardSecret(secretType: number, bytes: number)

参数说明
secretType 刷卡模式
0:不启用1:加密防复制
bytes IC 卡内码字节数3:3 字节
4:4 字节

备注

#### 20、获取刷卡secret 参数

函数名
getRficSecret(): number

参数说明

备注

#### 21、获取bytes 参数

函数名
getRficBytes(): number

---

<!-- Page 17 / 41 -->

参数说明

备注

#### 22、保存配置

函数名
save(): Promise<boolean>

参数说明

备注
以上set 方法需要调用此save 方法才能生效
### 7.3. CallApi 对讲模块

#### 1、获取当前sip 注册状态

函数名
isSipAvailable(): boolean

参数说明

备注

#### 2、设置对讲事件回调

函数名
setCallListener(callListener: ICallListener)

参数说明

备注
ICallListener 回调说明：
/**
* 构建呼叫信息CallInfo，用于群呼时自定义参数
* @returns

```ts
*/
buildCallInfo(callInfo: CallInfo): void
/**
```

* 外部呼入
* @param call

```ts
*/
onCallReceived(call: Call)
/**
```

* 外呼异常
* @param callToCallFailed :CallGlobal.CallToCallFailed

```ts
*/
onCallOutgoingFailed(callToCallFailed: number)
```


---

<!-- Page 18 / 41 -->

/**
* 呼出，正在等待响应
* @param call

```ts
*/
onCallOutgoingProcess(call: Call)
/**
```

* 呼叫成功，对方处于振铃状态，此时可以播放回铃音
* @param call

```ts
*/
onCallRinging(call: Call)
/**
```

* 呼叫保持成功(我方申请保持)
* @param call

```ts
*/
onCallPaused(call: Call)
onCallPlayPrepare(call: Call)
onCallVisitReceived(call: Call)
/**
```

* 呼叫被保持(对方申请保持)
* @param call

```ts
*/
onCallPausedByRemote(call: Call)
/**
```

* 通话中
* @param call

```ts
*/
onCallStreamRunning(call: Call)
/**
```

* 呼叫异常
* @param call:
* @param error:CallGlobal.Error

```ts
*/
onCallError(call: Call, error: number)
```


---

<!-- Page 19 / 41 -->

/**
* 呼叫或者通话结束
* @param call

```ts
*/
onCallEnd(call: Call)
/**
```

* 异常重置
* @param

```ts
*/
onCallReset()
/**
```

* sip 注册成功
* @param

```ts
*/
onSipRegistrationSuccess()
/**
```

* sip 注册失败
* @param

```ts
*/
onSipRegistrationFailed()
/**
```

* 收到自定义消息
* @param event
* @param messageContent

```ts
*/
onMsgCtl(event: string, messageContent: string)
/**
```

* 收到执行指令
* @param call
* @param behavior
* @returns

```ts
*/
onCallExecute(call: Call, behavior: string): Promise<boolean>
/**
```

* 有其他呼叫呼入

---

<!-- Page 20 / 41 -->

* @param host

```ts
*/
onCallToCallBusy(host: string)
/**
```

* 呼叫转移
* @param call

```ts
*/
onCallReferred(call: Call)
/**
```

* 呼叫被转移
* @param call

```ts
*/
onCallReferredByRemote(call: Call)
/**
```

* 呼叫队列新增呼叫
* @param call

```ts
*/
onCallQueueAdd(call: Call)
/**
```

* 呼叫队列数据变更
* @param call

```ts
*/
onCallQueueUpdate(call: Call)
/**
```

* 呼叫队列移除
* @param call

```ts
*/
onCallQueueRemove(call: Call)
/**
```

* 呼叫清空

```ts
*/
onCallQueueClear()
/**
```

* 自动接听

```ts
*/
onCallAutoAnswer(call: Call)
```


---

<!-- Page 21 / 41 -->

/**
* 监视开始

```ts
*/
onMonitorStart(cid: number, callInfo: CallInfo)
/**
```

* 监视结束

```ts
*/
onMonitorEnd()
```

#### 3、点对点呼出

函数名
toCall(dstUser: string, dstIp: string, info: CallInfo, ring: boolean)

参数说明
dstUser 对方sip 账号
dstIp 对方设备IP
info 呼叫信息
ring 是否要振铃

备注

#### 4、呼叫组呼叫

函数名
doCall(param: DoCallParam)

参数说明
/**
* @param mode
呼叫类型
@param modeSupportOperator
呼叫类型可支持操作方式0：默认都支持1：不支持对讲
@param nursing_color
@param port
防区端口
@param inOutgoingNeedRing
是否需要振铃
@param makingCallDeviceId
呼叫发起设备id，呼叫发起设备：网关，一键报警器，之类的网关
设备。
@param makingCallDeviceName
呼叫发起设备名称，呼叫发起设备：网关，一键报警器，之类的网
关设备。
@param distalDeviceInfo
发送的设备信息
@param isNeedEndLastOutgoingCall 是否需要结束上一个呼出，有些不需要结束呼上一个出的
@param isNeedDealInComingCall 是否需要判断呼入，有些不需要判断呼入的

```ts
*/
class DoCallParam {
mode: number = 0
modeSupportOperator: number = CallGlobal.ModeSupportOperator.All
nursing_color: string | null = null
port: number = 0
```


---

<!-- Page 22 / 41 -->

```ts
inOutgoingNeedRing: boolean = false
makingCallDeviceId: string | null = null
makingCallDeviceName: string | null = null
subModeName: string | null = null
distalDeviceInfo: any = null
isNeedEndLastOutgoingCall: boolean = false
isNeedDealInComingCall: boolean = true
}
```

备注
组呼需要配置BindingCode、DeviceType、SeatGroup，否则无法正常呼叫。
组呼必须搭配我方后端使用

#### 5、接听

函数名
accept(cid: number)

参数说明
cid 呼叫id ，ICallListener 回调中返回的Call 获取

备注

#### 6、挂断

函数名
terminate(cid: number)

参数说明
cid 呼叫id ，ICallListener 回调中返回的Call 获取

备注

#### 7、通话保持

函数名
pause(cid: number)

参数说明
cid 呼叫id ，ICallListener 回调中返回的Call 获取

备注

#### 8、通话转移

函数名
transfer(cid: number, targetSipNo: string, targetIp: string)

参数说明
cid 待转移的cid
targetSipNo 目标sip 号
targetIp 目标ip

备注

#### 9、恢复通话


---

<!-- Page 23 / 41 -->

函数名
resume(cid: number)

参数说明

备注

#### 10、开启视频通话

函数名
startVoRender(x: number, y: number, w: number, h: number)

参数说明
x，y 视频窗口左上角左边，w 窗口宽度，y 窗口高度

备注

#### 11、己方视频窗口是否显示

函数名
setViRender(enable: boolean)

参数说明

备注

#### 12、对方视频窗口是否显示

函数名
setVoRender(enable: boolean)

参数说明

备注

#### 13、发送消息

函数名
sendMessage(toUser: string, toUserIp: string, event: string,
messageContent: string)

参数说明
toUser
发送对象的sip 号
toUserIp
发送对象的ip 地址
event
发送消息事件类型(必须以/special 开头例：
/special/customer/msg1)
messageContent 发送消息内容

备注
接收方通过ICallListener 的onMsgCtl 回调接收

#### 14、发送执行指令

函数名
sendExecute(call: Call, behavior: string, callback:
CallExecuteCallBack)

参数说明
call 通话实体通过ICallListener 回调获取
behavior 要执行的操作类型
callback 执行结果回调

---

<!-- Page 24 / 41 -->

备注
接收方通过ICallListener 的onCallExecute 回调接收事件并返回处
理结果

#### 15、强制发起sip 注册

函数名
registerSip()

参数说明

备注
### 7.4. BroadcastApi 广播模块

#### 1、获取广播状态

函数名
getBroadcastState(): number

参数说明

```ts
enum BroadcastState {
IDLE = 0,//空闲
PREPLAY,//预播放
PLAYING,// 播放中
PAUSE//停止
}
```

备注

#### 2、发起音频广播

函数名
sendMusicBroadcast(index: number, url: string, port: number)

参数说明
index：自定义通道
url :音频文件地址仅支持绝对地址不支持沙箱地址
port:自定义播放端口

备注

#### 3、发起麦克风广播

函数名
sendMicBroadcast(index: number,port: number)

参数说明
index：自定义通道
port:自定义播放端口

备注

#### 4、暂停广播


---

<!-- Page 25 / 41 -->

函数名
pauseSendBroadcast()

参数说明

备注

#### 5、结束广播

函数名
stopSendBroadcast()

参数说明

备注

#### 6、推送播放事件到播放设备

函数名
pushPlayParams(para: MusicParam, extra?: any)

参数说明
para 预播放返回的播放参数
extra 自定义字段用于实现针对性设备广播播放端接收此参数
自行判断是否播放

备注
接收music_play_ack 事件后可通过此方法将播放参数推送到播放端，也
可以自行通过其他方式推送播放参数

#### 7、推送停止播放事件到播放设备

函数名
pushStopPlayParams(para: MusicParam, extra?: any)

参数说明
para 预播放返回的播放参数
extra 自定义字段用于实现针对性设备广播播放端接收此参数
自行判断是否播放

备注

#### 8、播放广播

函数名
playBroadcast(para: MusicParam)

参数说明
para 播放参数

备注
接收到play_music 事件后（非pushPlayParams 推送方式则在自己
实现的推送接收到数据后）调用此方法开始播放广播内容

#### 9、结束播放广播

函数名
stopPlayBroadcast(index: number, port: number)

参数说明
index 播放参数中的index 字段
port 自定义端口与播放时的port 一致

---

<!-- Page 26 / 41 -->

备注
接收stop_music 事件后调用该方法停止播放，也可以缓存播放
参数主动调用此方法停止播放

#### 10、广播事件监听

```ts
aboutToAppear() {
// 广播事件监听
DeviceSdk.getInstance().getEventObserver().on('broadcast', (event: BroadcastEvent) =>
{
this.onBroadcastRecv(event)
})
}
aboutToDisappear() {
// 取消广播事件监听
DeviceSdk.getInstance().getEventObserver().off('broadcast', (event: BroadcastEvent) =>
{
this.onBroadcastRecv(event)
})
// 停止播放和广播
if (this.musicParam) {
DeviceSdk.getInstance().getBroadcastApi().stopPlayBroadcast(this.musicParam.index,
this.musicParam.port)
if (DeviceSdk.getInstance().getBroadcastApi().getBroadcastState() ==
BroadcastState.PLAYING) {
DeviceSdk.getInstance().getBroadcastApi().pushStopPlayParams(this.musicParam)
}
}
DeviceSdk.getInstance().getBroadcastApi().stopSendBroadcast()
}
onBroadcastRecv(event: BroadcastEvent) {
```

console.info(TEST_TAG + '-broadcast', JSON.stringify(event))

```ts
if (event && event.event && event.broadcastData) {
let musicParam: MusicParam = event.broadcastData
// 发送端的逻辑
if (event.event == 'music_play_ack') {
//底层准备就绪的回调，返回播放参数，此处调用pushPlayParams 把参数推送给播放设备，播放设
```

备将接收到play_music 事件

---

<!-- Page 27 / 41 -->

```ts
if (musicParam.result == 0) { // result=0 标识已就绪
this.musicParam = musicParam
this.musicParam.vol = this.vol // 设置播放音量
// 添加额外参数比如对应播放设备的ip 或者其他标识字段，用于限制指定的播放设备
let extra: BroadcastExtraMsg = {
```

devlist: '<device-ip>'

```ts
}
DeviceSdk.getInstance()
```

.getBroadcastApi()
.pushPlayParams(this.musicParam, extra) // 也可以不调用pushPlayParams 自行通过其
他方式把数据推送给播放设备，播放设备接收之后调用playBroadcast
// DeviceSdk.getInstance().getBroadcastApi().playBroadcast(this.sendParam) //此
处可以实现本机同步播放注释此行则本机自己不播放

```ts
}
} else if (event.event == 'music_play_finish') {
//当前音频播放结束的回调在此通知播放设备停止播放并停止推送播放数据
DeviceSdk.getInstance().getBroadcastApi().pushStopPlayParams(musicParam)
DeviceSdk.getInstance().getBroadcastApi().stopSendBroadcast()
}
// 播放端的逻辑
if (event.event == 'play_music') {
// 开始播放
let extra = event.broadcastData as BroadcastExtraMsg
if (extra) {
```

console.log(TEST_TAG, 'extra ip=' + extra.devlist)

```ts
// 根据extra 字段判断哪些设备可以播放
// if (extra.devlist?.indexOf('<device-ip>') == -1) {
//
```

return

```ts
// }
}
let state = DeviceSdk.getInstance().getBroadcastApi().getBroadcastState()
if (state == BroadcastState.PLAYING || state == BroadcastState.PAUSE) { // 正在广播
```

不能播放别人的广播
console.log(TEST_TAG, 'busy')

```ts
} else {
this.musicParam = musicParam
DeviceSdk.getInstance().getBroadcastApi().playBroadcast(musicParam)
}
```


---

<!-- Page 28 / 41 -->

```ts
} else if (event.event == 'stop_music') {
// 停止播放
DeviceSdk.getInstance().getBroadcastApi().stopPlayBroadcast(musicParam.index,
```

musicParam.port)

```ts
}
}
}
```

### 7.5. UartApi 串口模块

#### 1、发送串口指令

函数名
send(data: ArrayBuffer, printLog: boolean): Promise<void>

参数说明

备注
### 7.6. IOApi IO 控制模块

#### 1、485 门灯控制

函数名
rgb_led_485(r: boolean, g: boolean, b: boolean)

参数说明
r、g、b 表示红绿蓝灯是否点亮

备注
支持混色，红绿灯一起亮则显示黄色

#### 2、机身led 灯带控制

函数名
rgb_led_local(r: boolean, g: boolean, b: boolean)

参数说明
r、g、b 表示红绿蓝灯是否点亮

备注
支持混色，红绿灯一起亮则显示黄色

#### 3、防区警号电源控制（卫生间按钮LED 灯）

函数名
hooter(onoff: boolean)

参数说明
onoff false 关闭
true 开启

备注

#### 4、声道与麦克风选择

函数名
handset(mode: number)

参数说明
mode：0: 外放模式
1: 手柄模式

备注

---

<!-- Page 29 / 41 -->

#### 5、监仓接口板继电器1/2 开关

函数名
unlock(index: number, onoff: number)

参数说明
index 0: 继电器1 1: 继电器2
onoff 0: 关闭
1: 开启

备注

#### 6、补光灯开启关闭

函数名
camLedControl(onoff: number)

参数说明
onoff 0: 关闭
1: 开启

备注

#### 7、hub usb 开关

函数名
hubUsb(index: number, onoff: number)

参数说明
index 取值范围0~3，hub usb 序号，默认取值=0
onoff 0: 关闭
1: 开启

备注

#### 8、监仓接口板门灯控制

函数名
mcuLight(index: number, onoff: number)

参数说明
index 取值范围0、1、2，0 表示控制门灯，1 表示门灯开关,
控制门灯是一个功能用来控制门灯的，2 表示门灯电源
onoff 0: 关闭
1: 开启

备注
### 7.7. FaceApi 人脸识别模块

#### 1、设置人脸识别参数

函数名
setFaceConfig(enable: boolean, similarity: number, live: number,
model: number, mask: number, led: number, gray: number,
enableFaceIr: boolean): Promise<boolean>

参数说明
enable: 是否开启
similarity: 相识度72:低
75:中
78:高
live: 活体检测0:禁用1:普通2:高级--只有门禁机才有此功能
model: 识别模型0:4.0 1:5.0 2:6.0 3:6.1 4:6.2 5:7.0 6:7.1
mask: 口罩检测0:禁止1:开启
led: 补光灯
0:待机关闭
1:实时检测
gray:补光灯灵敏度
0:普通
1:灵敏

---

<!-- Page 30 / 41 -->

enableFaceIr: 是否需要处理人体感应回调

备注

#### 2、获取人脸参数

函数名
getFaceConfig(): FaceBean

参数说明
FaceBean

备注

#### 3、开启人脸进程--门禁机不需要

函数名
startFaceProcess(): Promise<void>

参数说明

备注

#### 4、结束人脸进程--门禁机不需要

函数名
killFaceProcess(): Promise<void>

参数说明

备注

#### 5、开启人脸识别

函数名
faceStart(): Promise<DEvent>

参数说明

备注

#### 6、结束人脸识别

函数名
stopFace(isRecycle?: boolean): Promise<DEvent>

参数说明
isRecycle 是否释放摄像头

备注

#### 7、开启人脸显示

函数名

```ts
startFaceOsd(x?: number, y?: number, w?: number, h?: number):
Promise<DEvent>
```

参数说明
x：开始渲染人脸识别界面的x 像素
y：开始渲染人脸识别界面的y 像素
w：渲染人脸识别界面的宽度

---

<!-- Page 31 / 41 -->

h：渲染人脸识别界面的高度

备注

#### 8、人脸注册--本机注册

函数名
registerFace(registerId: number): Promise<DEvent>

参数说明
registerId
注册id

备注
/ui/v170/face/register 返回结果，是否成功

#### 9、人脸注册--图片注册

函数名

```ts
registerFaceJpeg(registerId: number, jpegUrl: string):
Promise<DEvent>
```

参数说明
registerId
注册id
jpegUrl 人脸图片地址

备注
/ui/v170/face/jpeg 返回结果

#### 10、单个人脸人脸注册信息

函数名
deleteFace(registerId: number): Promise<DEvent>

参数说明
registerId
注册id

备注

#### 11、清除所有人脸注册信息

函数名
clearFace(): Promise<DEvent>

参数说明

备注

#### 12、人脸识别事件监听

函数名

```ts
DeviceSdk.getInstance().getEventObserver().on('face',
this.onFaceEvent)
DeviceSdk.getInstance().getEventObserver().off('face',
this.onFaceEvent)
```

参数说明
'face' 人脸识别回调事件

备注

```ts
private onFaceEvent = async (faceEvent: FaceEvent) => {
let event = faceEvent.event
switch (event) {
case 'faceIdent': // 处理人脸识别成功
break
```


---

<!-- Page 32 / 41 -->

```ts
case 'faceRegister': // 处理人脸注册
break
case 'faceRegisterJpeg': // 处理人脸图片注册
break
case 'faceCapture': // 处理人脸抓拍
break
case 'faceLived': // 处理活体检测--只有门禁机才有此回调
break
case 'irDetect': // 处理人体感应
break
case 'faceReboot': // 处理人脸识别进程重启
break
}
}
```

### 7.8. PowerApi 电源管理模块

#### 1、重启设备

函数名
reboot()

参数说明

备注

#### 2、关机

函数名
shutdown()

参数说明

备注

#### 3、熄屏

函数名
suspend()

参数说明

备注

#### 4、亮屏

函数名
wakeup()

参数说明

备注

---

<!-- Page 33 / 41 -->

#### 5、判断当前是否亮屏

函数名
isActive(): Promise<boolean>

参数说明

备注
### 7.9. EventObserver 事件监听模块

#### 1、订阅事件

函数名
on(eventName: EventName, callback: Function)

参数说明
eventName:事件类型
'touch' 触屏仅提示触屏操作不返回具体坐标
'key' 按键返回键值与动作onoff 1 表示按下0 表示抬起
'card' 刷卡返回卡号
'security' 防区报警返回防区状态对应的io 值表示当前状态0 为正
常2 为触发
'broadcast' 广播事件
'ipwatchd' ip 冲突事件
'dmsg' 未被sdk 处理的自定义dmsg 事件
'netState' 网络状态事件
'face' 人脸识别回调事件
'termGate' 监仓接口板门磁事件
'tamperDetect' 监仓接口板防拆检测事件
callback:事件回调

备注

#### 2、取消订阅事件

函数名
off(eventName: SystemEventName, callback: Function)

参数说明
eventName:事件类型
callback:事件回调

备注
将订阅时的事件类型和对应的回调传入

#### 3、取消所有订阅事件

函数名
offAll()

参数说明

备注

---

<!-- Page 34 / 41 -->

### 7.10. NetApi 网络配置模块

#### 1、判断网络是否可用

函数名
isNetAvailable(): Promise<boolean>

参数说明

备注

#### 2、获取当前激活的网络配置

函数名
getAvailableNetCfg(): Promise<NetworkConfig>

参数说明

```ts
class NetworkConfig {
netType: NetType = NetType.Unknown
/**
```

* STATIC
0，DHCP
1

```ts
*/
mode: number = 0
ip: string = ''
netMask: string = ''
gateway: string = ''
dnsServer: string = ''
}
```

备注

#### 3、获取以太网IP 配置

函数名
getEthernetConfig(): Promise<NetworkConfig>

参数说明

备注

#### 4、获取wifi IP 配置

函数名
getWifiConfig(): Promise<NetworkConfig>

参数说明

备注

#### 5、设置以太网IP 配置

函数名
setEthernetConfig(cfg: NetworkConfig): Promise<boolean>

参数说明

备注

---

<!-- Page 35 / 41 -->

#### 6、判断当前是否蜂窝网络

函数名
isCellularNet(): Promise<boolean>

参数说明

备注

#### 7、获取网络类型

函数名
getNetType(): Promise<number>

参数说明

```ts
enum NetType {
/**
```

* 未知

```ts
*/
Unknown = 0,
/**
```

* 有线
*/
Ethernet,
/**
* 无线
*/
Wifi,
/**
* 蜂窝数据-4G/5G
*/
Cellular
}

备注

#### 8、启用蜂窝网络

函数名
enableCellularData(): Promise<void>

参数说明

备注

#### 9、判断蜂窝网络是否启用

函数名
isCellularDataEnabled(): Promise<boolean>

参数说明

备注

---

<!-- Page 36 / 41 -->

#### 10、禁用蜂窝网络

函数名
disableCellularData(): Promise<void>

参数说明

备注

#### 11、获取蜂窝网络连接状态

函数名
getCellularDataState(): Promise<number>

参数说明

备注

#### 12、获取蜂窝网络apn

函数名
getCellularApn(): Promise<string>

参数说明

备注

#### 13、设置蜂窝网络apn

函数名
setCellularApn(apn: string): Promise<boolean>

参数说明

备注

#### 14、获取蜂窝网络信号值

函数名

```ts
setCellularApngetCellularSignalInfo():
Promise<Array<radio.SignalInformation>>
```

参数说明

备注

#### 15、获取MEID

函数名
getMEID(): Promise<string>

参数说明

备注

#### 16、获取IMEI

函数名
getIMEI(): Promise<string>

参数说明

备注

---

<!-- Page 37 / 41 -->

#### 17、获取sim 卡信息

函数名
getSimAccountInfo(): Promise<sim.IccAccountInfo>

参数说明

备注

#### 18、获取以太网mac 地址

函数名
getEthMac(): Promise<string>

参数说明

备注

#### 19、获取wifi mac 地址

函数名
getWifiMac(): Promise<string>

参数说明

备注
### 7.11. ProcessApi 进程管理模块

#### 1、杀死指定应用

函数名
killApp(bundleName:string): Promise<void>

参数说明

备注

#### 2、重启指定应用

函数名
restartApp(bundleName:string,abilityName:string): Promise<void>

参数说明

备注
### 7.12. WatchDogApi 看门狗模块

#### 1、添加看门狗

函数名
addDog(bundleName: string, abilityName: string): Promise<boolean>

参数说明

备注

#### 2、移除看门狗


---

<!-- Page 38 / 41 -->

函数名
removeDog(bundleName: string): Promise<boolean>

参数说明

备注

#### 3、喂狗

函数名
feedDog(bundleName: string): Promise<boolean>

参数说明

备注

#### 4、自动看门狗

函数名
keepAlive(bundleName: string, abilityName: string)

参数说明

备注

#### 5、释放看门狗

函数名
release()

参数说明

备注
### 7.13. CommonApi 模块

#### 1、设置触屏是否自动亮屏

函数名
setTouchWakeupDisable(disable: boolean): Promise<void>

参数说明

备注

#### 2、设置伪关机状态

函数名
setShutDownState(): Promise<void>

参数说明

备注
效果为sdk 不再处理除了reboot 以外的任何事件，此时触屏不亮屏

## 八、

错误码
错误类型
CallGlobal.CallToCallFailed
HaveStreamRun:
正在通话中，无法呼叫
HaveOutgoingWithoutPaused:
已有呼出通话，无法呼叫

---

<!-- Page 39 / 41 -->

Repeat:
已有相同呼入通话，无法呼叫
UrlNull: callUrl 为空，无法呼叫
CallIpNull: 本地ip 地址为空，无法呼叫
OfflineNull: 联动配置无效，无法呼叫
CidInvalid: 无效cid，无法呼叫
错误类型
CallGlobal.Error
OutgoingProgressError：呼叫失败，邀请通话，未收到回应。
OutgoingRingingOutTime：振铃超时
StreamRunPrepareError：开始发起sip 呼叫失败
PausingError ：发起通话保持失败
PausedOutTime：通话保持超时
TransferError ：转移失败，转移目标不在线
ReferringError ：发起通话转移失败
ReferInvitingError ：发起通话转移邀请通话失败
ReferredOutTime：通话转移超时

## 九、签名

Hap 包签名工具概述：
https://docs.openharmony.cn/pages/v4.1/zh-cn/application-dev/security/hapsigntool-overview.md
Hap 包签名工具指导：
https://docs.openharmony.cn/pages/v4.1/zh-cn/application-dev/security/hapsigntool-guidelines.md
应用包签名工具:
https://gitee.com/openharmony/developtools_hapsigner
FullSDK 签名工具目录：

---

<!-- Page 40 / 41 -->

HarmonyAppProvision 配置文件说明（就是UnsgnedReleasedProfileTemplate.json 文件）：
https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/security/app-provision-structure.md/
修改签名签名将应用提升为系统权限：
https://docs.openharmony.cn/pages/v5.1/zh-cn/device-dev/subsystems/subsys-app-privilege-config-gu
ide.md
将UnsgnedReleasedProfileTemplate.json 中的apl 修改为system_core
https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V3/ohos-auto-configuring-signature-
information-0000001271659465-V3

**页面图片：**

![page 40 image](assets/page-40-image-01.png)


---

<!-- Page 41 / 41 -->

## 十、鸿蒙开发参考资料

开源鸿蒙官网
https://docs.openharmony.cn/
开源鸿蒙在线课程
https://www.openharmony.cn/courses/
开发者文档
https://www.openharmony.cn/docs/zh-cn/overview/
Codelabs
https://growing.openharmony.cn/mainPlay/codelabs/
开源鸿蒙官方代码仓库
https://gitee.com/openharmony
开源鸿蒙每日构建
https://ci.openharmony.cn/
Laval 社区
https://laval.csdn.net/
开源鸿蒙开发者论坛
https://forums.openharmony.cn/
开源鸿蒙三方库中心仓
https://ohpm.openharmony.cn/#/cn/home
OpenHarmony SIG 组织
https://gitee.com/organizations/openharmony-sig/projects
OpenHarmony-TPC
https://gitee.com/openharmony-tpc

---
