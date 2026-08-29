# Pomi 前端联调接口

更新日期：2026-08-27

本文档仅列出已合入并可用于前端联调的后端接口。完整字段、枚举和约束以 `contracts/openapi/pomi-api-v1.yaml` 为准。

## 1. 环境与通用约定

| 环境 | Base URL |
|---|---|
| 生产 | `https://api.healy1012-ops.top` |
| 本地 | `http://127.0.0.1:8000` |

生产已部署 `main@048039836e608fd4207dda094c5e00f225268810`，数据库版本为 `20260827_0027`。下列章节只描述该 release 已实现的接口。

- 健康检查和认证接口以外，请求头都必须携带 `Authorization: Bearer <session_id>`。
- `session_id` 由登录接口返回，只存放在 Android/iOS 安全存储中，不得写入日志、埋点或普通缓存。
- 日期使用 `YYYY-MM-DD`；时间使用带时区的 ISO 8601。
- 业务响应使用统一包络；认证接口保持直接响应。
- 服务端通过 Session 确定 UID，前端不传患者 UID 用于鉴权。

业务成功包络：

```json
{
  "success": true,
  "data": {},
  "request_id": "request-id",
  "error": null
}
```

业务失败包络：

```json
{
  "success": false,
  "data": null,
  "request_id": "request-id",
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid fields.",
    "retryable": false,
    "details": {}
  }
}
```

前端应保留响应头 `X-Request-ID` 用于联调排查，但不应记录 Authorization 值。

## 2. 认证与健康检查

| 方法 | 路径 | 认证 | 成功状态 | 说明 |
|---|---|---:|---:|---|
| `GET` | `/health/live` | 否 | 200 | 进程存活 |
| `GET` | `/health/ready` | 否 | 200 | 进程与数据库就绪 |
| `POST` | `/api/auth/register` | 否 | 201 | 注册，不自动登录 |
| `POST` | `/api/auth/login` | 否 | 200 | 返回 Session |
| `GET` | `/api/auth/me` | 是 | 200 | 恢复当前账号 |
| `POST` | `/api/auth/logout` | 是 | 204 | 幂等撤销 Session，无响应体 |

注册请求：

```json
{
  "account_name": "new-user",
  "password": "StrongPass123",
  "phone_number": "+8613812345678"
}
```

登录请求：

```json
{
  "account_name": "new-user",
  "password": "StrongPass123",
  "client_platform": "android",
  "device_name": "Pixel Emulator"
}
```

登录成功响应的核心字段为 `session_id`、`token_type`、`expires_at` 和 `account`。认证失败、Session 过期或已撤销时返回 401；前端应清理本地 Session 并返回登录页。

## 3. 患者画像

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `/api/patient/profile` | 获取当前 Session 对应画像 |
| `PUT` | `/api/patient/profile` | 分步保存或编辑画像 |

`PUT` 接受：`nickname`、`birth_date`、`gender`、`height_cm`、`diagnosis_year`、`primary_condition`、`next_visit_date`、`health_goal`、`complete_onboarding`、`updated_at`。未定义字段返回 422。

- `gender`: `female | male | other | prefer_not_to_say`
- `height_cm`: 100–230，最多一位小数
- `complete_onboarding=true` 只用于首次完成引导；普通编辑不要重复传 true
- 编辑时建议携带最后读取的 `updated_at` 做并发保护

## 4. Dashboard 聚合

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `/api/dashboard` | 一次读取复诊、今日用药、本月三态统计和最新成功报告元数据 |

响应包含 `business_date`，以及四个相互独立的 section：`follow_up`、`today_medications`、`monthly_medication_summary`、`latest_report`。每个 section 都有：

```json
{
  "status": "ok",
  "data": {},
  "error": null
}
```

- `status`: `ok | empty | error`
- 单个 section 失败不会令其他 section 一起失败。
- `latest_report` 只返回 `report_id`、`status`、`generated_at`、`snapshot_hash`，不会在 Dashboard 泄露报告正文。
- 网络刷新失败时，前端可以展示当前 UID 的加密缓存，但必须标记离线或 stale 时间；401 时必须清除该 UID 的缓存和内存数据。

## 5. 用药与每日三状态

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `/api/medications?status=active|paused|stopped` | 用药列表、分组与服务器业务日期 |
| `POST` | `/api/medications` | 新增用药，必须携带 `Idempotency-Key` |
| `PUT` | `/api/medications/{medication_id}` | 调整、暂停、恢复或停用 |
| `GET` | `/api/medications/{medication_id}/events` | 不可覆盖的事件历史 |
| `PUT` | `/api/medications/{medication_id}/daily-status` | 写入最近 7 个业务自然日的已服/漏服/未记录 |
| `GET` | `/api/medication-daily?from=YYYY-MM-DD&to=YYYY-MM-DD` | 查询日期范围的每日记录 |

创建用药的必填字段：`drug_name`、`source_category`、`start_date`、`event_date`。

- `source_category`: `prescribed | supplement | other_long_term`
- `source_type`: `manual | medical_order | outpatient_record | imported`
- 更新 `event_type`: `adjusted | paused | resumed | stopped`
- 停用时必须传 `stop_source`: `written_order | verbal_doctor | patient_self | other`
- 每日 `intake_status`: `taken | missed | unrecorded`
- 前端必须使用 `GET /api/medications` 返回的 `data.server_date` 作为当日写入日期，不使用设备本地日期猜测服务器业务日。
- `PUT /api/medications/{id}` 必须携带当前记录的 `updated_at`。
- 可写窗口为 `editable_from <= record_date <= business_date`；第 8 天及更早返回 `409 HISTORICAL_DAILY_STATUS_READ_ONLY`，未来日期返回 `409 FUTURE_DAILY_STATUS_NOT_ALLOWED`。
- `unrecorded` 表示撤销明确状态，后端不会持久化一条“未记录”行。
- `GET /api/medication-daily` 的每个 item 包含 `editable`；响应同时包含 `business_date` 和 `editable_from`。
- 写入成功响应包含最新 `month_summary`。重复写入同一状态不会改变 `recorded_at`，并发重复写入只保留一行。

每日状态请求：

```json
{
  "record_date": "2026-08-27",
  "intake_status": "taken"
}
```

## 6. 经期历史

| 方法 | 路径 | 成功状态 | 用途 |
|---|---|---:|---|
| `GET` | `/api/cycles?from=YYYY-MM-DD&to=YYYY-MM-DD` | 200 | 列表与趋势 |
| `POST` | `/api/cycles` | 201 | 新建记录 |
| `PUT` | `/api/cycles/{cycle_id}` | 200 | 修改记录 |
| `DELETE` | `/api/cycles/{cycle_id}` | 204 | 逻辑删除 |

写入请求：

```json
{
  "start_date": "2026-08-20",
  "end_date": "2026-08-25",
  "flow_level": "medium",
  "note": "用户手工记录",
  "source_type": "manual",
  "updated_at": null
}
```

- `flow_level`: `light | medium | heavy | unknown | null`
- `source_type`: `manual | imported`
- 编辑时传当前记录的 `updated_at`；新建时可为 null
- 后端拒绝结束日早于开始日、与其他记录重叠、以及对已删除记录的操作

## 7. 体重记录

| 方法 | 路径 | 成功状态 | 用途 |
|---|---|---:|---|
| `GET` | `/api/weights?from=YYYY-MM-DD&to=YYYY-MM-DD` | 200 | 按日期范围读取趋势 |
| `POST` | `/api/weights` | 201/200 | 当日无记录时创建，已有记录时更新 |
| `PUT` | `/api/weights/{weight_id}` | 200 | 按 ID 修改 |

写入请求：

```json
{
  "record_date": "2026-08-27",
  "weight_kg": 68.4
}
```

`weight_kg` 范围为 20.0–300.0 kg，最多一位小数。查询时 `to` 不能早于 `from`。

## 8. 私有医疗材料

| 方法 | 路径 | 成功状态 | 用途 |
|---|---|---:|---|
| `GET` | `/api/documents?document_type=...` | 200 | 当前 UID 的材料列表 |
| `POST` | `/api/documents` | 201 | multipart 上传，必须携带 `Idempotency-Key` |
| `GET` | `/api/documents/{document_id}` | 200 | 材料详情 |
| `DELETE` | `/api/documents/{document_id}` | 204 | 软删除材料 |
| `GET` | `/api/documents/{document_id}/revisions` | 200 | 修订列表 |
| `POST` | `/api/documents/{document_id}/revisions` | 201 | 上传新修订，必须携带 `Idempotency-Key` |
| `GET` | `/api/documents/{document_id}/revisions/{revision_id}/file` | 200 | 鉴权读取原始文件流 |

- 支持 JPG、JPEG、PNG 和单页 PDF；最大 20 MiB，图片最大 25 MP。
- 上传表单字段为 `document_type`、可选 `external_processing_consent_version`，文件字段名为 `file`。
- 原始文件名、服务端 SHA-256、存储路径和修订归属均由后端校验；不要把文件 URL 当公开 URL 缓存或分享。
- 删除后列表、详情、修订和文件读取均按不存在处理；不同 UID 的对象统一返回 404。

## 9. 患者自述草稿

| 方法 | 路径 | 成功状态 | 用途 |
|---|---|---:|---|
| `POST` | `/api/patient-notes` | 201 | 创建草稿 |
| `GET` | `/api/patient-notes/latest` | 200 | 读取最近一条；没有时 `data=null` |
| `PUT` | `/api/patient-notes/{note_id}` | 200 | 仅修改 draft，携带 `updated_at` |
| `POST` | `/api/patient-notes/{note_id}/confirm` | 200 | 确认草稿 |
| `POST` | `/api/patient-notes/{note_id}/skip` | 200 | 明确跳过 |
| `POST` | `/api/patient-notes/{note_id}/copy` | 201 | 从历史记录复制为新草稿 |

状态为 `draft | confirmed | skipped | consumed`。原文、确认人、来源 note、确认时间和消费时间由服务端保存；并发更新使用 `updated_at`，跨 UID 一律 404。

当前已合入的是患者自述与报告来源归属基础，以及 Dashboard 的最新成功报告元数据。`/api/reports`、PDF、OCR 等后续接口在对应 PR 合入并部署前不要调用，即使主 OpenAPI 中已有规划契约。

## 10. 前端错误处理

| HTTP | 典型场景 | 前端处理 |
|---:|---|---|
| 401 | Session 缺失、过期或撤销 | 清理安全存储并回登录页 |
| 404 | 对象不存在或不属于当前 UID | 按不存在处理，不提示归属信息 |
| 409 | `updated_at` 过期、日期冲突或状态不允许 | 重新拉取最新数据，保留用户输入后提示重试 |
| 422 | 字段、枚举、日期或数值不合法 | 优先使用本地校验，展示可操作提示 |
| 429 | 认证请求限流 | 按 `Retry-After` 倒计时 |
| 5xx/网络失败 | 服务或连接异常 | 保留表单原值，允许安全重试，不将旧缓存伪装为最新数据 |

## 11. curl 联调模板

```bash
BASE_URL='https://api.healy1012-ops.top'

curl --fail "$BASE_URL/health/ready"

curl "$BASE_URL/api/patient/profile" \
  --header 'Authorization: Bearer <session_id>'

curl "$BASE_URL/api/weights?from=2026-08-01&to=2026-08-31" \
  --header 'Authorization: Bearer <session_id>'

curl "$BASE_URL/api/dashboard" \
  --header 'Authorization: Bearer <session_id>'
```

代码生成、DTO 对齐和自动化契约测试请直接使用：`contracts/openapi/pomi-api-v1.yaml`。生产环境为降低暴露面不公开 `/docs` 和 `/openapi.json`。
