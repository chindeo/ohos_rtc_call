# 对象说明

### DeviceModelEntity

 设备模型实体类，描述设备硬件功能和支持情况。

| 字段                | 类型           | 说明                                                 |
| ------------------- | -------------- | ---------------------------------------------------- |
| deviceModel         | string         | 设备型号（后期通过工具烧录进去的型号）               |
| romModel            | string         | 设备 ROM 型号                                        |
| deviceType          | DeviceTypeEnum | 设备类型，用于描述当前设备类型（医护、中控、室内机） |
| chipScheme          | ChipSchemeEnum | 设备芯片方案                                         |
| sn                  | string         | 设备sn                                               |
| mac                 | string         | 设备Mac                                              |
| enableEthernetLan   | boolean        | 是否支持以太网lan口                                  |
| enableEthernetWan   | boolean        | 是否支持以太网wan口                                  |
| enableWifi          | boolean        | 是否支持wifi                                         |
| enableBluetooth     | boolean        | 是否支持蓝牙                                         |
| enableMobilenet     | boolean        | 是否支持4G                                           |
| enableZigbee        | boolean        | 是否支持zigbee                                       |
| enableDeviceLight   | boolean        | 是否支持氛围灯                                       |
| enableRGBLight      | boolean        | 是否支持RGB三色灯                                    |
| enableCard          | boolean        | 是否支持刷卡                                         |
| enableCamera        | boolean        | 是否支持摄像头                                       |
| enableTelephone     | boolean        | 是否支持听筒                                         |
| enableHandle        | boolean        | 是否支持手柄                                         |
| enablePowerKey      | boolean        | 是否支持电源键                                       |
| enableKnob          | boolean        | 是否支持旋钮                                         |
| keyNum              | number[]       | 设备按键，数组存放支持的按键值，空数组表示不支持按键 |
| relayNum            | number         | 继电器，数值是支持几路继电器，0表示不支持            |
| launcherPackageName | string         | launcher应用包名                                     |

!> **注意事项** <br /> DeviceModelEntity 中的字段值只与型号有关跟实际设备硬件是否支持该能力无关，同款硬件，如果型号不一样，则值也可能不一样。<br /> 比如一款硬件设备它硬件上与标准api接口都支持WiFi与蓝牙，有 A、B两个型号，这两个型号都可以烧录到该硬件设备上。其中A型号的程序我不想让他有WiFi和蓝牙功能，B型号有WiFi与蓝牙功能，此时在设备上烧录A型号后获取到的enableWifi与enableBluetooth值就是false，虽然是false，但是你依然可以用标准api去操作WiFi与蓝牙，烧B型号enableWifi与enableBluetooth返回的值就是true。<br />除 deviceModel、romModel、deviceType、chipScheme、sn、mac 字段外，其他的字段未必一定符合当前设备的硬件能力，开发时以实际为准，或者咨询对接的技术人员。

### EthernetConfigEntity

以太网网络配置数据

| 字段       | 类型                                                         | 说明                                                       |
| ---------- | ------------------------------------------------------------ | ---------------------------------------------------------- |
| iface      | [EthernetIfaceEnum](./docs/property/entity.md#EthernetIfaceEnum) | 以太网接口名称：eth0、eth01                                |
| mode       | [EthernetModeEnum](./docs/property/entity.md#EthernetModeEnum) | 以太网连接的配置模式，静态配置、动态配置                   |
| ipAddr     | string                                                       | IP地址                                                     |
| route      | string                                                       | 以太网连接静态配置路由信息                                 |
| gateway    | string                                                       | 网关                                                       |
| netMask    | string                                                       | 子网掩码                                                   |
| dnsServers | string                                                       | 以太网连接已配置dns服务地址，多个dns地址之间用英文逗号分割 |

### EthernetIfaceEnum

网络接口名称枚举

| 字段    | 说明   |
| ------- | ------ |
| ETH0    | ETH0   |
| ETH1    | ETH1   |
| WLAN0   | WLAN0  |
| UNKNOWN | 未知的 |

### EthernetModeEnum

以太网模式枚举

| 字段   | 说明     |
| ------ | -------- |
| STATIC | 静态网络 |
| DHCP   | 动态网络 |

### AudioDeviceTypeEnum

音频设备类型枚举

| 字段     | 说明             |
| -------- | ---------------- |
| EARPIECE | 耳机、听筒、手柄 |
| SPEAKER  | 扬声器、机身     |

