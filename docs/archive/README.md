# 归档说明

本目录只保留无法完全改写为维护规则的原始厂家资料。

## 保留内容

- `vendor/dnake-v769-sdk.md`：Dnake 设备 SDK 原始资料。
- `vendor/shimeta-openharmony-device-api.md`：Shimeta OpenHarmony 设备能力原始资料。
- `vendor/aurine-hardware-services-ohos/`：Aurine 硬件服务原始资料。

## 已整合并删除的内容

- nurse/bed 的 `AGENTS.md` 和 `todo.md` 已整合进顶层 `AGENTS.md`、`audio-video-maintenance-roadmap.md`、`host-bed-project-notes.md`。
- WebRTC 音频诊断和 native audio findings 已整合进 `webrtc-audio-diagnostics.md`。
- `libwebrtc.md` 是大体量 API 参考，不作为本项目维护文档保留；实际通话约束已整理进顶层 WebRTC 文档。
- 临时日志、截图和独立 call app 旧方案文档不作为长期资料保留；有用结论已沉淀到顶层文档。

## 维护规则

- 不按来源项目重复归档同一份文档。
- 新增厂家原始资料时放入 `vendor/`，并在顶层维护文档提炼实际接入规则。
- 归档资料进入仓库前必须脱敏，不能包含真实设备地址、token、密码、本机绝对路径或临时 HAR 文件名。
