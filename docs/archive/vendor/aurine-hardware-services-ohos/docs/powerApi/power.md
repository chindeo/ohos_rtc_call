# 电源管理

更新时间： {docsify-updated} 

本文介绍了电源相关的接口信息。包含关机、重启、开启屏幕、关闭屏幕等。

### 一、关机

**接口说明**

关机。

```js
HardwareServiceManager.getPowerApi().shutdown(reason?: string)
```

**请求参数**

| 参数名称 | 参数类型 | 是否必须 | 说明             |
| -------- | -------- | -------- | ---------------- |
| reason   | string   | false    | 关机原因，可不传 |

**返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getPowerApi().shutdown("异常关机").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 二、重启

**接口说明**

重启。

```js
HardwareServiceManager.getPowerApi().reboot(reason?: string)
```

**请求参数**

| 参数名称 | 参数类型 | 是否必须 | 说明             |
| -------- | -------- | -------- | ---------------- |
| reason   | string   | false    | 重启原因，可不传 |

**返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getPowerApi().reboot("异常重启").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 三、屏幕是否亮起

**接口说明**

检查当前设备是否处于激活状态，如果处于激活状态屏幕将亮起，否则屏幕将关闭。

```js
HardwareServiceManager.getPowerApi().isActive()
```

**请求参数：无**

**返回参数**

| 参数类型               | 说明                                                         |
| ---------------------- | ------------------------------------------------------------ |
| Promise&lt;boolean&gt; | 成功时 resolved ，失败时 rejected<br /> true：激活（屏幕亮着），false：未激活（屏幕暗着） |

**请求示例**

```js
HardwareServiceManager.getPowerApi().isActive().then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 四、唤醒设备

**接口说明**

唤醒设备以开启屏幕。

```js
HardwareServiceManager.getPowerApi().wakeup(detail?: string)
```

**请求参数**

| 参数名称 | 参数类型 | 是否必须 | 说明                       |
| -------- | -------- | -------- | -------------------------- |
| detail   | string   | false    | 发起唤醒的请求信息，可不传 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getPowerApi().wakeup().then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 五、挂起设备

**接口说明**

挂起设备以关闭屏幕

```js
HardwareServiceManager.getPowerApi().suspend(isImmediate: boolean)
```

**请求参数**

| 参数名称    | 参数类型 | 是否必须 | 说明         |
| ----------- | -------- | -------- | ------------ |
| isImmediate | boolean  | true     | 是否立即休眠 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getPowerApi().suspend(true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 六、设置屏幕关闭的超时时间

**接口说明**

设置屏幕关闭的超时时间，单无操作到底设置的时间后，设备将息屏。

```js
HardwareServiceManager.getPowerApi().setScreenOffTime(timeout: number)
```

**请求参数**

| 参数名称 | 参数类型 | 是否必须 | 说明                                                        |
| -------- | -------- | -------- | ----------------------------------------------------------- |
| timeout  | number   | true     | 休眠时间，单位毫秒，最低设置为 15000（15s），-1表示永不息屏 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getPowerApi().setScreenOffTime(15000).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

