# 以太网

更新时间： {docsify-updated} 

本文介绍了与以太网网络相关的接口信息。包括设置 LAN 网口静态 IP、设置 LAN 网口 DHCP、设置 WAN 网口 DHCP、获取 LAN 网口连接状态、获取 WAN 网口连接状态等。

> 目前以太网设置后需要设备重启，设置的以太网IP才会真实生效

#### 一、判断以太网接口是否处于活跃状态

**接口说明**

判断指定的以太网接口是否处于活跃状态（当以太网口插入网线为活跃状态，否则为不活跃）。

```js
HardwareServiceManager.getEthernetApi().isIfaceActive(iface: EthernetIfaceEnum)
```

**请求参数**

| 参数名称 | 参数类型                                                     | 是否必须 | 说明         |
| -------- | ------------------------------------------------------------ | -------- | ------------ |
| iface    | [EthernetIfaceEnum](./docs/property/entity.md#EthernetIfaceEnum) | true     | 网络接口名称 |

**返回参数**

| 参数类型               | 说明                                                         |
| ---------------------- | ------------------------------------------------------------ |
| Promise&lt;boolean&gt; | 成功时 resolved ，失败时 rejected<br /> 返回 resolved 时，如果 boolean 为 true 表示处于活跃状态 |

**请求示例**

```js
HardwareServiceManager.getEthernetApi().isIfaceActive(EthernetIfaceEnum.ETH0).then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 二、获取 LAN  口的配置信息

**接口说明**

获取以太网LAN口的网络配置信息。

```js
HardwareServiceHelper.getInstance().getEthernetLanConfig()
```

**请求参数：**无

**返回参数**

| 参数类型                                                     | 说明                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| Promise&lt;[EthernetConfigEntity](./docs/property/entity.md#EthernetConfigEntity)&gt; | 成功时 resolved ，失败时 rejected<br /> 返回 resolved 时，可以获取到以太网的配置信息 |

**请求示例**

```js
HardwareServiceManager.getEthernetApi().getEthernetLanConfig().then((entity) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 三、获取 LAN 网口 MAC 地址

**接口说明**

获取以太网LAN口MAC地址。

```js
HardwareServiceHelper.getInstance().getEthernetLanMac()
```

**请求参数：**无

**返回参数**

| 参数类型              | 说明                                                         |
| --------------------- | ------------------------------------------------------------ |
| Promise&lt;string&gt; | 成功时 resolved ，失败时 rejected<br /> 返回 resolved 时，可以获取到 LAN 口的 MAC 地址 |

**请求示例**

```js
HardwareServiceManager.getEthernetApi().getEthernetLanMac().then((result) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 四、获取 WAN  口的配置信息

**接口说明**

获取以太网 WAN 口的网络配置信息。

```js
HardwareServiceHelper.getInstance().getEthernetWanConfig()
```

**请求参数：**无

**返回参数**

| 参数类型                                                     | 说明                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| Promise&lt;[EthernetConfigEntity](./docs/property/entity.md#EthernetConfigEntity)&gt; | 成功时 resolved ，失败时 rejected<br /> 返回 resolved 时，可以获取到以太网的配置信息 |

**请求示例**

```js
HardwareServiceManager.getEthernetApi().getEthernetWanConfig().then((entity) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 五、获取指定以太网接口的配置信息

**接口说明**

获取指定以太网接口的配置信息。

```js
HardwareServiceHelper.getInstance().getEthernetConfig(iface: EthernetIfaceEnum)
```

**请求参数**

| 参数名称 | 参数类型                                                     | 是否必须 | 说明         |
| -------- | ------------------------------------------------------------ | -------- | ------------ |
| iface    | [EthernetIfaceEnum](./docs/property/entity.md#EthernetIfaceEnum) | true     | 网络接口名称 |

**返回参数**

| 参数类型                                                     | 说明                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| Promise&lt;[EthernetConfigEntity](./docs/property/entity.md#EthernetConfigEntity)&gt; | 成功时 resolved ，失败时 rejected<br /> 返回 resolved 时，可以获取到以太网的配置信息 |

**请求示例**

```js
HardwareServiceManager.getEthernetApi().getEthernetConfig(EthernetIfaceEnum.ETH0).then((entity) => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 六、设置以太网 LAN 口网络配置信息

**接口说明**

设置以太网 LAN 口网络配置信息。

```js
HardwareServiceHelper.getInstance().setEthernetLanConfig(config: EthernetConfigEntity)
```

**请求参数**

| 参数名称 | 参数类型                                                     | 是否必须 | 说明                                                         |
| -------- | ------------------------------------------------------------ | -------- | ------------------------------------------------------------ |
| config   | [EthernetConfigEntity](./docs/property/entity.md#EthernetConfigEntity) | true     | 以太网的配置信息。如果是设置为 DHCP 则只需要将 mode 字段传入 EthernetModeEnum.DHCP 即可，其他字段可不传 |

**返回参数**

| 参数类型              | 说明                              |
| --------------------- | --------------------------------- |
| Promise&lt;string&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
const config: EthernetConfigEntity =
          new EthernetConfigEntity(this.ip, this.gateway, this.subnetMask, this.dnsServers)

HardwareServiceManager.getEthernetApi().setEthernetLanConfig(config).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 七、设置以太网 WAN 口网络配置信息

**接口说明**

设置以太网 WAN 口网络配置信息。

```js
HardwareServiceHelper.getInstance().setEthernetWanConfig(config: EthernetConfigEntity)
```

**请求参数**

| 参数名称 | 参数类型                                                     | 是否必须 | 说明                                                         |
| -------- | ------------------------------------------------------------ | -------- | ------------------------------------------------------------ |
| config   | [EthernetConfigEntity](./docs/property/entity.md#EthernetConfigEntity) | true     | 以太网的配置信息。如果是设置为 DHCP 则只需要将 mode 字段传入 EthernetModeEnum.DHCP 即可，其他字段可不传 |

**返回参数**

| 参数类型              | 说明                              |
| --------------------- | --------------------------------- |
| Promise&lt;string&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
const config: EthernetConfigEntity =
          new EthernetConfigEntity(this.ip, this.gateway, this.subnetMask, this.dnsServers)

HardwareServiceManager.getEthernetApi().setEthernetWanConfig(config).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 八、设置指定以太网接口的配置信息

**接口说明**

设置指定以太网接口的配置信息。

```js
HardwareServiceHelper.getInstance().setEthernetConfig(iface: EthernetIfaceEnum, config: EthernetConfigEntity)
```

**请求参数**

| 参数名称 | 参数类型                                                     | 是否必须 | 说明                                                         |
| -------- | ------------------------------------------------------------ | -------- | ------------------------------------------------------------ |
| iface    | [EthernetIfaceEnum](./docs/property/entity.md#EthernetIfaceEnum) | true     | 网络接口名称                                                 |
| config   | [EthernetConfigEntity](./docs/property/entity.md#EthernetConfigEntity) | true     | 以太网的配置信息。如果是设置为 DHCP 则只需要将 mode 字段传入 EthernetModeEnum.DHCP 即可，其他字段可不传 |

**返回参数**

| 参数类型              | 说明                              |
| --------------------- | --------------------------------- |
| Promise&lt;string&gt; | 成功时 resolved ，失败时 rejected |

**请求示例**

```js
const config: EthernetConfigEntity =
          new EthernetConfigEntity(this.ip, this.gateway, this.subnetMask, this.dnsServers)

HardwareServiceManager.getEthernetApi().setEthernetWanConfig(EthernetIfaceEnum.ETH0, config).then(() => {
  // do something
}).catch((err: BusinessError) => {
  // do something
})
```

#### 九、注册以太网事件监听

**接口说明**

通过注册事件回调用于监听 LAN 与 WAN 口状态变化。

```java
HardwareServiceHelper.getInstance().on(listener: IEthernetStateCallback)
```

**请求参数**

| 参数名称 | 参数类型               | 是否必须 | 说明                                                     |
| -------- | ---------------------- | -------- | -------------------------------------------------------- |
| listener | IEthernetStateCallback | true     | 以太网状态回调监听器。返回网络接口名称和激活状态两个字段 |

**返回参数：无**

**请求示例**

```js
private ethernetCallback: IEthernetStateCallback = {
    onStatusInfo: (iface, status) => {
      console.log(`${iface} 状态改变: ${status}`)
    }
  }

HardwareServiceHelper.getInstance().on(ethernetCallback)
```

#### 十、注销以太网事件监听

**接口说明**

用于注销 LAN 与 WAN 口状态变化的监听。

```js
HardwareServiceHelper.getInstance().off(listener: IEthernetStateCallback)
```

**请求参数**

| 参数名称 | 参数类型               | 是否必须 | 说明                                         |
| -------- | ---------------------- | -------- | -------------------------------------------- |
| listener | IEthernetStateCallback | true     | 监听器。必须和注册时传入的监听器是同一个实例 |

**返回参数：无**

**请求示例**

```js
private ethernetCallback: IEthernetStateCallback = {
    onStatusInfo: (iface, status) => {
      console.log(`${iface} 状态改变: ${status}`)
    }
  }

HardwareServiceHelper.getInstance().off(ethernetCallback)
```

