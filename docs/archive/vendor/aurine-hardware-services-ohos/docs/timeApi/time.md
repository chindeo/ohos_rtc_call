# 时间管理

更新时间： {docsify-updated} 

本文介绍了时间相关的接口信息。包含获取是否为24小时制、设置时间、设置时区等。

### 一、是否为24小时制

**接口说明**

判断系统是否为24小时制。

```js
HardwareServiceManager.getTimeApi().is24HourClock()
```

**请求参数：无**

**返回参数**

| 参数类型               | 说明                                                         |
| ---------------------- | ------------------------------------------------------------ |
| Promise&lt;boolean&gt; | 成功时 resolved ，失败时 rejected<br /> 返回 resolved 时，true：24小时制，false：非24小时制 |

**请求示例**

```js
HardwareServiceManager.getTimeApi().is24HourClock().then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 二、设置24小时制

**接口说明**

设置系统时间是否使用24小时制。

```js
HardwareServiceManager.getTimeApi().is24HourClock(is24: boolean)
```

**请求参数**

| 参数名称 | 参数类型 | 是否必须 | 说明                                          |
| -------- | -------- | -------- | --------------------------------------------- |
| is24     | boolean  | true     | true：使用24小时制<br />false：不使用24小时制 |

**返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getTimeApi().is24HourClock(true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 三、设置系统时间

**接口说明**

设置系统时间。

```js
HardwareServiceManager.getTimeApi().setSystemTime(timestamp: number)
```

**请求参数**

| 参数名称  | 参数类型 | 是否必须 | 说明                     |
| --------- | -------- | -------- | ------------------------ |
| timestamp | number   | true     | 需要设置时间对应的时间戳 |

**返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getTimeApi().setSystemTime(1761018785591).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 四、设置系统时区

**接口说明**

设置系统时区

```js
HardwareServiceManager.getTimeApi().setTimezone(timezone: string)
```

**请求参数**

| 参数名称 | 参数类型 | 是否必须 | 说明                                         |
| -------- | -------- | -------- | -------------------------------------------- |
| timezone | string   | true     | 标准时区值（Asia/Shanghai、Europe/London等） |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getTimeApi().setTimezone("Asia/Shanghai").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 五、判断是否自动获取时间

**接口说明**

判断是否从网络标识和时区（NITZ）自动获取日期、时间和时区

```js
HardwareServiceManager.getTimeApi().getAutoSyncTime()
```

**请求参数：无**

**返回参数**

| 参数类型               | 说明                                                         |
| ---------------------- | ------------------------------------------------------------ |
| Promise&lt;boolean&gt; | 成功时 resolved，失败时 rejected<br /> true：自动同步，false：手动同步 |

**请求示例**

```js
HardwareServiceManager.getTimeApi().getAutoSyncTime().then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 六、设置自动获取时间

**接口说明**

设置是否从网络标识和时区（NITZ）自动获取日期、时间和时区

```js
HardwareServiceManager.getTimeApi().setAutoSyncTime(autoSyncTime: boolean)
```

**请求参数**

| 参数名称     | 参数类型 | 是否必须 | 说明                                           |
| ------------ | -------- | -------- | ---------------------------------------------- |
| autoSyncTime | boolean  | true     | true：自动获取时间<br /> false：不自动获取时间 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getTimeApi().setAutoSyncTime(true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

