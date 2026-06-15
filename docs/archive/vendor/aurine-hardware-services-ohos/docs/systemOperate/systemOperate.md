# 系统管理

更新时间： {docsify-updated} 

本文介绍了与系统操作相关的接口信息。包括获取系统属性、设置系统属性、设置屏幕亮度、设置hdc状态等。

### 一、获取系统属性

**接口说明**

获取系统属性。

```js
HardwareServiceManager.getSystemApi().getSystemProperty(propertyName: string, defValue?: string)
```

**请求参数** 

| 参数名称     | 参数类型 | 是否必须 | 说明                       |
| ------------ | -------- | -------- | -------------------------- |
| propertyName | string   | true     | 属性名                     |
| defValue     | string   | false    | 默认值，不传默认为空字符串 |

**返回参数**

| 参数类型              | 说明                                                      |
| --------------------- | --------------------------------------------------------- |
| Promise&lt;string&gt; | 成功时 resolved，失败时 rejected<br /> 返回获取到的属性值 |

**请求示例**

```js
HardwareServiceManager.getSystemApi().getSystemProperty(settings.date.AUTO_GAIN_TIME, false).then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 二、设置系统属性

**接口说明**

设置系统属性。

```js
HardwareServiceManager.getSystemApi().setSystemProperty(propertyName: string, value: string)
```

**请求参数** 

| 参数名称     | 参数类型 | 是否必须 | 说明   |
| ------------ | -------- | -------- | ------ |
| propertyName | string   | true     | 属性名 |
| value        | string   | true     | 属性值 |

**返回参数**

| 参数类型              | 说明                             |
| --------------------- | -------------------------------- |
| Promise&lt;string&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getSystemApi().setSystemProperty(settings.date.AUTO_GAIN_TIME, "true").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 三、设置屏幕亮度

**接口说明**

设置屏幕亮度 。

```js
HardwareServiceManager.getSystemApi().setScreenBrightness(value: number, continuous: boolean)
```

**请求参数** 

| 参数名称   | 参数类型 | 是否必须 | 说明                                                         |
| ---------- | -------- | -------- | ------------------------------------------------------------ |
| value      | number   | true     | 亮度的值。范围：0~255                                        |
| continuous | boolean  | True     | 亮度调节是否连续。true表示亮度调节连续，false表示亮度调节不连续。在连续调节亮度过程中，设置continuous为true，结束时设置continuous为false，会有更好的性能 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getSystemApi().setScreenBrightness(100, true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 四、获取 hdc 状态

**接口说明**

获取HDC状态。

```js
HardwareServiceManager.getSystemApi().getHdcStatus()
```

**请求参数：无** 

**返回参数**

| 参数类型                 | 说明                                                         |
| ------------------------ | ------------------------------------------------------------ |
| Promise&lt;boolean[]&gt; | 成功时 resolved，失败时 rejected<br /> 返回HDC状态，数组类型[usb, tcp]，第一位表示usb是否启用，第二位表示tcp是否启用 |

**请求示例**

```js
HardwareServiceManager.getSystemApi().getHdcStatus().then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 五、设置 hdc 状态

**接口说明**

设置 hdc 状态。

```js
HardwareServiceManager.getSystemApi().setHdcStatus(enableUsb: boolean, enableTcp: boolean)
```

**请求参数** 

| 参数名称  | 参数类型 | 是否必须 | 说明                                                         |
| --------- | -------- | -------- | ------------------------------------------------------------ |
| enableUsb | boolean  | true     | 是否启用usb调试，true：启用usb调试，false：不启用usb调试。usb设置无法持久化保存，设置后重启会重置为默认值（启用usb调试） |
| enableTcp | boolean  | true     | 是否启用tcp调试，true：启用tcp调试，false：不启用tcp调试，启用后端口默认为5555 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getSystemApi().setHdcStatus(true, true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```
