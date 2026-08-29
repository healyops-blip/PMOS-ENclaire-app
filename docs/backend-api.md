# Pomi 后端接口文档

本文档描述当前生产环境实际部署的 Pomi HTTP API，供 Flutter、Web 和联调测试使用。

- 生产地址：`https://api.healy1012-ops.top`
- 对应代码：`main` 分支提交 `baa4d2acc551c52fd1364cb700c79e1afe437fce`
- API 风格：HTTPS + JSON；文件接口使用 `multipart/form-data`
- 业务时区：`Asia/Singapore`
- 认证方式：Bearer Session

> 生产环境关闭 `/docs`、`/redoc` 和 `/openapi.json`。接口以当前后端路由、自动化测试和本文档为准。

## 1. 通用约定

### 1.1 请求头

除健康检查、注册和登录外，所有接口都需要：

```http
Authorization: Bearer <session_id>
Content-Type: application/json
Accept: application/json
```

写入接口可能还要求：

```http
Idempotency-Key: <8-128 字符的客户端唯一值>
X-Request-ID: <可选，最长 128 字符>
```

服务端会在每个响应头中返回 `X-Request-ID`。排查问题时应记录该值。

### 1.2 时间、日期与 ID

- 日期：`YYYY-MM-DD`，例如 `2026-08-28`。
- 时间：ISO 8601，例如 `2026-08-28T08:30:00+00:00`。
- ID：不透明字符串，客户端不得解析、改写或自行生成资源 ID。
- `updated_at`：用于乐观并发控制。更新时必须回传最近一次读取到的值；版本过期返回 `409 RESOURCE_VERSION_CONFLICT`。
- 用药写入日期以 `GET /api/medications` 返回的 `server_date` 为准，不以设备本地时间推断业务日期。

### 1.3 通用业务响应

大多数已认证业务接口使用统一信封：

```json
{
  "success": true,
  "data": {},
  "request_id": "req_0123456789abcdef",
  "error": null
}
```

业务错误：

```json
{
  "success": false,
  "data": null,
  "request_id": "req_0123456789abcdef",
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "Document was not found.",
    "retryable": false,
    "retry_after_seconds": null,
    "details": {}
  }
}
```

认证接口使用较简洁的错误结构：

```json
{
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "The account name or password is incorrect."
  }
}
```

经期和体重接口也返回 `success/data/request_id/error` 信封，但部分体重错误由 FastAPI 返回：

```json
{"detail":"Weight record has changed."}
```

### 1.4 常用 HTTP 状态码

| 状态码 | 含义 |
| --- | --- |
| `200` | 查询、更新或幂等复用成功 |
| `201` | 新资源创建成功 |
| `204` | 成功且无响应体 |
| `400` | Host、请求格式或协议不被接受 |
| `401` | Session 缺失、无效、过期或已撤销 |
| `404` | 当前用户范围内资源不存在 |
| `409` | 状态冲突、版本冲突或缺少必要确认 |
| `413` | 文件或图片过大 |
| `415` | 文件类型或 PDF 页数不支持 |
| `422` | 字段校验或业务校验失败 |
| `429` | 注册或登录尝试过于频繁 |
| `503/504` | 外部 OCR 服务不可用或超时 |

## 2. 接口总览

### 2.1 无需登录

| 方法 | 路径 | 成功状态 | 说明 |
| --- | --- | --- | --- |
| `GET` | `/health/live` | `200` | 进程存活检查 |
| `GET` | `/health/ready` | `200` | 服务与数据库就绪检查 |
| `POST` | `/api/auth/register` | `201` | 注册账号 |
| `POST` | `/api/auth/login` | `200` | 账号名或手机号登录 |

### 2.2 需要 Bearer Session

| 模块 | 方法与路径 |
| --- | --- |
| 会话 | `GET /api/auth/me`；`POST /api/auth/logout` |
| 首次引导 | `GET /api/onboarding`；`PUT /api/onboarding/steps/basic`；`PUT /api/onboarding/steps/cycle`；`PUT /api/onboarding/steps/medications`；`POST /api/onboarding/complete` |
| 患者画像 | `GET /api/patient/profile`；`PUT /api/patient/profile` |
| 首页 | `GET /api/dashboard` |
| 用药 | `GET/POST /api/medications`；`PUT /api/medications/{id}`；`GET /api/medications/{id}/events`；`PUT /api/medications/{id}/daily-status`；`GET /api/medication-daily` |
| 经期 | `GET/POST /api/cycles`；`PUT/DELETE /api/cycles/{id}` |
| 体重 | `GET/POST /api/weights`；`PUT /api/weights/{id}` |
| 医疗材料 | `GET/POST /api/documents`；`GET/DELETE /api/documents/{id}`；`GET/POST /api/documents/{id}/revisions`；`GET /api/documents/{id}/revisions/{revision_id}/file` |
| OCR | `POST /api/ocr/recognize`；`POST /api/ocr/results/{result_id}/confirm`；`POST /api/ocr/tasks`；`GET /api/ocr/tasks/{id}`；`GET /api/ocr/tasks/{id}/result`；`POST /api/ocr/tasks/{id}/confirm`；`POST /api/ocr/tasks/{id}/retry` |
| 化验结果 | `GET /api/lab-observations`；`GET /api/lab-observations/{id}` |
| 用药对账 | `POST /api/medication-reconciliations`；`GET/PUT /api/medication-reconciliations/{id}` |
| 患者自述 | `POST /api/patient-notes`；`GET /api/patient-notes/latest`；`PUT /api/patient-notes/{id}`；`POST /api/patient-notes/{id}/confirm`；`POST /api/patient-notes/{id}/skip`；`POST /api/patient-notes/{id}/copy` |
| 报告 | `POST /api/reports/preflight`；`GET/POST /api/reports`；`GET /api/reports/{id}` |

## 3. 健康检查

### `GET /health/live`

仅验证 API 进程存活。

### `GET /health/ready`

验证服务是否可以接收业务流量。成功响应：

```json
{"status":"ok"}
```

## 4. 认证与会话

### 4.1 注册

`POST /api/auth/register`

```json
{
  "account_name": "pomi-user",
  "password": "StrongPass123",
  "phone_number": "+8613800000000"
}
```

| 字段 | 必填 | 规则 |
| --- | --- | --- |
| `account_name` | 是 | 3-64 字符，唯一 |
| `password` | 是 | 8-128 字符，至少包含字母和数字 |
| `phone_number` | 否 | 最长 32 字符；非空时必须唯一 |

成功直接返回账号对象，不使用业务信封：

```json
{
  "uid": "account-uuid",
  "account_name": "pomi-user",
  "account_type": "patient",
  "onboarding_completed": false,
  "status": "active",
  "phone_number": "+8613800000000",
  "phone_verified": false
}
```

常见错误：`ACCOUNT_NAME_TAKEN`、`PHONE_NUMBER_TAKEN`、`VALIDATION_ERROR`、`AUTH_RATE_LIMITED`。

### 4.2 登录

`POST /api/auth/login`

`account_name` 可传账号名；以 `+` 开头或纯数字时也会尝试匹配手机号。

```json
{
  "account_name": "pomi-user",
  "password": "StrongPass123",
  "client_platform": "flutter-ios",
  "device_name": "iPhone"
}
```

成功响应：

```json
{
  "session_id": "opaque-session-credential",
  "token_type": "Bearer",
  "expires_at": "2026-09-04T08:30:00+00:00",
  "account": {
    "uid": "account-uuid",
    "account_name": "pomi-user",
    "account_type": "patient",
    "onboarding_completed": false,
    "status": "active",
    "phone_number": "+8613800000000",
    "phone_verified": false
  }
}
```

默认 Session 有效期为 7 天。客户端应安全保存 `session_id`，不得记录到日志或分析平台。

### 4.3 当前账号

`GET /api/auth/me`：成功返回与注册响应相同的账号对象，可用于冷启动恢复会话。

### 4.4 退出

`POST /api/auth/logout`：成功返回 `204 No Content`，当前 Session 随即撤销。

## 5. 首次引导 Onboarding

首次引导草稿支持分步骤保存和跨设备恢复。除第一次读取外，更新时建议回传草稿的 `updated_at`。

### 5.1 获取草稿

`GET /api/onboarding`

返回：`id`、`current_step`、`basic`、`cycle`、`medications`、`updated_at`。

### 5.2 保存基础信息

`PUT /api/onboarding/steps/basic`

```json
{
  "nickname": "小柚",
  "birth_year": 1995,
  "diagnosis_year": 2024,
  "height_cm": 165.0,
  "weight_kg": 58.5,
  "updated_at": "2026-08-28T08:30:00+00:00"
}
```

### 5.3 保存经期与复诊信息

`PUT /api/onboarding/steps/cycle`

```json
{
  "last_menstrual_start_date": "2026-08-10",
  "usual_cycle_min_days": 28,
  "usual_cycle_max_days": 35,
  "next_visit_date": "2026-09-20",
  "updated_at": "2026-08-28T08:30:00+00:00"
}
```

周期范围为 15-120 天，最小值不得大于最大值。

### 5.4 保存初始用药

`PUT /api/onboarding/steps/medications`

```json
{
  "items": [
    {
      "catalog_id": null,
      "drug_name": "二甲双胍",
      "source_category": "prescribed",
      "start_date": "2026-08-01"
    }
  ],
  "updated_at": "2026-08-28T08:30:00+00:00"
}
```

`source_category`：`prescribed`、`supplement`、`other_long_term`；最多 50 项。

### 5.5 完成首次引导

`POST /api/onboarding/complete`

该操作原子写入患者画像、初始体重、经期和用药，并把账号标记为已完成引导。基础信息缺失返回 `409 ONBOARDING_BASIC_REQUIRED`。

## 6. 患者画像与首页

### 6.1 获取患者画像

`GET /api/patient/profile`

主要响应字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 患者 ID |
| `nickname` | string/null | 昵称 |
| `birth_year` | integer/null | 出生年份 |
| `height_cm` | number/null | 身高 |
| `diagnosis_year` | integer/null | 确诊年份 |
| `usual_cycle_min_days` | integer/null | 常见最短周期 |
| `usual_cycle_max_days` | integer/null | 常见最长周期 |
| `next_visit_date` | date/null | 下次复诊日期 |
| `health_goal` | string/null | 健康目标 |
| `onboarding_completed` | boolean | 是否完成首次引导 |
| `updated_at` | datetime | 当前资源版本 |

### 6.2 更新患者画像

`PUT /api/patient/profile`

请求可包含：`nickname`、`birth_year`、`birth_date`、`gender`、`height_cm`、`diagnosis_year`、`usual_cycle_min_days`、`usual_cycle_max_days`、`primary_condition`、`next_visit_date`、`health_goal`、`complete_onboarding`。

`updated_at` 必填，用于并发控制。

### 6.3 Dashboard

`GET /api/dashboard`

`data` 包含 `server_date`、`data_as_of`、`follow_up`、`today_medications`、`monthly_medication_summary`、`tracking_summary`、`document_summary` 和 `latest_report`。

每个 section 均有 `status: ok|empty|error`，单个区块失败不会使整个 Dashboard 请求失败。

## 7. 用药与每日状态

### 7.1 查询用药

`GET /api/medications?status=active|paused|stopped`

返回 `server_date`、`items`、`groups`、`next_cursor`、`has_more`。单项主要字段包括：`id`、`drug_name`、`standard_drug_id`、`specification`、`dosage_value`、`dosage_unit`、`frequency`、`route`、`current_status`、`source_category`、`start_date`、`end_date`、`updated_at`。

### 7.2 新增用药

`POST /api/medications`，需要 `Idempotency-Key`。

```json
{
  "drug_name": "二甲双胍",
  "source_category": "prescribed",
  "start_date": "2026-08-01",
  "event_date": "2026-08-01",
  "source_type": "manual",
  "source_document_id": null,
  "note": null
}
```

### 7.3 调整、暂停、恢复或停药

`PUT /api/medications/{medication_id}`

```json
{
  "event_type": "paused",
  "event_date": "2026-08-28",
  "stop_source": null,
  "change_reason": "等待复诊确认",
  "note": null,
  "updated_at": "2026-08-28T08:30:00+00:00"
}
```

`event_type`：`adjusted`、`paused`、`resumed`、`stopped`。停药时可能要求 `stop_source`：`written_order`、`verbal_doctor`、`patient_self`、`other`。

### 7.4 用药事件历史

`GET /api/medications/{medication_id}/events`：返回新旧用药说明、事件类型、事件日期、来源和操作时间。

### 7.5 写入每日三状态

`PUT /api/medications/{medication_id}/daily-status`

```json
{
  "record_date": "2026-08-28",
  "intake_status": "taken"
}
```

`intake_status`：`taken`、`missed`、`unrecorded`。未来日期不可写；历史只读窗口外不可修改。

### 7.6 查询每日记录

`GET /api/medication-daily?from=2026-08-01&to=2026-08-31&medication_id=<可选>`

## 8. 经期与体重

### 8.1 经期记录

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/cycles?from=<date>&to=<date>` | 查询日期范围内记录 |
| `POST` | `/api/cycles` | 新增记录，返回 `201` |
| `PUT` | `/api/cycles/{cycle_id}` | 更新记录 |
| `DELETE` | `/api/cycles/{cycle_id}` | 删除记录，返回 `204` |

新增/更新请求：

```json
{
  "start_date": "2026-08-10",
  "end_date": "2026-08-15",
  "flow_level": "medium",
  "note": null,
  "source_type": "manual",
  "updated_at": null
}
```

`flow_level`：`light`、`medium`、`heavy`、`unknown`。

### 8.2 体重记录

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/weights?from=<date>&to=<date>` | 查询体重趋势 |
| `POST` | `/api/weights` | 当日无记录时创建 `201`；已有时更新 `200` |
| `PUT` | `/api/weights/{weight_id}` | 更新指定记录 |

```json
{
  "record_date": "2026-08-28",
  "weight_kg": 58.5,
  "updated_at": null
}
```

体重范围 20.0-300.0 kg，精度 0.1 kg。

## 9. 医疗材料与修订

支持类型：`lab_report`、`medical_order`、`imaging_text_report`、`outpatient_record`。

文件限制：JPEG、PNG 或单页 PDF；最大 20 MiB；图片最大 2500 万像素；文件存储在私有目录。

### 9.1 上传材料

`POST /api/documents`，请求类型为 `multipart/form-data`。

| 位置 | 字段 | 必填 | 说明 |
| --- | --- | --- | --- |
| Header | `Idempotency-Key` | 是 | 8-128 字符 |
| Form | `file` | 是 | 文件内容 |
| Form | `document_type` | 是 | 四种材料类型之一 |
| Form | `external_processing_consent_version` | 否 | 外部处理告知版本 |

### 9.2 查询与删除

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/documents?document_type=<可选>&cursor=<datetime>&limit=20` | 分页查询，`limit` 为 1-100 |
| `GET` | `/api/documents/{document_id}` | 获取材料和当前修订详情 |
| `DELETE` | `/api/documents/{document_id}` | 软删除并返回计划清理时间 |

材料响应包含 `current_revision_id`、文件哈希、大小、MIME、页数、上传状态，以及 `latest_ocr_task_id`、`latest_ocr_status`。

### 9.3 修订版本

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/documents/{document_id}/revisions` | 查询不可变修订历史 |
| `POST` | `/api/documents/{document_id}/revisions` | 上传替换版本，返回 `201` |
| `GET` | `/api/documents/{document_id}/revisions/{revision_id}/file` | 下载私有原文件 |

替换版本使用 `multipart/form-data`：`file`、`replacement_reason`、`expected_current_revision_id`，并要求 `Idempotency-Key`。

## 10. OCR

OCR 提供同步识别和任务式处理两套入口。结果必须经用户确认后才能进入正式业务数据。

### 10.1 同步识别

`POST /api/ocr/recognize`，请求类型为 `multipart/form-data`。

| 位置 | 字段 | 必填 | 说明 |
| --- | --- | --- | --- |
| Header | `Idempotency-Key` | 是 | 同一文件重试必须复用 |
| Header | `X-External-Processing-Consent-Version` | 是 | 外部 OCR 处理授权版本 |
| Form | `file` | 是 | JPEG、PNG 或单页 PDF |
| Form | `material_type` | 否 | 默认 `outpatient_record` |
| Form | `prompt_version` | 否 | 当前仅支持 `pomi-ocr-v1` |

成功返回识别草稿、`ocr_task_id`、`ocr_result_id`、材料与修订 ID、`result_source`。

同步确认路径：`POST /api/ocr/results/{result_id}/confirm`。

```json
{
  "visit_date": "2026-08-28",
  "examinations": [
    {
      "source_index": 0,
      "item_name": "空腹血糖",
      "value": "5.2",
      "unit": "mmol/L",
      "reference_range": "3.9-6.1",
      "note": null
    }
  ],
  "medication_suggestions": []
}
```

### 10.2 创建异步 OCR 任务

`POST /api/ocr/tasks`

```json
{
  "document_id": "document-uuid",
  "document_revision_id": "revision-uuid"
}
```

成功返回任务信息和 `reused`。

### 10.3 查询任务与结果

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/ocr/tasks/{task_id}` | 查询状态、尝试次数、耗时和安全错误信息 |
| `GET` | `/api/ocr/tasks/{task_id}/result` | 查询结构化草稿、证据字段和用户确认状态 |
| `POST` | `/api/ocr/tasks/{task_id}/retry` | 对可重试失败任务创建新尝试，返回 `201` |

### 10.4 确认任务结果

`POST /api/ocr/tasks/{task_id}/confirm`

该路径按材料类型接收三类请求：

1. 化验单：`result_id`、`expected_revision_id`、四类日期和 `items[]`。
2. 影像/门诊文本：`document_type`、`confirmed_data`、`field_confirmations[]`。
3. 医嘱：`result_id`、`expected_revision_id`、已确认的 `items[]`。

确认操作具有幂等性。相同内容重复确认返回已创建资源；不同内容重复提交通常返回 `409 OCR_ALREADY_CONFIRMED` 或版本冲突。

## 11. 正式化验数据与用药对账

### 11.1 化验观察值

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/lab-observations` | 返回 `items[]` |
| `GET` | `/api/lab-observations/{observation_id}` | 查询单项正式化验记录 |

正式记录包含原指标名、标准指标 ID、映射状态、原始/数值结果、原始/标准单位、参考范围、确定性异常状态、四类日期、趋势日期来源、OCR 来源和确认时间。

### 11.2 用药对账

创建草稿：`POST /api/medication-reconciliations`

```json
{"ocr_task_id":"ocr-task-uuid"}
```

查询草稿：`GET /api/medication-reconciliations/{reconciliation_id}`。

执行对账：`PUT /api/medication-reconciliations/{reconciliation_id}`

```json
{
  "decisions": [
    {
      "item_id": "reconciliation-item-uuid",
      "decision": "accept",
      "note": null,
      "stop_date": null,
      "stop_source": null
    }
  ]
}
```

`decision`：`accept`、`keep_current`、`reject`。执行是原子操作，决策不完整或重复执行返回 `409`。

## 12. 患者自述

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/api/patient-notes` | 新建草稿，返回 `201` |
| `GET` | `/api/patient-notes/latest` | 获取最新一条；无数据时 `data=null` |
| `PUT` | `/api/patient-notes/{note_id}` | 修改未消费的草稿 |
| `POST` | `/api/patient-notes/{note_id}/confirm` | 确认文本 |
| `POST` | `/api/patient-notes/{note_id}/skip` | 明确跳过自述 |
| `POST` | `/api/patient-notes/{note_id}/copy` | 从不可变记录复制新草稿，返回 `201` |

```json
{
  "original_text": "最近两周睡眠变差，希望复诊时讨论。",
  "visit_context": "2026-09 复诊"
}
```

`original_text` 最长 5000 字符，`visit_context` 最长 200 字符。报告消费后的记录不可直接修改，需调用 copy。

## 13. 报告快照

报告是确定性数据快照，不在请求时调用生成式模型。

```json
{
  "patient_note_id": "patient-note-uuid",
  "include_sections": [
    "profile",
    "patient_note",
    "medications",
    "labs",
    "imaging",
    "outpatient",
    "cycles",
    "weights"
  ],
  "confirm_incomplete": false
}
```

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/api/reports/preflight` | 返回缺失区块、是否可生成、已确认来源数量 |
| `POST` | `/api/reports` | 创建报告快照，返回 `201`；相同来源可复用 |
| `GET` | `/api/reports` | 返回 `items`、`next_cursor`、`has_more` |
| `GET` | `/api/reports/{report_id}` | 返回快照、日期来源和数据新鲜度 |

缺少必要内容且未设置 `confirm_incomplete=true` 时，返回 `409 REPORT_INCOMPLETE_CONFIRMATION_REQUIRED`。

## 14. 错误码参考

| 错误码 | 建议客户端动作 |
| --- | --- |
| `AUTHENTICATION_REQUIRED` | 清理本地 Session 并跳转登录 |
| `INVALID_CREDENTIALS` | 保留账号输入，提示账号或密码错误 |
| `ACCOUNT_NAME_TAKEN` / `PHONE_NUMBER_TAKEN` | 提示更换账号名或手机号 |
| `AUTH_RATE_LIMITED` | 读取 `Retry-After` 后再试 |
| `VALIDATION_ERROR` | 保留表单并标记字段错误 |
| `RESOURCE_NOT_FOUND` | 刷新列表并移除失效本地引用 |
| `RESOURCE_VERSION_CONFLICT` | 重新拉取资源，提示用户合并或重试 |
| `FILE_TOO_LARGE` / `IMAGE_TOO_LARGE` | 压缩或重新选择文件 |
| `UNSUPPORTED_FORMAT` / `MULTI_PAGE_PDF` | 改用 JPEG、PNG 或单页 PDF |
| `EXTERNAL_PROCESSING_CONSENT_REQUIRED` | 展示外部 OCR 授权说明 |
| `OCR_RESULT_NOT_READY` | 保持轮询或稍后重试 |
| `OCR_TASK_NOT_RETRYABLE` | 停止自动重试并展示安全错误信息 |
| `OCR_CONFIRMATION_VERSION_CONFLICT` / `DOCUMENT_REVISION_MISMATCH` | 重新读取当前修订和 OCR 结果 |
| `LAB_CONFIRMATION_INVALID` | 使用 `error.details.fields[]` 标记具体字段 |
| `HISTORICAL_DAILY_STATUS_READ_ONLY` | 禁用该日期编辑 |
| `FUTURE_DAILY_STATUS_NOT_ALLOWED` | 使用服务器业务日期重新选择日期 |
| `PATIENT_NOTE_IMMUTABLE` | 调用 copy 创建新草稿 |
| `REPORT_INCOMPLETE_CONFIRMATION_REQUIRED` | 展示缺失区块并让用户明确确认 |

网络失败或 `5xx` 时，客户端应保留用户原始输入；只有明确幂等的读取请求或带稳定 `Idempotency-Key` 的写入才能自动重试。

## 15. curl 联调示例

### 15.1 登录并读取当前账号

```bash
BASE_URL='https://api.healy1012-ops.top'

curl --request POST "$BASE_URL/api/auth/login" \
  --header 'Content-Type: application/json' \
  --data '{
    "account_name": "pomi-user",
    "password": "StrongPass123",
    "client_platform": "curl",
    "device_name": "developer-machine"
  }'
```

从登录响应安全取得 `session_id` 后：

```bash
curl --request GET "$BASE_URL/api/auth/me" \
  --header "Authorization: Bearer $POMI_SESSION_ID"
```

### 15.2 上传医疗材料

```bash
curl --request POST "$BASE_URL/api/documents" \
  --header "Authorization: Bearer $POMI_SESSION_ID" \
  --header "Idempotency-Key: upload-$(date +%s)" \
  --form 'document_type=lab_report' \
  --form 'file=@./lab-report.jpg'
```

## 16. 当前契约差异与非 HTTP 能力

仓库 `contracts/openapi/pomi-api-v1.yaml` 中列出了以下路径，但提交 `baa4d2acc551c52fd1364cb700c79e1afe437fce` 的 FastAPI 应用当前没有挂载对应路由：

- `/api/reports/{report_id}/pdf`
- `/api/reports/{report_id}/pdf/file`
- `/api/deterministic-rules`
- `/api/deterministic-rules/{rule_id}`
- `/api/rule-executions/{execution_id}`

前端在路由正式实现并部署前不得调用这些路径。

以下能力仅限服务器管理员本地执行，不是 HTTP API：

```bash
pomi-admin seed-accounts
pomi-admin reset-password ACCOUNT_NAME
```

系统目前不提供公开密码重置接口、万能密码或公开管理员接口。
