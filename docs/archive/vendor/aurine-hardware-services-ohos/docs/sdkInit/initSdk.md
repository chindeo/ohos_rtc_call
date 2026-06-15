# 初始化SDK

更新时间： {docsify-updated} 

本文将介绍SDK初始化方法与绑定硬件APP服务并与之建立通信连接，只有与硬件APP服务建立通信后才能调用相关API方法。

如果项目中有除主线程/主进程外的其他线程/进程环境，并且其他线程/进程中也有使用硬件服务SDK接口，需要保证其他线程/进程起来时也需要调用SDK初始化与绑定硬件服务

### 一、初始化SDK

**接口说明**

初始化SDK，请优先调用该接口进行SDK初始化

```js
HardwareServiceManager.getCoreApi().init(context: Context, iLogger?: ILoggerPrinter)
```

**请求参数**

| 参数名称 | 参数类型       | 是否必须 | 说明                                                         |
| -------- | -------------- | -------- | ------------------------------------------------------------ |
| context  | Context        | true     | 上下文                                                       |
| iLogger  | ILoggerPrinter | false    | 日志拦截器<br /> SDK内部会有日志打印，如果外部需要获取这些日志打印可以传入该参数用于拦截SDK内部的日志输出，如果外部传入了该参数，SDK内部的日志输出将会被重定向到该拦截器，外部拦截到日志后可以自行处理这些日志，比如保存到本地 |

**返回参数：无**

**请求示例**

```js
HardwareServiceManager.getCoreApi().init(this.context, {
  // 拦截SDK内部的日志输出，拦截后SDK内部将不会在控制台输出日志，外部可以自行处理这些日志，比如输出到控制台或者本地保存
  printer: (logLevel, domain, tag, format, ...logInfo: LoggerType[]) => {
    switch (logLevel) {
      case hilog.LogLevel.DEBUG:
        hilog.debug(domain, tag, format, ...logInfo);
        break
      case hilog.LogLevel.INFO:
        hilog.info(domain, tag, format, ...logInfo);
        break
      case hilog.LogLevel.WARN:
         hilog.warn(domain, tag, format, ...logInfo);
         break
      case hilog.LogLevel.ERROR:
         hilog.error(domain, tag, format, ...logInfo);
         break
  	case hilog.LogLevel.FATAL:
         hilog.fatal(domain, tag, format, ...logInfo);
         break
    }
  }
})
```

!> **注意事项** <br /> SDK内部默认会在控制台输出日志，可以通过过滤 `HardwareServerSDK` 关键字查看相关日志输出。如果外部传入了ILoggerPrinter参数，SDK内部的日志将不会在控制台输出，而是由ILoggerPrinter返回交由第三方开发者自行实现

### 二、绑定硬件服务

**接口说明** 

绑定硬件服务。只有绑定硬件服务成功才能调用相关api，否则将会返回失败

```js
HardwareServiceManager.getCoreApi().bindHardwareService(context: common.UIAbilityContext, callback?: Callback<boolean>)
```

**请求参数**

| 参数名称 | 参数类型                | 是否必须 | 说明                                                         |
| -------- | ----------------------- | -------- | ------------------------------------------------------------ |
| context  | UIAbilityContext        | true     | Ability 上下文                                               |
| callback | Callback&lt;boolean&gt; | false    | 绑定结果回调：<br /> true：绑定成功，此时可以调用相关api<br /> false：绑定失败，失败原因可以通过查看控制台日志输出获取 |

**返回参数：无**

**请求示例**

```js
HardwareServiceManager.getCoreApi().bindHardwareService(this.context, (status) => {
  // do something
})
```

### 三、解绑硬件服务

**接口说明** 

解除与硬件服务的绑定。解绑后将不能再调用相关api

```js
HardwareServiceManager.getCoreApi().unBindHardwareService()
```

**请求参数：无**

**返回参数**

| 参数类型             | 说明                             |
| -------------------- | -------------------------------- |
| Promise &lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getCoreApi().unBindHardwareService().then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

!> **注意事项** <br /> 解绑成功后将不能再调用 SDK 提供的接口。<br />
