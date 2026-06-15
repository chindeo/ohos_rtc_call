# 快速集成

更新时间： {docsify-updated} 

本文将介绍如何将 **硬件服务har** 包集成到您的开发环境中。

### 创建 OpenHarmony 工程

在 DevEco Studio 中新建工程。

### 下载开发资源包

`hardware_service_sdk_VXXX.har` 包为核心库，提供硬件服务的所有API接口实现，开发者需要集成此库以调用相关功能接口。`示例demo` 中展示了 har 包中核心接口的调用流程，提供可运行的代码模版，帮助开发者快速上手。

点击下载 har： [hardware_service_sdk_V1.0.0_20260315.har](http://icloudobs.aurine.cn:7002/aurine-system-development/docs/hardware-service-ohos/har/v1.0.0/hardware_service_sdk_V1.0.0_20260315.har)

点击下载示例 demo：[HardwareServiceDemo.zip](http://icloudobs.aurine.cn:7002/aurine-system-development/docs/hardware-service-ohos/demo/v1.0.0/HardwareServiceDemo.zip)

点击下载硬件服务 app：[HardwareService_V1.0.0_20260315.hap](http://icloudobs.aurine.cn:7002/aurine-system-development/docs/hardware-service-ohos/hap/v1.0.0/HardwareService_V1.0.0_20260315.hap)

> 一般情况下系统会内置硬件服务APP，不需要通过此处进行下载。如果存在系统中内置的硬件服务APP版本较低，可以通过此处进行下载覆盖安装

### 导入开发资源包

1. 将上方下载的 **har** 文件放入项目的 **libs** 目录下（har 包文件名称以上方实际下载的 har 文件名称为准）。
   ![](http://icloudobs.aurine.cn:7002/aurine-system-development/docs/hardware-service-ohos/images/8918c416-2efe-420b-8157-925a47d0366f.png)
   
2. 在 **oh-package.json5** 中添加依赖

   ```js
     "dependencies": {
       "@mili/hardware_service_sdk": "file:./libs/hardware_service_sdk_V1.0.0_20251203.har",
     }
   ```
   
3. DevEco Studio 点击右上角的 Sync Now，同步编译项目。

4. 验证 har 包是否导入成功。复制以下代码到自身项目中，查看是否可以成功引用到 HardwareServiceManager 类，然后运行项目查看集成的 har 包版本与实际下载的 har 包版本是否一致。

   ```js
   // 获取当前集成的 har 包版本
   const version = HardwareServiceManager.getCoreApi().getSDKVersion()
   ```

### 权限申请

无