# Pomi 前后端对接与 API 开工说明

> 状态：P0 开发基线
>
> 依据：`Pomi技术方案_260826.html`、`pcos-prototype-v7.html`、`docs/architecture.md`
>
> 机器可读契约：`contracts/openapi/pomi-api-v1.yaml`

本文用于让 Flutter、FastAPI、OCR Worker 和测试同学在不反复猜字段的情况下并行开工。认证接口已经落地，必须以 `backend/src/pomi_backend`、`docs/backend-api.md` 和对应测试为准；其他尚未实现的业务接口以 OpenAPI 为准。业务边界冲突时先更新本文和 OpenAPI，再改代码。

## 1. 当前 P0 边界

### 1.1 本期必须由后端提供

- 账号注册、账号密码登录、会话恢复和退出。
- 患者画像读取、分步保存和初始化完成。
- Dashboard 聚合。
- 用药清单、用药事件、每日三状态、经期和体重。
- 四类医疗材料的上传、分页、详情、修订、私有文件流和软删除。
- 异步 OCR 任务、任务轮询、四类草稿、字段级确认、失败重试和预置材料兜底。
- 医嘱确认后的用药对账。
- 患者自述、不可变报告快照、三层报告和服务端 PDF。
- 管理端确定性规则读取/更新与规则执行追溯。

### 1.2 本期只由 Flutter 本地实现

- 材料“医院认证”演示状态：`not_started`、`processing`、`succeeded`、`failed`。
- 状态键：`document_id + document_revision_id`。
- 认证水印和“提供区块链技术支持”提示。

当前 FastAPI **不得**增加医生 KYC、医院 KYB、电子签字、真实区块链交易、交易哈希或跨院互认接口。未来真实认证服务必须另立数据模型和 OpenAPI 版本。

### 1.3 明确排除

- 短信验证码、短信/邮件找回密码和真实推送。
- 医学诊断、治疗建议、自动停药和“改善/恶化”结论。
- 多页 PDF、任意材料类型、本地大模型、Redis、Celery、Kafka。
- 将未确认 OCR 草稿直接写入正式健康数据。

## 2. 技术责任边界

| 组件 | 负责 | 不负责 |
|---|---|---|
| Flutter Presentation | 页面、输入校验、加载/空/错误状态、图表、文件选择、分享打印 | 直接操作 SQLite、计算医疗规则 |
| Flutter Application | Riverpod 状态、上传编排、2 秒轮询、乐观更新及回滚、防重复提交 | 保存服务端正式医疗数据 |
| Flutter Data | Dio、DTO、Repository、Session Header、本地轻缓存 | 供应商 OCR 字段 |
| FastAPI Router/Schema | 鉴权、参数校验、统一响应、OpenAPI | 页面状态 |
| FastAPI Service | 事务、业务状态机、幂等、报告聚合、确定性规则 | 直接耦合 Flutter Widget |
| SQLite Repository | 正式数据、会话哈希、任务状态、文件元数据、报告快照 | 原始文件二进制 |
| OCR Worker | 租约领取任务、Qwen3-VL、Schema 校验、字段级草稿、重试 | 把草稿直接转正式数据 |
| 私有文件目录 | 原图、单页 PDF、生成 PDF | 对公网直接暴露路径 |

## 3. 联调基础约定

### 3.1 地址与鉴权

- 服务根地址：`https://api.healy1012-ops.top`
- 本地根地址：`http://127.0.0.1:8000`
- 业务接口统一使用 `/api` 前缀；健康检查使用根路径下的 `/health/live`、`/health/ready`。
- 除注册、登录和健康检查外，请求头必须携带：

```http
Authorization: Bearer <session_id>
```

- Flutter 仅把 `session_id` 写入系统安全存储；服务端数据库只保存 SHA-256 后的会话哈希。
- 会话默认 7 天过期，退出立即撤销。

### 3.2 JSON 响应

已经实现的认证和健康检查接口保持当前直接响应结构：

- `/health/live`、`/health/ready`：`{"status":"ok"}`。
- 注册和 `/api/auth/me`：直接返回 `AccountResponse`。
- 登录：直接返回 `LoginResponse`。
- 退出：`204 No Content`，无响应体。
- 认证错误：`{"error":{"code":"...","message":"..."}}`。

下列统一包络仅用于尚未实现的患者、用药、材料、OCR、报告等业务接口：

成功：

```json
{
  "success": true,
  "data": {},
  "request_id": "req_01J...",
  "error": null
}
```

失败：

```json
{
  "success": false,
  "data": null,
  "request_id": "req_01J...",
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "账号或密码错误",
    "retryable": false,
    "details": {}
  }
}
```

文件流接口直接返回二进制，不套统一 JSON。后端实现新业务接口时不得擅自套用认证接口的直接结构；若团队决定统一改造，需同时修改 OpenAPI、Flutter DTO、测试和本文。

### 3.3 时间、ID、空值和分页

- `uid`：账号 ID；其他 `*_id`：UUID 字符串。
- 日期：`YYYY-MM-DD`；时间：UTC ISO 8601，例如 `2026-08-26T10:24:00Z`。
- App 展示时转换为设备时区，服务端和数据库保持 UTC。
- 未知/缺失值用 `null`，不用空字符串或 `0` 冒充。
- 列表统一使用游标分页：`cursor`、`limit`，返回 `items`、`next_cursor`、`has_more`。
- 默认 `limit=20`，允许范围 `1..100`。

### 3.4 幂等和并发

- 下列创建请求必须携带 `Idempotency-Key`：文件上传、OCR 创建/重试、对账创建、报告生成、PDF 生成。当前注册接口不要求该 Header。
- 服务端对同一会话和幂等键返回同一资源，不重复写入。
- 更新接口携带 `updated_at` 或 `expected_revision_id`；版本不一致返回 `409 RESOURCE_VERSION_CONFLICT`。
- Flutter 按钮提交期间禁用；每日用药可乐观更新，失败必须回滚。

### 3.5 文件限制

- 支持：JPG、JPEG、PNG、单页 PDF。
- 单文件最大 20 MiB；图片最大 25 MP；PDF 只允许 1 页。
- 后端生成 SHA-256，不信任客户端哈希。
- 原始文件和 PDF 只能通过鉴权文件流接口访问。

## 4. 接口总表与页面对应

| 模块 | 方法与路径 | Flutter 使用位置 | 后端产出 |
|---|---|---|---|
| 健康检查 | `GET /health/live`、`GET /health/ready` | 开发/部署诊断 | 固定 `{status: ok}`；ready 额外检查数据库 |
| 注册 | `POST /api/auth/register` | 注册页 | 账号；不创建会话，随后调用登录 |
| 登录 | `POST /api/auth/login` | 登录页 | Session、过期时间、账号状态 |
| 会话恢复 | `GET /api/auth/me` | App 启动 | 当前账号；前端根据 `onboarding_completed` 路由 |
| 退出 | `POST /api/auth/logout` | 我的 | `204` 并撤销当前 Session |
| 画像 | `GET/PUT /api/patient/profile` | 四步引导、我的 | 患者画像和完成状态 |
| Dashboard | `GET /api/dashboard` | 首页 | 倒计时、今日药物、月统计、报告入口 |
| 用药列表 | `GET/POST /api/medications` | 用药管理 | 当前/历史用药 |
| 用药更新 | `PUT /api/medications/{medication_id}` | 用药编辑 | 新事件、暂停/恢复状态或新版本 |
| 用药历史 | `GET /api/medications/{medication_id}/events` | 时间线 | 不可覆盖的事件链 |
| 每日状态 | `PUT /api/medications/{medication_id}/daily-status` | 首页、用药月历 | taken/missed/unrecorded |
| 每日状态范围 | `GET /api/medication-daily` | 月统计 | 日期范围内三状态记录 |
| 经期 | `GET/POST /api/cycles`、`PUT/DELETE /api/cycles/{cycle_id}` | 经期页 | 周期、趋势和逻辑删除 |
| 体重 | `GET/POST /api/weights`、`PUT /api/weights/{weight_id}` | 经期/体重页 | 体重趋势 |
| 材料 | `GET/POST /api/documents` | 记录页、上传页 | 材料及当前修订 |
| 材料详情 | `GET/DELETE /api/documents/{document_id}` | 材料详情 | 详情或软删除结果 |
| 修订 | `GET/POST /api/documents/{document_id}/revisions` | 修订历史/替换 | 修订链 |
| 原件 | `GET /api/documents/{document_id}/revisions/{revision_id}/file` | 图片/PDF 查看器 | 私有文件流 |
| OCR 创建 | `POST /api/ocr/tasks` | 上传完成后 | 异步任务 |
| OCR 状态 | `GET /api/ocr/tasks/{task_id}` | 2 秒轮询 | 状态、错误、进度 |
| OCR 草稿 | `GET /api/ocr/tasks/{task_id}/result` | 四类确认页 | 字段级草稿 |
| OCR 确认 | `POST /api/ocr/tasks/{task_id}/confirm` | 四类确认页 | 正式数据 ID |
| OCR 重试 | `POST /api/ocr/tasks/{task_id}/retry` | 失败页 | 新任务 |
| 用药对账 | `POST /api/medication-reconciliations` | 医嘱确认后 | 对账草稿 |
| 对账详情 | `GET/PUT /api/medication-reconciliations/{reconciliation_id}` | 对账页 | 差异和用户决策 |
| 患者自述 | `POST /api/patient-notes`、`GET /api/patient-notes/latest`、`PUT /api/patient-notes/{note_id}`、`POST /api/patient-notes/{note_id}/{confirm\|skip\|copy}` | 报告生成页 | 草稿、确认、跳过和历史复制 |
| 报告 | `GET/POST /api/reports` | 报告入口/历史 | 不可变快照 |
| 报告详情 | `GET /api/reports/{report_id}` | 三层报告 | 摘要、趋势、来源 |
| PDF | `POST/GET /api/reports/{report_id}/pdf` | 报告操作 | PDF 任务和元数据 |
| PDF 文件 | `GET /api/reports/{report_id}/pdf/file` | 下载/分享/打印 | PDF 文件流 |
| 规则管理 | `GET /api/deterministic-rules`、`PUT /api/deterministic-rules/{rule_id}` | 无普通用户页面 | 管理端规则参数 |
| 规则追溯 | `GET /api/rule-executions/{execution_id}` | 报告来源调试 | 规则输入/输出说明 |

## 5. 逐模块字段说明

下面列出联调最常用字段。完整必填、可空、枚举和格式约束见 OpenAPI。

### 5.1 注册、登录与会话

#### `POST /api/auth/register`

请求：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `account_name` | string | 是 | 3–64 字符；后端去空格并转小写；首字符为小写字母/数字，其余允许小写字母、数字、`.`、`_`、`-` |
| `password` | string | 是 | 8–128 字符，至少一个字母和一个数字，仅通过 HTTPS 传输 |
| `phone_number` | string/null | 否 | 7–20 位数字，可带 `+`；后端移除空格/连字符；当前不验证且不能登录 |

成功返回 `201` 和直接 `AccountResponse`：`uid`、`account_name`、`account_type`、`onboarding_completed`、`status`、`phone_number`、`phone_verified`。注册不返回 `session_id`，前端注册成功后必须再调用登录。

#### `POST /api/auth/login`

请求：必填 `account_name`、`password`；可选 `client_platform`（最长 32）、`device_name`（最长 128）。

成功直接返回 `LoginResponse`：`session_id`、固定为 `Bearer` 的 `token_type`、`expires_at`、`account`。其中 `account` 字段结构同注册响应。账号不存在、密码错误或账号不可登录统一返回 `INVALID_CREDENTIALS`，不能泄露账号是否存在。

#### `GET /api/auth/me`

携带 Bearer Session，直接返回 `AccountResponse`，不返回新的 `session_id`。`account_type` 为 `user/admin`；账号状态为 `active/disabled/locked`。前端根据 `onboarding_completed=false/true` 分别进入首次引导页或 Dashboard。

#### `POST /api/auth/logout`

携带 Bearer Session，成功返回 `204 No Content`。前端不能解析 JSON；收到成功响应后删除安全存储中的 `session_id`。

### 5.2 患者画像

`GET/PUT /api/patient/profile` 使用以下字段：

| 字段 | 类型 | 可空 | 谁生成 |
|---|---|---:|---|
| `patient_id` | UUID | 否 | 后端 |
| `account_uid` | string | 否 | 后端，从会话取得 |
| `nickname` | string | 是 | 用户 |
| `birth_date` | date | 是 | 用户 |
| `gender` | enum | 是 | `female/male/other/prefer_not_to_say` |
| `height_cm` | number | 是 | 用户，80–250 |
| `diagnosis_year` | integer | 是 | 用户，不能晚于当前年 |
| `primary_condition` | string | 是 | 当前默认 `pcos` |
| `usual_cycle_length_days` | integer | 是 | 引导周期步骤，15–120 |
| `last_menstrual_start_date` | date | 是 | 引导周期步骤 |
| `next_visit_date` | date | 是 | 首页倒计时 |
| `health_goal` | string | 是 | 管理目标 |
| `onboarding_step` | integer | 否 | 后端根据已保存字段计算，0–4 |
| `onboarding_completed` | boolean | 否 | 最后一步提交时置 true |
| `external_ocr_notice_accepted_at` | datetime | 是 | 后端记录用户首次同意时间 |
| `created_at`、`updated_at` | datetime | 否 | 后端 |

PUT 允许分步部分更新。请求中的 `complete_onboarding=true` 只有在必填字段齐全时才成功。

### 5.3 Dashboard

`GET /api/dashboard?date=YYYY-MM-DD` 返回 `server_date`、`data_as_of`，以及四个相互独立的区块：

- `follow_up`
- `today_medications`
- `monthly_medication_summary`
- `latest_report`

每个区块固定返回 `status`、`data`、`error_code`。`status` 为 `ok/empty/error`；空数据使用 `empty` 和 `data: null`（今日用药也可返回空数组）；局部查询失败使用 `error` 和稳定错误码。单一区块失败时聚合接口仍返回 HTTP 200，其他区块继续返回自身结果；认证等全局错误仍使用对应 HTTP 状态。

- `follow_up.data`：`date`、`timing`、`days`。`timing` 为 `upcoming/due/overdue`，`days` 始终非负。
- `today_medications.data[]`：`medication_id`、`drug_name`、`specification`、`dosage_text`、`frequency`、`intake_status`、`recorded_at`。
- `monthly_medication_summary.data`：`month`、`taken_count`、`missed_count`、`unrecorded_count`、`by_medication[]`。
- `latest_report.data`：`report_id`、`status`、`generated_at`；无报告时该区块为 `empty`。

禁止返回“完成率”或把 `unrecorded` 计入 `missed`。

### 5.4 用药与每日状态

用药对象字段：

`id`、`drug_name`、`normalized_drug_name`、`specification`、`dosage_text`、`dosage_value`、`dosage_unit`、`frequency`、`route`、`start_date`、`end_date`、`current_status`、`source_type`、`source_document_id`、`replaces_medication_id`、`created_at`、`updated_at`。

- `current_status`：`active/paused/stopped/unknown`。
- 新增/编辑请求还包含 `change_reason`、`event_date`、`note`。
- 停药必须附带 `stop_source`：`written_order/verbal_doctor/patient_self/other`。
- 后端每次修改生成 `medication_event`，事件类型：`started/adjusted/paused/resumed/stopped`。
- 剂量或频率调整不能覆盖旧记录：结束旧版本并创建新版本，新版本通过 `replaces_medication_id` 指向旧版本。

每日状态请求：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `record_date` | date | 是 | 设备选择日期，后端校验 |
| `intake_status` | enum | 是 | `taken/missed/unrecorded` |
唯一键为 `patient_id + medication_id + record_date`，重复 PUT 覆盖当日状态但不创建重复行。

### 5.5 经期与体重

经期字段：`id`、`start_date`、`end_date`、`flow_level`、`cycle_length_days`、`duration_days`、`note`、`source_type`、`created_at`、`updated_at`。

- `flow_level`：`light/medium/heavy/unknown`。
- `end_date` 可空；不能早于开始日期。
- `cycle_length_days` 和 `duration_days` 由后端计算。
- 周期重叠返回 `CYCLE_DATE_OVERLAP`。
- `DELETE /api/cycles/{cycle_id}` 采用逻辑删除；默认查询不返回已删除记录。

体重字段：`id`、`measured_at`、`weight_kg`、`source_type`、`note`、`created_at`。

- 只保存 kg，合法范围 20.0–300.0 kg，最多一位小数。
- 同一患者同一自然日 POST 视为更新并返回现有 ID。

### 5.6 材料与修订

材料类型固定为：

- `lab_report`
- `medical_order`
- `imaging_text_report`
- `outpatient_record`

上传使用 `multipart/form-data`：`file`、`document_type`、可选 `encounter_id`、可选 `external_processing_consent_version`。

材料响应字段：`id`、`patient_id`、`encounter_id`、`document_type`、`original_file_name`、`mime_type`、`file_size_bytes`、`pixel_count`、`page_count`、`file_hash`、`upload_status`、`current_revision_id`、`uploaded_at`、`deleted_at`。

修订字段：`id`、`document_id`、`revision_number`、`file_hash`、`file_size_bytes`、`replaced_revision_id`、`replacement_reason`、`is_current`、`created_at`。

替换文件必须创建新修订；OCR 字段纠错不创建文件修订。软删除后普通列表立即不可见，但已被报告快照引用的修订继续可追溯。

### 5.7 OCR 任务与四类草稿

创建请求：`document_id`、`document_revision_id`、可选 `force_new_attempt=false`。材料类型、Prompt 和模型由后端根据修订确定。

任务字段：`id`、`document_id`、`document_revision_id`、`document_type`、`task_status`、`attempt_count`、`max_attempts`、`queued_at`、`started_at`、`finished_at`、`processing_ms`、`error_code`、`error_message`、`result_source`、`progress`。

- `task_status`：`pending/processing/succeeded/failed/timeout/fallback/confirmed`。
- `result_source`：`qwen_api/fallback/null`。
- Flutter 在 `pending/processing` 时每 2 秒轮询，进入后台后暂停高频轮询。

草稿公共字段：`result_id`、`task_id`、`document_type`、`validation_status`、`critical_error`、`result_source`、`fields[]`、`draft`。

字段级 `fields[]`：`field_path`、`raw_text`、`parsed_value`、`confidence`、`uncertainty_reason`、`source_region`、`user_value`、`confirmation_status`。

四类 `draft`：

- 化验：`hospital_name`、`sample_date`、`report_date`、`items[]`；item 含 `item_name/item_code/raw_value/numeric_value/raw_unit/normalized_unit/reference_range_text/reference_low/reference_high`。
- 医嘱：`hospital_name`、`department_name`、`prescribed_at`、`orders[]`；order 含 `source_text/drug_name/normalized_drug_name/specification/dosage_text/dosage_value/dosage_unit/frequency/duration/route/instruction`。
- 影像文字：`examination_name`、`body_part`、`examination_method`、`findings_text`、`conclusion_text`、`examined_at`、`reported_at`。
- 门诊：`hospital_name`、`department_name`、`doctor_name`、`visit_date`、`chief_complaint`、`diagnosis_summary`、`treatment_plan`、`medical_advice`。

确认请求必须携带 `result_id`、`expected_revision_id`、`confirmed_data` 和 `field_confirmations[]`。医嘱每个 order 都必须确认，只有化验允许批量确认。响应返回 `created_resource_ids[]`、`confirmed_at`、`reconciliation_required`。

### 5.8 用药对账

创建请求：`source_document_id`、可选 `medical_order_ids[]`。

对账对象：`id`、`source_document_id`、`status`、`summary`、`items[]`、`created_at`、`confirmed_at`。

item 字段：`id`、`existing_medication_id`、`new_medical_order_id`、`medication_concept_id`、`drug_name`、`comparison_type`、`old_instruction`、`new_instruction`、`differences`、`user_decision`、`decision_note`。

- `comparison_type`：`unchanged/adjusted/added/stopped/uncertain/manual_review`。
- `user_decision`：`accept/keep_existing/confirm_stopped/needs_review`。
- `confirm_stopped` 必须提供 `stop_date` 和 `stop_source`。
- 所有 item 有决策后才能把对账状态改为 `confirmed`；写入当前用药和事件链必须在同一事务完成。

### 5.9 患者自述、报告与 PDF

患者自述字段：`id`、`patient_id`、`encounter_id`、`original_text`、`confirmed_text`、`status`、`confirmed_by_uid`、`confirmed_at`、`source_patient_note_id`、`created_at`、`updated_at`。状态为 `draft/confirmed/skipped/consumed`，确认文本不调用模型改写。

- `POST /api/patient-notes` 创建草稿；`PUT /api/patient-notes/{note_id}` 只修改未消费的草稿。
- `GET /api/patient-notes/latest` 获取当前患者最近一次自述。
- `POST /api/patient-notes/{note_id}/confirm` 与 `/skip` 为幂等状态操作。
- `POST /api/patient-notes/{note_id}/copy` 从历史自述创建新的独立草稿，并通过 `source_patient_note_id` 追溯来源；复制结果必须重新确认。
- `consumed` 自述只读，不能原地修改或影响既有报告。

创建报告请求：`patient_note_id`（可空）、`include_sections[]`（可空，默认全部）。响应：`report_id`、`status`、`generated_at`、`snapshot_hash`。

报告详情三层结构：

- `summary`：患者摘要、自述原文、当前用药、最新指标、经期/体重摘要、免责声明。
- `trends[]`：`metric_id`、`metric_name`、`unit`、`comparability`、`points[]`；point 含 `value/raw_value/date/date_source/abnormal_status/source_id`。
- `sources[]`：`source_number`、`source_type`、`source_id`、`document_id`、`document_revision_id`、`original_value`、`original_unit`、`reference_range_text`、`material_date`、`date_source`、`file_url`。

后端报告不接收或聚合 Flutter 本地认证状态。Flutter拿到 `document_id + document_revision_id` 后自行叠加本地水印。

PDF 对象字段：`report_id`、`file_id`、`generation_status`、`file_name`、`mime_type`、`file_size_bytes`、`file_hash`、`generated_at`、`download_url`、`download_expires_at`、`failure_reason`。

### 5.10 确定性规则与执行追溯

`GET /api/deterministic-rules` 仅供管理端使用，返回规则数组。每条规则字段：`id`、`rule_key`、`rule_type`、`rule_name`、`parameters`、`priority`、`enabled`、`updated_at`。

- `rule_type`：`reference_range/date_source/freshness/unit_conversion/comparability/reconciliation`。
- `parameters` 只能保存经过 Schema 验证的 JSON 参数，不允许保存或执行 Python 表达式。
- `PUT /api/deterministic-rules/{rule_id}` 请求字段：`parameters`、`priority`、`enabled`、`updated_at`；最后一个字段用于并发冲突检测。

`GET /api/rule-executions/{execution_id}` 返回：`id`、`rule_id`、`source_type`、`source_id`、`input_digest`、`input`、`output`、`explanation`、`executed_at`。前端普通用户页面不直接调用；报告来源调试和审计使用。

### 5.11 后端接口与数据表映射

| 接口域 | 主表 | 同事务/关联表 |
|---|---|---|
| Auth | `user_account`、`user_session` | 会话只存哈希 |
| Patient | `patient_profile` | 完成引导时原子更新 `user_account.onboarding_completed` |
| Dashboard | 无独立写表 | 聚合 `patient_profile`、`medication*`、`report_snapshot` |
| Medications | `medication` | `medication_event`、`medication_daily` |
| Cycles/Weights | `menstrual_cycle`、`weight_record` | 日期和趋势由后端计算 |
| Documents | `document`、`document_revision` | 文件在私有目录，表内只存相对路径和哈希 |
| OCR | `ocr_task`、`ocr_result`、`ocr_field_result` | 确认后写 `lab_observation`、`medical_order`、`imaging_report` 或 `outpatient_record` |
| Reconciliation | `medication_reconciliation`、`medication_reconciliation_item` | 确认时写 `medication` 和 `medication_event` |
| Rules | `deterministic_rule`、`rule_execution` | 禁止在数据库保存可执行 Python 表达式 |
| Reports | `patient_note`、`report_snapshot`、`report_source`、`report_file` | 快照创建后不可覆盖 |

首个数据库迁移需要把接口契约补充字段落盘：

- `patient_profile.usual_cycle_length_days INTEGER NULL`
- `patient_profile.external_ocr_notice_version TEXT NULL`
- `medication_event.stop_source TEXT NULL`
- 幂等记录表：`idempotency_record(id, account_uid, endpoint_key, idempotency_key, resource_type, resource_id, response_digest, expires_at, created_at)`，并对 `account_uid + endpoint_key + idempotency_key` 建唯一索引。
- `weight_record` 增加患者本地日期列或等价唯一索引，保证同一患者同一天幂等更新。

`onboarding_step` 是根据画像字段计算的响应字段，不要求单独存库；`last_menstrual_start_date` 完成引导时写入首条 `menstrual_cycle`，避免在画像与周期表重复维护两份正式数据。

## 6. 错误码与前端动作

| HTTP | `error.code` | Flutter 动作 |
|---:|---|---|
| 422 | `VALIDATION_ERROR` | 标注字段，不清空用户输入；认证请求也包括多余字段 |
| 401 | `INVALID_CREDENTIALS` | 登录页提示，不说明账号是否存在 |
| 401 | `AUTHENTICATION_REQUIRED` | 清安全存储并跳登录；覆盖缺失、无效、撤销或过期 Session |
| 403 | `FORBIDDEN_RESOURCE` | 提示无权访问，不重试 |
| 404 | `RESOURCE_NOT_FOUND` | 返回上一页并刷新 |
| 409 | `ACCOUNT_NAME_TAKEN` | 注册页定位账号字段 |
| 409 | `RESOURCE_VERSION_CONFLICT` | 重新拉取详情，提示内容已更新 |
| 409 | `RECONCILIATION_REQUIRED` | 跳用药对账页 |
| 413 | `FILE_TOO_LARGE` / `IMAGE_TOO_LARGE` | 重新选择或压缩 |
| 415 | `UNSUPPORTED_FORMAT` / `MULTI_PAGE_PDF` | 显示支持格式 |
| 422 | `SCHEMA_VALIDATION_FAILED` / `CRITICAL_FIELD_MISSING` | 打开草稿并突出字段 |
| 429 | `AUTH_RATE_LIMITED` | 认证页按 `Retry-After` Header 倒计时 |
| 429 | `RATE_LIMITED` | 其他业务接口按 `retry_after_seconds` 延迟 |
| 502 | `INVALID_MODEL_JSON` | 允许重试；预置材料可提示兜底 |
| 504 | `MODEL_TIMEOUT` | 允许重试；不要创建正式数据 |
| 409 | `REPORT_SOURCE_INCOMPLETE` | 显示缺少哪些确认数据 |
| 500 | `PDF_GENERATION_FAILED` | 允许重试，不影响 App 内报告 |

## 7. 并行开工顺序

### 7.1 可直接领取的任务看板

`已完成` 表示仓库中已有代码和测试；`待开发` 表示接口字段已冻结、可以直接领取。领取后在团队看板补负责人和 PR 链接，不要通过聊天临时改字段。

| ID | 状态 | 领取方 | 工作内容 | 依赖 | 交付与验收 |
|---|---|---|---|---|---|
| BE-00 | 已完成 | 后端 | 账号注册、登录、`/auth/me`、退出、SQLite Session、限流 | 无 | `backend/tests` 已覆盖；不得破坏现有响应 |
| FE-00 | 已完成 | 前端 | Dio Bearer Header、系统安全存储 | BE-00 | Header 为 `Authorization: Bearer`，清 Session 后不再发送 |
| FE-01 | 待开发 | 前端 | `AccountDto`、`LoginResponseDto`、`AuthRepository`，登录/注册页接真接口，冷启动恢复 | BE-00 | 注册后自动登录；401 清 Session；按 `onboarding_completed` 路由 |
| BE-01 | 待开发 | 后端 | 患者画像 GET/PUT 和引导完成事务 | BE-00 | 分步保存、字段校验、完成状态和 409 测试 |
| FE-02 | 待开发 | 前端 | 四步引导接画像接口，移除账号路由中的 `DemoAccount` 依赖 | FE-01、BE-01 | 杀进程重开不丢步骤；完成后进入 Dashboard |
| BE-02 | 待开发 | 后端 | 用药、事件、每日三状态、经期、体重、Dashboard 聚合 | BE-01 | `unrecorded` 不等于 `missed`；事件不可覆盖；同日体重幂等 |
| FE-03 | 待开发 | 前端 | Dashboard/用药/经期/体重 Repository 与页面状态 | BE-02 | 成功、空数据、加载、401、409、500 均有页面状态 |
| BE-03 | 待开发 | 后端 | 材料、修订、私有文件流、OCR 任务/草稿/确认/重试 | BE-01 | 文件限制、租约、字段级来源、确认事务和失败测试 |
| FE-04 | 待开发 | 前端 | 上传进度、2 秒 OCR 轮询、四类确认页和错误恢复 | BE-03 | 页面退出停止轮询；未确认草稿不进入正式数据 |
| BE-04 | 待开发 | 后端 | 医嘱对账、规则执行、患者自述、报告快照、PDF | BE-02、BE-03 | 旧药不自动停；快照不可变；PDF 和 App 同源 |
| FE-05 | 待开发 | 前端 | 对账、报告三层、PDF 下载/分享/打印 | BE-04 | 所有来源可追溯；生成中/失败/完成状态明确 |
| QA-01 | 待开发 | 联调/测试 | OpenAPI 契约测试、后端 fixture、Flutter Repository 测试、端到端验收 | 对应 BE/FE | 同一字段在 OpenAPI、Pydantic、DTO 和 fixture 中一致 |

### 7.2 工作包说明

#### 工作包 A：基础与账号（后端先行）

后端：认证、异常中间件、SQLite 迁移、密码哈希、会话、注册/登录/恢复/退出已经实现；下一步实现画像，并保持现有认证响应兼容。

前端：AuthRepository、SessionStore、真实登录/注册、启动路由、画像 DTO 与分步保存。注册流程必须执行“注册成功 → 登录 → 安全保存 Session”；冷启动通过 `/api/auth/me` 恢复。

完成定义：新账号真实入库；重启可恢复会话；新用户进引导，老用户进 Dashboard。

#### 工作包 B：日常记录（可与 A 后半段并行）

后端：用药/事件/每日状态、经期、体重、Dashboard 聚合。

前端：替换 Dashboard、用药、经期和体重页面的硬编码数据。

完成定义：三状态互斥且未记录不等于漏服；历史不被覆盖；同日体重幂等。

#### 工作包 C：文件与 OCR

后端：私有文件、修订、OCR 任务/租约 Worker、Qwen 适配器、四类 Schema、字段级结果。

前端：DocumentRepository、上传进度、2 秒轮询、四类确认 DTO、权限和错误恢复。

完成定义：未确认草稿不进正式数据；任一正式字段可追溯至原件修订。

#### 工作包 D：对账与报告

后端：确定性规则、用药对账事务、患者自述、不可变报告、来源关系、PDF Worker。

前端：对账逐项决策、报告生成状态、三层页面、文件下载/分享/打印。

完成定义：旧药未出现不自动停药；快照不随源数据静默变化；PDF与 App 报告来自同一快照。

#### 工作包 E：联调与验收

- 后端先根据 OpenAPI 生成 stub，前端根据相同契约写 DTO/Repository。
- 每个工作包提供成功、空数据、401、422、409 和 500 fixture。
- 联调环境禁止使用数据库路径、文件绝对路径和模型原始响应作为前端字段。
- Android模拟器和至少一台真机走完注册→画像→Dashboard→四类材料→确认→对账→报告→PDF。

## 8. 前端需要建立的 Repository

```text
AuthRepository
PatientRepository
DashboardRepository
MedicationRepository
CycleRepository
WeightRepository
DocumentRepository
OcrRepository
MedicationReconciliationRepository
PatientNoteRepository
ReportRepository
CertificationRepository  // 当前仅本地实现，不调用 FastAPI
```

每个 Repository 只暴露 Domain 对象；Dio、JSON 和接口错误转换留在 Data 层。页面不得直接调用 `PomiApiClient.dio`。

## 9. 后端目录落位

```text
backend/src/pomi_backend/
├── api/            # auth, patient, dashboard, medications, cycles, weights,
│                   # documents, ocr, reconciliations, reports, rules
├── schemas/        # 与 OpenAPI 同名的 Pydantic request/response
├── models/         # SQLite 模型
├── repositories/   # 事务边界和查询
├── services/       # 状态机、聚合、幂等、报告
├── integrations/   # Qwen3-VL 与私有文件存储适配器
├── rules/          # 日期、参考范围、趋势、单位白名单、对账
├── workers/        # OCR 与 PDF 单进程 Worker
└── core/           # config, security, errors, logging, request_id
```

任何接口字段变更必须同时修改 OpenAPI、Pydantic Schema、Flutter DTO 和契约测试。
