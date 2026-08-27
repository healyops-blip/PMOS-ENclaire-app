# Issue #26：医院认证本地交互演示

## 产品边界

本功能只存在于 Flutter 客户端，是绑定材料修订的交互演示。它不调用
FastAPI 认证接口，不连接医院、医生身份系统、电子签名、数字证书或区块链
网络，也不会生成交易哈希、医院公章、医生签名或对外验证地址。

“提供区块链技术支持”是产品指定的小字，页面同时固定显示“仅限本地交互
演示”“不代表真实认证”和完整免责声明，前者不能替代后者。

## 显示条件

`CertificationEntryCard` 只在以下条件同时满足时构建入口：

- OCR 已由用户确认；
- `document_id` 非空；
- `document_revision_id` 非空；
- 该修订仍是当前可用修订。

化验报告、医嘱／处方、影像文字报告和门诊病历复用同一个入口组件。未确认、
缺少标识、已删除或已经换版的材料不得启动演示。

## 本地状态机

状态固定为：

```text
not_started -> processing -> succeeded
                         \-> failed -> processing -> succeeded/failed
```

- 默认演示路径约 1.4 秒后成功；处理中禁用按钮。
- 只有 `succeeded` 显示集中配置的“本地认证演示”水印。
- 自动化测试可注入“首次失败”计划，普通生产页面不暴露失败开关。
- `processing` 会保存开始时间和待完成的本地演示结果；离开页面或重启 App
  后再次加载时按剩余时间恢复，超时则立即完成，不会永久卡住。

## 存储和修订隔离

`CertificationRepository` 是独立抽象，当前唯一生产实现使用
`SharedPreferencesAsync`。存储键由 `document_id + revision_id` 共同编码，记录
不会按材料 ID 跨修订继承。旧修订记录可以保留，但材料替换得到新的
`revision_id` 后，新修订从 `not_started` 开始。

本地记录只包含演示状态、更新时间、尝试次数和处理中恢复信息。它不包含医疗
正文、医生身份或链上字段。清除应用数据或卸载后记录允许重置；服务端不会从
本地记录恢复，也不会因认证演示被修改。

## 数据流隔离

认证页面只依赖 `CertificationRepository`，不依赖 `PomiApiClient`、
`OcrRepository`、用药 Repository 或报告 Repository。状态变化不会触发 OCR
重跑、材料替换、正式记录修改、用药对账或报告重建。未来若立项真实认证，必须
新增独立远程 Repository、服务端数据模型和经评审的 OpenAPI 版本，不能改变
当前本地实现的语义。

## 验证

自动化覆盖：

- 四项入口资格条件；
- `not_started -> processing -> succeeded`；
- `failed -> retry -> processing -> succeeded`；
- 处理中不显示水印、成功后才显示；
- 页面恢复处理中状态；
- 同材料不同修订、不同材料相同修订的状态隔离；
- 普通构建页面无失败模拟按钮及虚构认证字段。

Android 模拟器和真机仍需在发版验收时走完成功、失败测试构建、重试、重启和
材料换版五条人工路径。
