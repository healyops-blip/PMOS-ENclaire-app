# POMI 前后端联调实施计划与接口映射

> 状态：待实施（审计后冻结范围）
>
> 适用分支：`healy/pomi-fullstack-integration`
>
> 本文是实施计划，不是接口实现。当前只完成差异审计，未修改业务代码。

## 1. 目标与边界

目标是让真实登录用户完成一条可验证闭环：

`登录 → 患者资料 → 用药/经期/体重 → 上传材料 → OCR → 用户确认 → 报告 → 趋势/来源追溯`

本地联调环境固定为：

- Flutter Web：`http://127.0.0.1:3010`
- FastAPI：`http://127.0.0.1:8000`
- 数据库：本地 SQLite（使用仓库 `backend` 的 SQLAlchemy/Alembic 模型）
- 鉴权：真实 Bearer session
- 初始数据：`20260828_200621` 数据集导入测试账号，导入必须幂等

不在本轮范围内：真实医院 KYC/KYB、真实区块链交易、短信验证、生产远程数据库。

## 2. 当前阻塞项

| 优先级 | 问题 | 当前表现 | 处理方案 |
|---|---|---|---|
| P0 | OCR 确认 DTO 不一致 | 前端确认请求缺少 `result_id`、`expected_revision_id`；后端严格校验 | 统一使用 `/api/ocr/tasks/{task_id}/confirm`，按材料类型适配确认 DTO；前端保存 task/result/revision 三个 ID |
| P0 | OCR 流程模式不一致 | 前端调用同步 `/api/ocr/recognize`；既定方案是异步任务轮询 | 选择异步任务为主流程：上传/建任务 → 轮询 → 结果 → 确认 → 刷新；同步接口仅保留兼容用途 |
| P0 | 用药对账枚举不一致 | 前端 `accept_new/keep_existing/stop_existing/manual_review`；后端 `accept/keep_current/reject` | 按已确认决策以前端值和交互为准，由后端增加兼容 DTO/映射；数据库仍保存可审计的标准决策和备注 |
| P0 | 存证仍是本地模拟 | `CertificationRepository` 使用 SharedPreferences，无后端表/接口 | 本轮先明确为本地演示能力；若要求真实落库，新增 certification 表、接口、状态轮询和水印文件版本字段 |
| P1 | Web API 地址/CORS | 前端默认 `10.0.2.2:8000`，浏览器应访问 `127.0.0.1:8000`；后端默认 CORS 未包含 3010 | 按运行平台注入 `POMI_API_BASE_URL`，并将 3010 加入本地 CORS |
| P1 | 模拟数据未自动落库 | Smoke 数据在 Flutter 内存/asset 中，不能证明真实 SQLite 报告趋势 | 增加幂等 seed/import 命令，写入正式表并绑定开发账号 |
| P1 | 后端实现存在两份 | 仓库 `backend/src/pomi_backend` 与工作区旧版 `pomi-backend/apps/backend` 路由/字段不同 | 联调只允许启动仓库 `backend`；旧版标记为 legacy，不作为接口依据 |

## 3. 分阶段实施顺序

### 阶段 0：运行基线

1. 固定启动目标为 `backend/src/pomi_backend`。
2. 配置本地 API 地址、CORS、SQLite 路径和存储目录。
3. 执行 Alembic migration。
4. 创建开发账号（密码只通过环境变量提供）。
5. 幂等导入 `20260828_200621`，记录导入批次和资源映射。
6. 用 `/health/live`、`/health/ready` 验证服务和数据库。

### 阶段 1：基础资料与健康记录

1. 登录/恢复会话。
2. 读取和保存患者资料，处理 `updated_at` 版本冲突。
3. 验证药品新增、编辑、事件历史和每日状态。
4. 验证经期开始/结束日期、体重记录和重复日期约束。
5. 写入成功后失效 Dashboard、Tracking、Medication、Profile provider 并重新拉取。

### 阶段 2：材料、OCR 与正式化数据

1. 上传四类材料并保存文档/修订版本。
2. 创建异步 OCR task，轮询 `pending/processing/succeeded/failed/timeout`。
3. 读取草稿，按材料类型显示字段确认页。
4. 确认后写入 `lab_observation`、`medical_order`、`imaging_report`、`outpatient_record`。
5. 失败支持重试；确认失败保留用户输入并显示可恢复错误。

### 阶段 3：报告、趋势与来源

1. 患者自述确认或跳过。
2. 调用报告 preflight，展示缺失区块。
3. 用户确认不完整内容后生成不可变报告快照。
4. 验证后端趋势聚合：经期、BMI、化验指标、采样日期优先级、单位换算和新鲜度。
5. 验证趋势节点到 `document_id + document_revision_id` 的来源追溯。
6. 验证报告列表、详情、重复 source digest 复用和 PDF 状态。

### 阶段 4：验收与回归

- 后端 API 契约测试：所有 P0/P1 接口和错误码。
- Flutter repository/widget 测试：字段映射、状态、provider 刷新。
- 一条真实端到端流程：注册/登录 → 资料 → 记录 → 上传 OCR → 确认 → 报告/趋势。
- 两个账号隔离测试：账号 A 不可读取账号 B 的记录、文件和报告。

## 4. 接口映射表

状态说明：✅ 已基本对齐；⚠️ 存在风险；❌ 当前阻塞。

| 业务 | 前端调用位置 | 方法与路径 | 后端实现 | 请求/响应关键字段 | 状态 |
|---|---|---|---|---|---|
| 注册 | `auth_controller.dart` | `POST /api/auth/register` | `api/auth.py` | `account_name`、`password`；返回 `AccountResponse` | ✅ |
| 登录 | `auth_controller.dart` | `POST /api/auth/login` | `api/auth.py` | 返回 `session_id`、`expires_at`、`account` | ✅ |
| 会话恢复 | `auth_controller.dart` | `GET /api/auth/me` | `api/auth.py` | Bearer；返回账号状态 | ✅ |
| 退出 | `auth_controller.dart` | `POST /api/auth/logout` | `api/auth.py` | Bearer；204 | ✅ |
| 患者资料 | `patient_repository.dart`、`profile_screen.dart` | `GET/PUT /api/patient/profile` | `api/patient.py` | `updated_at` 乐观锁；身高、日期独立字段 | ✅ |
| Onboarding | `onboarding_repository.dart` | `GET /api/onboarding`、`PUT /api/onboarding/steps/*`、`POST /api/onboarding/complete` | `api/onboarding.py` | `birth_year`、周期日期、药品 items | ✅ |
| Dashboard | `dashboard_screen.dart` | `GET /api/dashboard` | `api/dashboard.py` | section `{status,data,error_code}` | ✅ |
| 药品列表 | `medication_repository.dart`、`dashboard_screen.dart` | `GET /api/medications` | `api/medications.py` | `items`、`server_date`、`has_more` | ✅ |
| 药品新增/编辑 | `medication_repository.dart`、`dashboard_screen.dart` | `POST/PUT /api/medications*` | `api/medications.py` | `source_category`、剂量/频次分字段 | ✅ |
| 每日用药 | `medication_repository.dart`、`dashboard_screen.dart` | `GET /api/medication-daily`、`PUT /api/medications/{id}/daily-status` | `api/medications.py` | 当前枚举为 `taken/missed/unrecorded` | ✅ |
| 经期 | `tracking_repository.dart` | `GET/POST /api/cycles`、`PUT/DELETE /api/cycles/{id}` | `api/cycles.py` | `start_date`、`end_date`、`flow_level` | ✅ |
| 体重 | `tracking_repository.dart` | `GET/POST /api/weights`、`PUT /api/weights/{id}` | `api/weights.py` | `record_date`、`weight_kg`、版本字段 | ⚠️ |
| 材料上传 | `upload_screen.dart` | `POST /api/ocr/recognize`（当前） | `api/ocr.py` | 同步接口内部创建 document；要求幂等键/同意版本 | ⚠️ |
| OCR 异步任务 | 当前前端未作为主流程使用 | `POST /api/ocr/tasks`、`GET /api/ocr/tasks/{id}` | `api/ocr.py` | 建议改为主流程 | ❌ |
| OCR 草稿 | 当前确认页间接使用 | `GET /api/ocr/tasks/{id}/result` | `api/ocr.py` | `validated_draft`/字段级信息 | ⚠️ |
| OCR 确认 | `upload_screen.dart` | 当前 `/api/ocr/results/{resultId}/confirm` | `api/ocr.py` | 需要 `result_id`、`expected_revision_id` 和严格 DTO | ❌ |
| 文档列表/详情 | `records_screen.dart` | `GET /api/documents`、`GET /api/documents/{id}` | `api/documents.py` | `items`、`latest_ocr_task_id/status` | ✅ |
| 原件/修订 | `records_screen.dart` | `GET /api/documents/{id}/revisions/{rid}/file` | `api/documents.py` | 私有文件流、修订 ID | ✅ |
| 用药对账 | `records_screen.dart` | `POST/GET/PUT /api/medication-reconciliations*` | `api/reconciliations.py` | 后端兼容前端决策值并落标准状态 | ❌ |
| 患者自述 | `records_screen.dart` | `POST/PUT /api/patient-notes*` | `api/patient_notes.py` | 确认/跳过/复制 | ✅ |
| 报告 | `records_screen.dart` | `POST /api/reports/preflight`、`POST/GET /api/reports*` | `api/reports.py` | `include_sections`、`confirm_incomplete`、`snapshot` | ✅ |
| 趋势 | `records_screen.dart` | 报告详情内 `snapshot.trends` | `services/reports.py` | 后端聚合，前端绘图 | ✅ |
| PDF | 当前页面未完整接入 | `POST/GET /api/reports/{id}/pdf`、`.../file` | `api/reports.py` | 异步生成状态与文件流 | ⚠️ |
| 存证/水印 | `certification_repository.dart` | 当前无后端路径 | 无对应 API/表 | SharedPreferences 本地模拟 | ❌ |

## 5. 数据库落点与一致性规则

| 数据 | 主表 | 关键关联 | 一致性要求 |
|---|---|---|---|
| 账号/会话 | `user_account`、`user_session` | `account_uid` | 只存会话哈希；所有业务查询按当前账号患者范围过滤 |
| 患者资料 | `patient_profile` | `account_uid` 唯一 | 用 `updated_at` 做版本控制 |
| 药品 | `medication`、`medication_event` | `patient_id`、`medication_id` | 药量、单位、频次分字段；变更写事件 |
| 每日用药 | `medication_daily` | `(medication_id, record_date)` 唯一 | `unrecorded` 不应伪造为已服用 |
| 经期/体重 | `menstrual_cycle`、`weight_record` | `patient_id` | 开始/结束日期分开；体重按业务日期唯一 |
| 文档 | `document`、`document_revision` | `current_revision_id` | 原件不可覆盖，替换产生新 revision |
| OCR | `ocr_task`、`ocr_result`、`ocr_field_result` | task/result/revision | 草稿未确认不得进入正式健康表 |
| 医疗数据 | `lab_observation`、`medical_order`、`imaging_report`、`outpatient_record` | document + OCR result | 医院、科室、日期分字段；检验趋势优先采样日期 |
| 报告 | `report_snapshot`、`report_source` | source digest + revision | 快照不可变；来源必须带文档修订信息 |
| 药品目录 | `medication_catalog_entry` | version/source | 目录可查询；用户自定义药品进入 `medication`，不覆盖静态目录 |
| 存证（待定） | 尚无表 | document/revision | 若纳入真实闭环，需新增状态、时间、哈希、水印版本字段 |

## 6. 统一错误与刷新策略

- `401`：清理本地 session，回登录页。
- `409 RESOURCE_VERSION_CONFLICT`：重新拉取后提示用户合并。
- `409` OCR 未完成/报告缺资料：保留页面输入，提供继续或重试。
- `422`：根据字段错误定位表单，不用通用“保存失败”。
- 写入成功后失效对应 Riverpod provider，重新读取数据库结果；不要只更新局部内存状态。

## 7. 完成定义（Definition of Done）

- 所有 P0 接口请求/响应字段与 OpenAPI、数据库模型一致。
- OCR 四类材料均能完成“上传 → 任务 → 确认 → 正式表”。
- 报告趋势只读取已确认正式数据，并能追溯到文档修订。
- 至少一条真实端到端流程和账号隔离测试通过。
- `flutter analyze`、`flutter test`、后端 `pytest` 和 Web 构建通过。
- 本文中的 P0/P1 差异全部关闭或明确标记为本地演示限制。
