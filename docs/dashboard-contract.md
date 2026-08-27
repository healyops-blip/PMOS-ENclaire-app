# Dashboard 聚合与离线契约

`GET /api/dashboard` 只使用 Bearer session 中的 UID，不接受患者 ID。服务端业务日期由
`POMI_BUSINESS_TIMEZONE` 决定。除认证等全局错误外，响应始终为 HTTP 200；四个区块各自
返回 `status: ok | empty | error`、`data` 和稳定错误码，单个区块失败不影响其他区块。

- `follow_up.data`: `next_visit_date`、`state`（`upcoming | due | overdue`）和非负的
  `days_remaining`；未设置日期时为空。
- `today_medications.data`: 当天应服药物及其 `daily.intake_status`，暂停、停用、尚未生效
  和已被调药版本替代的记录不会出现。
- `monthly_medication_summary.data`: 从当月 1 日至业务日期的 `taken`、`missed`、
  `unrecorded`，按“有效药物 × 应服日期”计算，不输出依从率。
- `latest_report.data`: 报告模块尚未生成报告时为空，不返回模拟报告。

Flutter 的 `DashboardRepository` 负责 DTO 转换。联网成功后按 UID 将最后一次成功响应写入
`flutter_secure_storage`；Android 上由 Keystore 保护加密存储密钥。断网时只能读取当前 UID
的缓存，显示缓存时间并禁用用药、经期和体重写操作。账号切换、退出登录和账号删除流程
必须调用 `DashboardRepository.clear(uid)`，且缓存不包含原始医疗文件或报告正文。
