# 包管理

更新时间： {docsify-updated} 

本文介绍了包管理相关的接口信息。包含安装hap、清除应用缓存、系统OTA等。

### 一、安装 hap

**接口说明**

安装 hap 应用，支持同时安装多个 hap。

```js
HardwareServiceManager.getBundleApi().installHap(hapFilePaths: Array<string>, isReboot: boolean)
```

**请求参数**

| 参数名称     | 参数类型 | 是否必须 | 说明                                                         |
| ------------ | -------- | -------- | ------------------------------------------------------------ |
| hapFilePaths | string   | true     | hap 文件路径，支持传入多个 hap 路径，hap 包需要放在 /data/updater 目录下 |
| isReboot     | boolean  | true     | 安装成功后是否需要重启，如果为 true，安装成功后过2s将会重启系统。如果是安装 launcher 建议始终传入 true，否则不会被自动重新拉起 |

**返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getBundleApi().installHap(["/data/updater/xxx.hap"], true).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 二、回滚应用到初次安装时的状态

**接口说明**

回滚应用到初次安装时的状态。

```js
HardwareServiceManager.getBundleApi().recoverHap(bundleName: string)
```

**请求参数**

| 参数名称   | 参数类型 | 是否必须 | 说明               |
| ---------- | -------- | -------- | ------------------ |
| bundleName | string   | true     | 需要回滚的应用包名 |

**返回参数**

| 参数类型            | 说明                              |
| ------------------- | --------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getBundleApi().recoverHap("com.xxx.xxx").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 三、清理应用缓存数据

**接口说明**

清理指定应用缓存数据，清除该应用全局与各hap包目录下的 cache 与 temp 目录下的文件。

```js
HardwareServiceManager.getBundleApi().cleanBundleCacheFiles(bundleName: string)
```

**请求参数**

| 参数名称   | 参数类型 | 是否必须 | 说明     |
| ---------- | -------- | -------- | -------- |
| bundleName | string   | true     | 应用包名 |

**返回参数**

| 参数类型               | 说明                              |
| ---------------------- | --------------------------------- |
| Promise&lt;boolean&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getBundleApi().cleanBundleCacheFiles("com.xxx.xxx").then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 四、清除应用全部数据

**接口说明**

清除应用的全部数据。

```js
HardwareServiceManager.getBundleApi().clearUpApplicationData(bundleName: string)
```

**请求参数**

| 参数名称   | 参数类型 | 是否必须 | 说明     |
| ---------- | -------- | -------- | -------- |
| bundleName | string   | true     | 应用包名 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getBundleApi().clearUpApplicationData("com.xxx.xxx").then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

### 五、OTA

**接口说明**

系统 OTA 升级。

```js
HardwareServiceManager.getBundleApi().ota(otaFilePath: string)
```

**请求参数**

| 参数名称    | 参数类型 | 是否必须 | 说明                                              |
| ----------- | -------- | -------- | ------------------------------------------------- |
| otaFilePath | string   | true     | ota 文件路径，ota 包需要放在 /data/updater 目录下 |

**返回参数**

| 参数类型            | 说明                             |
| ------------------- | -------------------------------- |
| Promise&lt;void&gt; | 成功时 resolved，失败时 rejected |

**请求示例**

```js
HardwareServiceManager.getBundleApi().ota("data/updater/ota.zip").then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```
