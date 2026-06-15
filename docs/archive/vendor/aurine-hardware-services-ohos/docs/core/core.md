# 核心/基础功能

更新时间： {docsify-updated} 

本文介绍了核心/系统基础功能相关的接口信息。包含获取硬件服务绑定状态、获取SDK版本号、打开厂测应用等。

### 一、获取SDK版本号

**接口说明**

获取当前集成的SDK版本号

```js
HardwareServiceManager.getCoreApi().getSDKVersion()
```

**请求参数：无**

**返回参数**

| 参数类型 | 说明   |
| -------- | ------ |
| string   | 版本号 |

**请求示例**

```js
const version = HardwareServiceManager.getCoreApi().getSDKVersion()
```

### 二、获取硬件服务绑定状态

**接口说明**

判断是否已经成功绑定了硬件服务，只有成功绑定硬件服务后才能调用相关api

```js
HardwareServiceManager.getCoreApi().isBind()
```

**请求参数：无**

**返回参数**

| 参数类型 | 说明                                                         |
| -------- | ------------------------------------------------------------ |
| boolean  | 是否已经成功版本硬件服务<br /> true：已经绑定成功 <br /> false：未绑定或者还未绑定成功 |

**请求示例**

```js
const isBind = HardwareServiceManager.getCoreApi().isBind()
```

### 三、注册硬件服务绑定状态回调

**接口说明**

注册回调，监听硬件服务绑定状态回调，当硬件服务绑定成功或者断开绑定连接时将会触发该回调

```js
HardwareServiceManager.getCoreApi().registerBindStatusCallback(callback: Callback<boolean>)
```

**请求参数**

| 参数名称 | 参数类型                | 是否必须 | 说明                                                    |
| -------- | ----------------------- | -------- | ------------------------------------------------------- |
| callback | Callback&lt;boolean&gt; | true     | 回调函数<br /> true：成功绑定<br /> false：断开绑定连接 |

**返回参数：无**

**请求示例**

```js
private bindStatusCallback = (status: boolean): void => {
  // do something
}

HardwareServiceManager.getCoreApi().registerBindStatusCallback(this.bindStatusCallback)
```

### 四、注销硬件服务绑定状态回调

**接口说明**

注监听硬件服务绑定状态回调

```js
HardwareServiceManager.getCoreApi().unregisterBindStatusCallback(callback: Callback<boolean>)
```

**请求参数**

| 参数名称 | 参数类型                | 是否必须 | 说明                             |
| -------- | ----------------------- | -------- | -------------------------------- |
| callback | Callback&lt;boolean&gt; | true     | 需要传入注册回调时传入的callback |

**返回参数：无**

**请求示例**

```js
private bindStatusCallback = (status: boolean): void => {
  // do something
}

HardwareServiceManager.getCoreApi().unregisterBindStatusCallback(this.bindStatusCallback)
```

### 五、打开厂测应用

**接口说明**

打开厂测应用并进入测试页面

```js
HardwareServiceManager.getCoreApi().openFactoryTestPage(context: common.UIAbilityContext, parameters?: Record<string, Object>)
```

**请求参数**

| 参数名称   | 参数类型               | 是否必须 | 说明                 |
| ---------- | ---------------------- | -------- | -------------------- |
| context    | UIAbilityContext       | true     | Ability 上下文       |
| parameters | Record<string, Object> | false    | 跳转时携带的参数信息 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getCoreApi()
  .openFactoryTestPage(this.getUIContext().getHostContext() as common.UIAbilityContext, { "xxx": "xxxx" })
  .then(_ => {
     // do something
  })
  .catch((err: BusinessError) => {
     // do something
  })
})
```

!>注意事项<br /> 该接口第三方在对接时必须进行实现<br />
 系统内置了一个厂测应用用于测试验证设备相关硬件功能（比如继电器、WiFi、屏幕、灯等）是否正常。设备出厂时，生产人员会开机一次并用厂测应用验证硬件功能是否正常，所以需要第三方开发者在自己的应用中增加一个隐蔽入口，点击调用该方法打开我们的厂测页面。并且该入口需要尽可能的简便，比如可以在开机引导页面或者程序首页增加一个隐蔽入口，通过点击/多次点击/长按等方法打开厂测应用，方便生产进行测试验证<br /> 第三方在实现完该接口后，需要将如何跳转到厂测的方式告知我司的对接人员，方便我司进行归档与移交送测

