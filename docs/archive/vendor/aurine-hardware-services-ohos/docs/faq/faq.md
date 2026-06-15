# 常见问题

更新时间： {docsify-updated} 

### 一、是否可以提供远程 maven 库，通过远程方式进行SDK集成?

目前只提供 har 包，只支持通过本地依赖 har 包的方式进行 SDK 集成。

### 二、应用起来后调用SDK接口发现调用失败

- 检查是否有调用了初始化版本远程服务接口：HardwareServiceManager.getCoreApi().bindHardwareService(context: common.UIAbilityContext, callback?: Callback<boolean>)。
- 检查是否是在收到 Callback 函数回调前就调用了SDK接口，如果还未收到 Callback 函数回调就调用 SDK 接口将会导致接口调用失败。

### 三、项目无法安装到设备

项目安装的时候提示以下的错误

![ef689833d4ea63819635b29e5df7c3d3](http://icloudobs.aurine.cn:7002/aurine-system-development/docs/hardware-service-ohos/images/20260310163250_693_174.png)

该错误的原因是因为项目配置的 api 版本不对，目前我们的设备是 openahrmony 5.1.0 系统，所以需要在项目根目录下的 build-profile.json5 文件中，将 compatibleSdkVersion、compileSdkVersion、targetSdkVersion 的版本号改到18	

### 四、OTA升级文件权限问题

- oat 的文件一定要保存到 /data/updater  目录下
- 调用 HardwareServiceManager.getBundleApi().ota() 接口进行 ota 升级时，再将 ota 包的路径传入接口
