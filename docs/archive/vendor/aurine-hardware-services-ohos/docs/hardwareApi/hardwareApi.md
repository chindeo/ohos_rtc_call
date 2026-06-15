# 硬件外设

更新时间： {docsify-updated} 

本文介绍了与硬件外设相关的接口信息。包括按键背光灯控制、设置 RGB 三色灯值、mic 切换、按键事件、听筒/免提切换等。

### 一、获取设备属性模型信息

**接口说明**

获取设备属性模型信息，描述设备硬件功能和支持情况

```js
HardwareServiceManager.getHardwarePeripheralsApi().getDevicePropertyModel()
```

**请求参数：无**

**返回参数**

| 参数类型                                                     | 说明                                                    |
| ------------------------------------------------------------ | ------------------------------------------------------- |
| Promise&lt;[DeviceModelEntity](./docs/property/entity.md#DeviceModelEntity)&gt; | 成功时 resolved 获取 DeviceModelEntity，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().getDevicePropertyModel().then((entity) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 二、切换听筒与免提

**接口说明**

切换音频设备，用于切换耳机听筒模式与免提模式，mic与speaker会一起切换，管理员机可以使用此方法切换听筒与免提。

```js
HardwareServiceManager.getHardwarePeripheralsApi().switchHeadsetStatus(deviceType: AudioDeviceTypeEnum)
```

**请求参数：**

| 参数名称   | 参数类型                                                     | 是否必须 | 说明                                                         |
| ---------- | ------------------------------------------------------------ | -------- | ------------------------------------------------------------ |
| deviceType | [AudioDeviceTypeEnum](./docs/property/entity.md#AudioDeviceTypeEnum) | true     | 音频设备类型<br> AudioDeviceTypeEnum.EARPIECE：耳机、听筒、手柄<br > AudioDeviceTypeEnum.SPEAKER：扬声器、机身 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().switchHeadsetStatus(AudioDeviceTypeEnum.EARPIECE).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 三、切换MIC

**接口说明**

切换mic设备，用于切换机身mic模式与手柄mic模式，只切换mic模式，speaker没有切换，床头机、门口机可以使用此方法切换手柄 mic 与机身 mic。

```js
HardwareServiceManager.getHardwarePeripheralsApi().switchMicStatus(deviceType: AudioDeviceTypeEnum)
```

**请求参数：**

| 参数名称   | 参数类型                                                     | 是否必须 | 说明                                                         |
| ---------- | ------------------------------------------------------------ | -------- | ------------------------------------------------------------ |
| deviceType | [AudioDeviceTypeEnum](./docs/property/entity.md#AudioDeviceTypeEnum) | true     | 音频设备类型<br> AudioDeviceTypeEnum.EARPIECE：耳机、听筒、手柄<br > AudioDeviceTypeEnum.SPEAKER：扬声器、机身 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().switchMicStatus(AudioDeviceTypeEnum.EARPIECE).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 四、设置 RGB 三色灯状态

**接口说明**

设置 RGB 三色灯状态（部分设备不支持，请以设备实际效果为准）。

```js
HardwareServiceManager.getHardwarePeripheralsApi().setRgbLedLightStatus(red: boolean, green: boolean, blue: boolean)
```

**请求参数：**

| 参数名称 | 参数类型 | 是否必须 | 说明                                        |
| -------- | -------- | -------- | ------------------------------------------- |
| red      | boolean  | true     | 红灯状态<br /> true：打开<br /> false：关闭 |
| green    | boolean  | true     | 绿灯状态<br /> true：打开<br /> false：关闭 |
| blue     | boolean  | true     | 蓝灯状态<br /> true：打开<br /> false：关闭 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().setRgbLedLightStatus(true, false, false).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 五、设置 LED 灯状态

**接口说明**

设置 LED 灯状态，例如控制底部 LED 氛围灯状态。

```js
HardwareServiceManager.getHardwarePeripheralsApi().setPwmLedStatus(status: number)
```

**请求参数：**

| 参数名称 | 参数类型 | 是否必须 | 说明                                                         |
| -------- | -------- | -------- | ------------------------------------------------------------ |
| status   | number   | true     | LED  灯状态<br /> 0：关闭<br /> 1：打开<br /> 2：快闪<br /> 3：慢闪 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().setPwmLedStatus(1).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 六、设置按键灯状态

**接口说明**

设置按键灯状态，例如控制中控屏、室内机的设备按键灯状态。

```js
HardwareServiceManager.getHardwarePeripheralsApi().setAllPressLightStatus(status: number)
```

**请求参数：**

| 参数名称 | 参数类型 | 是否必须 | 说明                                   |
| -------- | -------- | -------- | -------------------------------------- |
| status   | number   | true     | 按键灯状态<br /> 0：关闭<br /> 1：打开 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().setAllPressLightStatus(1).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 七、设置继电器状态

**接口说明**

设置继电器状态。

```js
HardwareServiceManager.getHardwarePeripheralsApi().setRelayStatus(relay: number, status: boolean)
```

**请求参数：**

| 参数名称 | 参数类型 | 是否必须 | 说明                                                         |
| -------- | -------- | -------- | ------------------------------------------------------------ |
| relay    | number   | true     | 继电器编号，表示几路继电器<br /> 0：第一路继电器<br /> 1：第二路继电器<br /> ...... |
| status   | boolean  | true     | 继电器状态<br /> true：打开继电器<br /> fales：关闭继电器    |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().setRelayStatus(0, true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 八、初始化串口驱动

**接口说明**

初始化指定串口驱动。

```js
HardwareServiceManager.getHardwarePeripheralsApi().initSerialDriver(serialPort: number, baudRate: number)
```

**请求参数：**

| 参数名称   | 参数类型 | 是否必须 | 说明   |
| ---------- | -------- | -------- | ------ |
| serialPort | number   | true     | 串口号 |
| baudRate   | number   | true     | 波特率 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().initSerialDriver(6, 9600).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 九、注销串口驱动

**接口说明**

注销串口驱动。

```js
HardwareServiceManager.getHardwarePeripheralsApi().uInitSerialDriver()
```

**请求参数：无**

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().uInitSerialDriver().then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 十、发送串口数据

**接口说明**

发送串口数据。

```js
HardwareServiceManager.getHardwarePeripheralsApi().sendSerialData(data: Uint8Array)
```

**请求参数：**

| 参数名称 | 参数类型   | 是否必须 | 说明       |
| :------- | :--------- | :------- | :--------- |
| data     | Uint8Array | true     | 待发送数据 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().sendSerialData(new Uint8Array([0xA7, 0x06, 0x00, 0x81, 0x01, 0x21])).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 十一、初始化 485 串口

**接口说明**

初始化485串口。

```js
HardwareServiceManager.getHardwarePeripheralsApi().initRs485SerialPort()
```

**请求参数：无**

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().initRs485SerialPort().then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 十二、注销 485 串口

**接口说明**

注销485串口。

```js
HardwareServiceManager.getHardwarePeripheralsApi().uInitRs485SerialPort()
```

**请求参数：无**

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().uInitRs485SerialPort().then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 十三、发送 485 数据

**接口说明**

发送485数据。

```js
HardwareServiceManager.getHardwarePeripheralsApi().sendRs485Data(data: Array<number>)
```

**请求参数：**

| 参数名称 | 参数类型      | 是否必须 | 说明       |
| :------- | :------------ | :------- | :--------- |
| data     | Array<number> | true     | 待发送数据 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().sendRs485Data([0xA7, 0x08]).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 十四、喂狗

**接口说明**

喂狗，该方法需要定时重复调用。一旦调用了该方法表示启用喂狗检测机制，后续必须在指定时间段内再次调用该方法（一般情况下为30s），以此反复，如果该时间段内没有再次调用该方法将会导致系统重启。为避免调用失败，建议最好每5s就调用一次。

```js
HardwareServiceManager.getHardwarePeripheralsApi().feedWatchDog(packageName: string)
```

**请求参数：**

| 参数名称    | 参数类型 | 是否必须 | 说明           |
| ----------- | -------- | -------- | -------------- |
| packageName | string   | true     | 需要喂狗的包名 |

 **返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getHardwarePeripheralsApi().feedWatchDog("xxx").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

!> **注意事项** <br /> 该方法是一个应用异常时的保底恢复措施。应用可以定时循环调用该接口进行喂狗，当应用出现异常从而导致无法及时喂狗，系统会进行重启恢复。第三方开发者可以根据自身情况判断是否需要使用该方法<br />

### 十五、注册手柄状态回调

**接口说明**

注册手柄状态回调。

```js
HardwareServiceManager.getHardwarePeripheralsApi().onHandShankStateCallback(callback: Callback<boolean>)
```

**请求参数：**

| 参数名称 | 参数类型          | 是否必须 | 说明                                                |
| -------- | ----------------- | -------- | --------------------------------------------------- |
| callback | Callback<boolean> | true     | 回调函数<br /> true：拿起手柄<br /> false：放下手柄 |

 **返回参数：无**

**请求示例**

```js
const callback = (result: boolean) => {
  // do something
}

HardwareServiceManager.getHardwarePeripheralsApi().onHandShankStateCallback(callback)
```

!> **注意事项** <br /> 在监听到拿起手柄事件后，第三方需要调用 switchHeadsetStatus(AudioDeviceTypeEnum.EARPIECE) 方法将声音切换到手柄，放下手柄后调用 switchHeadsetStatus(AudioDeviceTypeEnum.SPEAKER)  方法将声音切换到免提<br />

### 十六、注销手柄状态回调

**接口说明**

注销手柄状态回调。

```js
HardwareServiceManager.getHardwarePeripheralsApi().offHandShankStateCallback(callback: Callback<boolean>)
```

**请求参数：**

| 参数名称 | 参数类型          | 是否必须 | 说明                 |
| -------- | ----------------- | -------- | -------------------- |
| callback | Callback<boolean> | true     | 注册时传入的回调函数 |

 **返回参数：无**

**请求示例**

```js
const callback = (result: boolean) => {
  // do something
}

HardwareServiceManager.getHardwarePeripheralsApi().offHandShankStateCallback(callback)
```

### 十七、注册刷卡回调

**接口说明**

注册刷卡数据回调。

```js
HardwareServiceManager.getHardwarePeripheralsApi().onCardNumCallback(callback: Callback<string>)
```

**请求参数：**

| 参数名称 | 参数类型         | 是否必须 | 说明               |
| -------- | ---------------- | -------- | ------------------ |
| callback | Callback<string> | true     | 回调函数，回调卡号 |

 **返回参数：无**

**请求示例**

```js
const callback = (result: string) => {
  // do something
}

HardwareServiceManager.getHardwarePeripheralsApi().onCardNumCallback(callback)
```

### 十八、注销刷卡回调

**接口说明**

注销刷卡数据回调。

```js
HardwareServiceManager.getHardwarePeripheralsApi().offCardNumCallback(callback: Callback<string>)
```

**请求参数：**

| 参数名称 | 参数类型         | 是否必须 | 说明                 |
| -------- | ---------------- | -------- | -------------------- |
| callback | Callback<string> | true     | 注册时传入的回调函数 |

 **返回参数：无**

**请求示例**

```js
const callback = (result: string) => {
  // do something
}

HardwareServiceManager.getHardwarePeripheralsApi().offCardNumCallback(callback)
```

### 十九、注册串口数据回调

**接口说明**

注册刷卡数据回调。

```js
HardwareServiceManager.getHardwarePeripheralsApi().onSerialCallback(callback: ISerialDataCallback)
```

**请求参数：**

| 参数名称 | 参数类型            | 是否必须 | 说明                   |
| -------- | ------------------- | -------- | ---------------------- |
| callback | ISerialDataCallback | true     | 回调函数，回调串口数据 |

 **返回参数：无**

**请求示例**

```js
private serialCallback: ISerialDataCallback = {
  onSerialData(data: Uint8Array, length: number) {
    // do something   
  }
}

HardwareServiceManager.getHardwarePeripheralsApi().onSerialCallback(serialCallback)
```

### 二十、注销串口数据回调

**接口说明**

注销串口数据回调。

```js
HardwareServiceManager.getHardwarePeripheralsApi().offCardNumCallback(callback: ISerialDataCallback)
```

**请求参数：**

| 参数名称 | 参数类型            | 是否必须 | 说明                 |
| -------- | ------------------- | -------- | -------------------- |
| callback | ISerialDataCallback | true     | 注册时传入的回调函数 |

 **返回参数：无**

**请求示例**

```js
private serialCallback: ISerialDataCallback = {
  onSerialData(data: Uint8Array, length: number) {
    // do something   
  }
}

HardwareServiceManager.getHardwarePeripheralsApi().offCardNumCallback(serialCallback)
```

### 二十一、设备按键事件

**接口说明**

监听设备按键键值和对应的事件。需要在 pages 页面的最外层组件使用 onKeyEvent 方法方法来监听按键按下与抬起事件

```js
.onKeyEvent((event: KeyEvent) => {
     // do something      
})
```

**请求参数：**

| 参数名称 | 参数类型 | 是否必须 | 说明     |
| -------- | -------- | -------- | -------- |
| event    | KeyEvent | true     | 按键事件 |

 **返回参数：无**

**请求示例**

```js
Navigation(this.navPathStack)
      .mode(NavigationMode.Stack)
      .hideToolBar(true)
      .hideTitleBar(true)
      .size({ width: DimensionsConst.FULL, height: DimensionsConst.FULL })
      .onKeyEvent((event: KeyEvent) => {
  	 // event.keyCode
       // event.type
        this.keyEvent = event
      })
```

!> **注意事项** <br /> 每款设备的按键值未必一定都是一样的，比如门前的呼叫按钮和病床的呼叫按钮他们的keyCode未必是一样的，第三方开发者在开发时可以监听 onKeyEvent 回调，然后按下设备上的按键，看下 onKeyEvent 实际上报的按键值是多少，以实际上报的按键值为准<br />
