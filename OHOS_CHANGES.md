# OHOS 支持改动说明

本次在 `flutter_secure_storage` 10.3.1 的基础上增加独立的 OHOS 平台包。业务侧仍使用主包的 `FlutterSecureStorage` API，无需引入 OHOS 子包或添加平台判断。

## 改动范围

| 位置 | 改动 |
| --- | --- |
| `flutter_secure_storage/pubspec.yaml` | 增加 `flutter_secure_storage_ohos` 路径依赖，并将其声明为 `ohos` 的 `default_package`。路径依赖无法发布到 pub.dev，因此主包设置 `publish_to: none`。 |
| `flutter_secure_storage/lib/flutter_secure_storage.dart` | `_selectOptions()` 在 OHOS 上返回空选项 Map，使现有读写入口能够继续调用平台接口。 |
| `flutter_secure_storage_ohos/pubspec.yaml` | 声明该包实现 `flutter_secure_storage`，并注册 OHOS 原生插件类。依赖 2.x 平台接口。 |
| `flutter_secure_storage_ohos/ohos/` | 新增原生插件注册、方法通道和安全存储实现。 |

## OHOS 实现

原生插件沿用 2.x 平台接口使用的 `plugins.it_nomads.com/flutter_secure_storage` 方法通道，处理 `write`、`read`、`containsKey`、`delete`、`readAll` 和 `deleteAll`。Dart 层传入的 `key`、`value`、`options` 中，OHOS 实现使用 `key` 和 `value`；目前没有 OHOS 专属选项。

数据使用 HUKS 中的 AES-256-GCM 密钥加密，Preferences 保存带版本号的密文，每次写入生成新的 nonce。读取不存在的键返回 `null`，原生操作失败通过方法通道返回错误。

## 验证与限制

- 主包与 OHOS 子包的 `flutter analyze` 均通过。
- 主包 `flutter test` 的 93 个测试全部通过。
- OHOS 示例的 debug HAP 构建通过，生成的插件注册代码包含 `FlutterSecureStorageOhosPlugin`。
- 尚未在 OHOS 设备上验证实际读写；当前实现不会迁移 CPF 1.2.2 写入的旧数据。
