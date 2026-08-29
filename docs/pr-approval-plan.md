# PR 审批计划

更新日期：2026-08-27

## 目标与范围

本计划用于审查 `healyops-blip/PMOS-ENclaire-app` 的开放 Pull Request，并按依赖顺序将可验证、可追溯且满足 Issue 验收标准的改动推进到 `main`。

当前范围包含 19 个开放 PR：前端基础 PR #4，以及对应开放 Issue #12–#18、#20–#30 的 18 个功能 PR。

审批由本地 `dependency-aware-pr-review` skill 驱动，并使用 `pm-ai-shipping:intended-vs-implemented` 方法。PR 显示可合并、作者声明测试通过或代码表面完整，都不能单独作为批准依据。

## 意图来源优先级

1. 对应 GitHub Issue 的目标、范围、依赖、非目标和验收标准。
2. `docs/architecture.md` 中的组件边界、安全规则和变更流程。
3. `contracts/` 中的 OpenAPI 与 JSON Schema 契约。
4. 功能 README、技术决策、隐私和部署文档。
5. PR 描述仅用于补充背景；与以上来源冲突时不能覆盖正式意图。

如果正式意图缺失或互相冲突，审批状态应为 `BLOCKED`，先补齐或澄清意图。

## 审批门槛

每个 PR 必须逐项满足以下门槛：

### 1. 依赖与范围

- 父 Issue/PR 已通过审批并进入目标基线，或当前 PR 明确基于可验证的集成基线。
- 改动覆盖 Issue 的全部验收标准，没有把必需项静默留到后续。
- 没有混入无关功能、生成产物、密钥、真实患者数据或大规模非必要重构。
- `Out of scope` 内容没有被意外实现，尤其不得扩大医疗、认证或公开访问承诺。

### 2. Intended vs. Implemented

- 为每条关键意图找到具体实现证据：文件、行号、调用路径或测试。
- 服务端在每条相关路径执行 UID/患者归属和 Session 鉴权；客户端隐藏按钮不算安全控制。
- 私有医疗材料、报告、Session、下载凭证和外部 API Key 不被日志、响应或客户端包泄露。
- 数据库约束、事务、幂等、软删除、不可变性和修订关系与 Issue 一致。
- 若发现边界差异，记录：书面意图、实现现实、攻击者/受影响对象、严重度和具体修复。

### 3. 自动化验证

Flutter 基础门槛：

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

后端基础门槛：

```bash
cd backend
python -m pip install -e '.[dev]'
python -m alembic upgrade head
pytest
ruff check .
```

按 PR 风险补充迁移升级/回退、跨 UID、失败回滚、并发幂等、Worker 重启、文件权限、离线缓存、Widget、模拟器或真机验证。

每个功能还必须建立验收条件到用例证据的映射，至少覆盖：正常路径、空状态、无效/边界输入、鉴权与 Session 失效、跨 UID 隔离、加载/失败/重试与输入保留、幂等/并发（适用时）、全新与当前生产 schema 迁移、前后端契约和生产入口 wiring；文件、Worker、离线或设备功能还需补对应专项用例。只执行仓库原有测试不构成充分审批证据。

### 4. 审批结论

- `APPROVED`：依赖满足，全部阻断问题关闭，关键意图有代码与测试证据，CI/本地验证通过。
- `CHANGES_REQUESTED`：存在可复现的正确性、安全、数据完整性、契约或验收缺口；在 GitHub 提交带证据的修改请求。
- `BLOCKED`：依赖未合入、正式意图冲突、环境/密钥/设备不可用，导致无法形成可靠结论。`BLOCKED` 不是批准。
- `IN_REVIEW`：证据仍在收集中，不提交 GitHub Approval。

## 工作步骤

对每个 PR 按以下顺序执行：

1. 记录 PR 的 head、base、对应 Issue、依赖、改动规模和 CI 状态。
2. 读取完整 Issue、PR 描述、相关架构/契约文档和迁移说明。
3. 审查完整 diff，并沿鉴权、持久化、文件、日志、外部调用和 UI 状态路径追踪实现。
4. 将验收标准映射到实现文件、代码行和自动化测试。
5. 在隔离 worktree 中基于 PR head 执行适用检查，避免污染主工作区。
6. 按严重度记录发现；阻断问题必须在批准前修复并复验。
7. 在 GitHub 提交 `Approve` 或 `Request changes`，并在本文件更新证据与结论。
8. 父 PR 合入后，将子 PR 同步到最新 `main`、调整 base、重新跑检查，再进行最终审批。

GitHub 沟通规则：只有完成对应 PR 的代码与测试审查后才发布结论。发现具体问题时，以可引用的代码证据评论并提交 `Request changes`；未发现阻断问题时直接 `Approve` 并按批准的目标分支合并。不发布仅说明依赖、计划或待审状态的泛化评论。

## 依赖批次与审批顺序

| 批次 | PR / Issue | 前置条件 | 初始状态 |
|---|---|---|---|
| 0 | PR #4 前端与 API 基线 | `main` | CHANGES_REQUESTED |
| 1 | PR #32 / Issue #12 | PR #4 | CHANGES_REQUESTED（且依赖阻断） |
| 2 | PR #33/#36/#34/#35 / Issue #13/#14/#15/#16 | #12；四项可并行审查 | CHANGES_REQUESTED |
| 3 | PR #39/#37/#41 / Issue #17/#20/#27 | #17 依赖 #13–#16；#20/#27 依赖 #13 | PENDING |
| Later | PR #38 / Issue #18 | #14；不纳入 Dashboard P0 | DEFERRED |
| 4 | PR #40 / Issue #21 | #20 | PENDING |
| 5 | PR #42/#44/#43 / Issue #22/#23/#24 | #22/#24 依赖 #20/#21；#23 另依赖 #14 | PENDING |
| 6 | PR #46/#45 / Issue #25/#26 | #20–#24；#26 不依赖 #25 | PENDING |
| 7 | PR #47 / Issue #28 | #27、#14–#16、#22–#24 | PENDING |
| 8 | PR #48 / Issue #29 | #20、#26、#28 | PENDING |
| 9 | PR #49 / Issue #30 | #28、#29 | PENDING |

同一批次可以并行收集证据，但 GitHub 最终批准仍须等待各自前置依赖满足。

## CI 与仓库级阻断项

- `.github/workflows/core-checks.yml` 当前只对 base 为 `main` 的 PR 自动运行；堆叠 PR 没有 GitHub Check 记录。
- `main` 当前工作流没有执行后端 `pytest`、`ruff` 或 Alembic 迁移验证；PR #4 head 已补入这些步骤，但须在契约问题修复后随 PR #4 一起复验。
- 在堆叠 PR 改为 `main` 前，必须通过手动检查或扩展工作流提供等价证据。
- `main` 应要求 Core checks 成功并至少获得一次非作者审批。

## 审批记录

每个 PR 的记录至少包含：

- 审查时间、审查人、head SHA、base SHA。
- 对应 Issue 和依赖状态。
- 关键意图到代码/测试的证据映射。
- 执行过的命令及结果。
- 发现与严重度，或明确记录“未发现阻断问题”。
- GitHub Review 链接和最终结论。

### PR #4

- 状态：CHANGES_REQUESTED
- 审查时间：2026-08-27
- 审查账号：`healyops-blip`
- Head：`9a7d38bb68a3ea4466f122f08ce0f9716ceda62c`
- Base：`main@5b127258ac7374742e77c7b152735f5d4cf440bf`
- GitHub Review：[PR #4](https://github.com/healyops-blip/PMOS-ENclaire-app/pull/4)
- GitHub CI：`Repository checks` 成功。
- 独立验证：
  - Flutter 3.47.1 / Dart 3.13.1。
  - `dart format`、`flutter analyze --fatal-infos`、`flutter test` 通过；8 个测试通过。
  - `ruff format --check`、`ruff check`、`pytest -W error` 通过；25 个后端测试通过。
  - Alembic 全新 SQLite `upgrade head` 和 `check` 通过。
  - OpenAPI：37 paths、48 operations、89 schemas、262 个内部引用，解析和引用完整性通过。
- 阻断发现：
  - Issue #14 要求暂停/恢复和 `replaces_medication_id` 版本链，OpenAPI 无法表达。
  - Issue #15 要求经期逻辑删除，OpenAPI 缺少 `DELETE /api/cycles/{cycle_id}`。
  - Issue #16 要求 `20.0–300.0 kg` 且最多一位小数，OpenAPI 允许到 350 且未限制精度。
  - Issue #17 要求四个 Dashboard 区块独立 `status/data` 和局部失败，OpenAPI 使用单体响应。
  - Issue #27 要求 `draft/confirmed/skipped/consumed` 及 latest/confirm/skip/copy API，OpenAPI 使用 `cancelled` 且缺少状态转换接口。
- 受影响边界：OpenAPI 被声明为 Flutter DTO、FastAPI Schema、fixture 和契约测试的共同基线；继续合并会使前后端生成不兼容实现。
- 复验条件：同步更新人类可读文档与 OpenAPI，增加上述枚举、数值边界和 path 的契约回归测试，并在新 head 上重新执行全部门槛。

### PR #32 / Issue #12

- 状态：CHANGES_REQUESTED；同时受 PR #4 依赖阻断。
- 审查时间：2026-08-27
- 审查账号：`healyops-blip`
- Head：`2f13f03a88ccdc64e8100ecf476e483f10188bff`
- Base：`WilderNoTrack/front@9a7d38bb68a3ea4466f122f08ce0f9716ceda62c`
- GitHub Review：[PR #32](https://github.com/healyops-blip/PMOS-ENclaire-app/pull/32)
- GitHub CI：无 Check 记录；该堆叠 PR 的 base 不是 `main`。
- 独立验证：
  - `ruff format --check`、`ruff check` 通过。
  - 本 PR 原有 28 个后端测试通过。
  - 3 个额外边界探针稳定复现被禁止的行为。
- 阻断发现：
  - Repository 的通用 `update(**changes)` 可修改 `patient_id`，把当前患者记录转移给另一患者。
  - Repository 和数据库允许患者 A 的 `medication_daily` 关联患者 B 的 `medication`；`medication_event.medication_id` 和 `replaces_medication_id` 存在同类边界。
  - `MenstrualCycleRepository.get()` 默认返回已软删除记录，且 `update()` 仍可修改该记录。
- 受影响边界：未来 Service 只要遗漏一次重复校验，跨 UID 医疗数据即可被关联、转移或污染；Issue #12 明确要求数据层承担归属隔离。
- 复验条件：禁止更新身份/所有权字段；在所有关联写路径和数据库约束中保证同患者关系；默认查询/更新排除软删除；提交对应跨 UID 与软删除回归测试；同步到通过审批的 PR #4 新基线。

### PR #33 / Issue #13

- 状态：CHANGES_REQUESTED；同时受 PR #4、#32 依赖阻断。
- 审查时间：2026-08-27
- 审查账号：`healyops-blip`
- Head：`8b3bfcbdfbc64d1a2893866b0ff5a5970328621a`
- Base：`feature/backend-p0-foundation@2f13f03a88ccdc64e8100ecf476e483f10188bff`
- GitHub Review：[PR #33](https://github.com/healyops-blip/PMOS-ENclaire-app/pull/33)
- GitHub CI：无 Check 记录；该堆叠 PR 的 base 不是 `main`。
- 独立验证：
  - `ruff format --check`、`ruff check`、`pytest -W error` 通过；30 个后端测试通过。
  - `dart format`、`flutter analyze`、`flutter test` 通过；10 个现有 Flutter 测试通过。
  - `flutter build apk --debug` 通过。
  - 额外 API 探针确认普通资料编辑会重写 `onboarding_completed_at`。
  - 额外 Widget 探针确认过期日期没有“已到/已超过 N 天”语义；资料保存路径稳定触发 `setState() callback argument returned a Future`。
- 阻断发现：
  - 保存资料后的刷新把 `Future<PatientProfile>` 从 `setState` 回调返回，老用户编辑路径无法通过 Flutter 状态测试。
  - Flutter 对已初始化用户持续发送 `complete_onboarding=true`，后端无条件重写首次初始化完成时间。
  - 过期复诊日期仅显示原始日期，未满足 Issue #13 的“已到/已超过 N 天”业务规则。
  - 无效复诊日期文本被 `DateTime.tryParse` 转为 `null` 并提交，可能静默清除已有日期。
- 受影响对象：所有从资料入口维护复诊日期的老用户；初始化审计时间和用户保存的复诊日期可能失真或丢失。
- 复验条件：修正同步 `setState`；只在首次 false→true 时写初始化时间；实现过期日期三态文案；校验无效日期且保留表单；补编辑成功/失败、时间不可变及日期边界回归测试；父 PR 合入后同步最新 `main` 再执行完整门槛。

### PR #36 / Issue #14

- 状态：CHANGES_REQUESTED；同时受 PR #4、#32 依赖阻断。
- 审查时间：2026-08-27
- 审查账号：`healyops-blip`
- Head：`f123cb01cd45e4f6428966c22ea0ae7dcff94d37`
- 依赖基线：Issue #12 commit `69aad92a6cfd7e4af3b2402c3fb7d7758f428d70`；当前 PR #32 head 另含 PR #4 合并基线。
- GitHub Review：[PR #36](https://github.com/healyops-blip/PMOS-ENclaire-app/pull/36)
- GitHub CI：无 Check 记录。
- 独立验证：
  - `ruff format --check`、`ruff check`、`pytest -W error` 通过；33 个后端测试通过。
  - 全新 SQLite 的 Alembic `upgrade head` 与 `check` 通过。
  - OpenAPI YAML 解析成功；37 个 path、0 个缺失内部引用。
  - `dart format`、`flutter analyze --fatal-infos`、`flutter test` 通过；11 个现有 Flutter 测试通过。
  - `flutter build apk --debug` 通过。
  - 额外 API 探针确认相同每日状态重放会改写 `recorded_at`；倒序暂停/恢复事件会使行状态与按时间线计算结果矛盾。
- 阻断发现：
  - 实际 App 未注入 `FastApiMedicationRepository`，Dashboard 默认仍使用三条硬编码数据和 `DemoMedicationRepository`，真实 API 路径不可达。
  - Flutter 使用设备本地日期，后端按 `Asia/Singapore` 服务端业务日期校验，跨时区/跨日时会错误拒绝今日状态。
  - 相同 daily-status 重试仍执行写入并改变审计时间，不满足重复请求幂等。
  - 事件日期没有单调性或重算约束，倒序事件导致当前状态与事件链/月统计不一致。
  - OpenAPI 的更新事件枚举和每日状态字段集合与 Pydantic 运行时模型不一致。
- 受影响对象：真实 App 用户无法使用服务端用药闭环；跨时区用户会误触历史日期拒绝；网络重试和倒序事件会破坏审计与统计一致性；生成客户端可能发送必然 422 的请求。
- 复验条件：接通已鉴权真实仓库并增加 App 入口测试；统一服务端业务日期；使状态重放无写入且处理并发；约束或重算事件时间线；统一 OpenAPI/Pydantic；在父依赖合入后基于最新 `main` 重跑完整门槛。

### PR #34 / Issue #15

- 状态：CHANGES_REQUESTED；同时受 PR #4、#32 依赖阻断。
- 审查时间：2026-08-27
- 审查账号：`healyops-blip`
- Head：`cfde6d43169d2c592dd3ead63731a54d1c741fa1`
- Base：`WilderNoTrack/issue-12-dashboard-foundation@2f13f03a88ccdc64e8100ecf476e483f10188bff`
- GitHub Review：[PR #34](https://github.com/healyops-blip/PMOS-ENclaire-app/pull/34)
- GitHub CI：无 Check 记录。
- 独立验证：
  - `ruff format --check`、`ruff check`、`pytest -W error` 通过；33 个后端测试通过。
  - 全新 SQLite 的 Alembic `upgrade head` 与 `check` 通过。
  - OpenAPI YAML 解析成功；37 个 path、0 个缺失内部引用。
  - `dart format`、`flutter analyze --fatal-infos`、`flutter test` 通过；13 个现有 Flutter 测试通过。
  - `flutter build apk --debug` 通过。
  - 额外 Repository 探针确认默认 Demo 实现在编辑中间记录后不重算被编辑记录及后一记录的周期长度。
- 阻断发现：
  - App 主导航未注入 `FastApiCycleRepository`，实际页面始终使用内存 Demo 数据，CRUD 不写入 SQLite。
  - 当前默认 Demo Repository 编辑后保留旧周期长度且不更新相邻记录，趋势结果错误。
  - 新增/编辑失败前已关闭表单，错误时丢失全部输入，仅有无重试动作的 Snackbar；写操作失败/重试状态不完整。
- 受影响对象：实际 App 用户的经期记录无法持久化；编辑后的趋势错误；重叠、并发或网络失败会造成重复录入成本和输入丢失。
- 复验条件：从 App 层注入已鉴权真实仓库；统一 Demo/Fake 领域行为；在表单内保留失败 draft 并允许重试；补主导航真实请求、相邻周期重算和 mutation 失败测试；父依赖合入后基于最新 `main` 重跑。

### PR #35 / Issue #16

- 状态：CHANGES_REQUESTED；同时受 PR #4、#32 依赖阻断。
- 审查时间：2026-08-27
- 审查账号：`healyops-blip`
- Head：`56539f5e7312ef3ef534ce5ccb3119701325cf93`
- Base：`WilderNoTrack/issue-12-dashboard-foundation@2f13f03a88ccdc64e8100ecf476e483f10188bff`
- GitHub Review：[PR #35](https://github.com/healyops-blip/PMOS-ENclaire-app/pull/35)
- GitHub CI：无 Check 记录。
- 独立验证：
  - `ruff format --check`、`ruff check`、`pytest -W error` 通过；32 个后端测试通过。
  - 全新 SQLite 的 Alembic `upgrade head` 与 `check` 通过。
  - OpenAPI YAML 解析成功；37 个 path、0 个缺失内部引用。
  - `dart format`、`flutter analyze --fatal-infos`、`flutter test` 通过；12 个 Flutter 测试通过。
  - `flutter build apk --debug` 通过。
- 阻断发现：
  - 生产入口未创建或注入 `ApiWeightRepository`，所有账号默认使用含四条固定记录的 `MemoryWeightRepository.seeded()`；真实 API 不可达，新用户空状态不成立。
  - 页面默认选中日期硬编码为 2026-08-27，日历范围硬编码为 2025–2027，后续日期会错误或不可选择。
  - 写入请求前已关闭输入 dialog，网络/鉴权/冲突失败会丢失输入且不能原值重试。
  - 已有记录时刷新失败仅在 Controller 保存错误，趋势页与 Dashboard 忽略错误并把旧缓存展示为当前值。
- 受影响对象：所有真实 App 用户的体重数据不会进入 SQLite；新用户看到伪造历史；错误日期可能被保存；同步失败时旧数据无 stale 标识。
- 复验条件：从 App 层注入已鉴权 API 仓库；使用可注入时钟和合理日期边界；保留失败表单并允许重试；展示 stale/error 状态；补真实入口、非 2026 日期、写失败和先成功后刷新失败测试；父依赖合入后基于最新 `main` 重跑。

## 修复与复验记录

> 上方 `CHANGES_REQUESTED` 条目是初次审查快照，用于保留问题与修复条件的审计记录；本表是修复后的最终执行状态。

| PR | 修复 Head | 复验结果 | 当前结论 |
|---|---|---|---|
| #4 | `93ea6f6` | Ruff；pytest 30；Alembic upgrade/check；OpenAPI；Flutter analyze/8 tests；APK | APPROVED；2026-08-27 已合入 `main` (`7f1d568`) |
| #32 | `7af72e9` | Ruff；pytest 35；Alembic；Flutter analyze/8 tests；APK；Core checks | APPROVED；2026-08-27 已合入 `main` (`6117373`) |
| #33 | `fc5b5e4` | Ruff；pytest 37；Alembic；Flutter analyze/13 tests；APK；Core checks | APPROVED；2026-08-27 已合入 `main` (`8fc4742`) |
| #36 | `d57f553` | Ruff；pytest 42；Alembic；OpenAPI；Flutter analyze/17 tests；APK；Core checks | APPROVED；2026-08-27 已合入 `main` (`067573c`) |
| #34 | `24c9184` | 组合 Ruff；pytest 47；Alembic 0012→0015；OpenAPI；Flutter analyze/24 tests；APK；Core checks | APPROVED；2026-08-27 已合入 `main` (`ca8791c`) |
| #35 | `ecdfda8` | 组合 Ruff；pytest 51；Alembic 0012→0015；OpenAPI；Flutter analyze/31 tests；APK；Core checks | APPROVED；2026-08-27 已合入 `main` (`1ff82ed`) |
| #37 | `07fd56d` | 组合 Ruff；pytest 56；Alembic 全新及 0015→0020；跨 UID/并发/幂等/逐修订清理；Flutter analyze/35 tests；APK；Core checks | APPROVED；2026-08-27 已合入 `main` (`6bf6d98`) |
| #41 | `cbf063a` | 组合 Ruff；pytest 63；Alembic 全新及 0020→0027；跨 UID/并发确认/来源归属/不可变快照/报告引用清理；Flutter analyze/40 tests；APK；required Core checks | APPROVED；2026-08-27 已合入 `main` (`3eca4fd`) |
| #39 | `e648878` | 组合 Ruff；pytest 69；Alembic 全新及 0020→0027；Dashboard 边界统计/局部失败/跨 UID/Session 撤销/缓存隔离/并发刷新/报告元数据；Flutter analyze/47 tests；APK；Android emulator 3 tests；required Core checks | APPROVED；2026-08-27 已合入 `main` (`974a2c4`) |
| #38 | `d51cc35` | 组合 Ruff；pytest 76；Alembic 全新及生产 0015→0027；七日边界/三态撤销/暂停恢复与替换/幂等/6 路并发/跨 UID/Session 撤销；Flutter analyze/57 tests；APK；Android emulator 6 tests；required Core checks | APPROVED；2026-08-27 已合入 `main` (`0480398`) |
| #40 | `e25e264` | Ruff；pytest 91；Alembic 全新及 0027→0028/downgrade/integrity；四类结构化 OCR/evidence/超时租约/过期结果/重试/软删除/跨 UID/Session；OpenAPI validator；Flutter analyze/63 tests；APK；Android emulator 6 OCR tests；生产 wheel/Worker smoke；required Core checks run `33125858667` | APPROVED；2026-08-27 已合入 `main` (`58c907d`) |
| #42 | `5cacb76` | Ruff；pytest 107；Alembic 全新、0028→0029、现网 0027→0029、downgrade/integrity；真实化验草稿映射/字段状态/失败不入库/删除源/跨 UID/Session 撤销/并发幂等/删项来源/确定性边界；OpenAPI 3.1 validator；Flutter analyze/64 tests；APK；Android 16 emulator 7 OCR tests；隔离 wheel smoke；required Core checks run `33127320926` | APPROVED；2026-08-27 已合入 `main` (`bd05a10`) |
| #43 | `2f6a499` | Ruff；pytest 107；Alembic 全新、现网 0027→0030、0029→0030、0030→0029→0030/check；真实影像/门诊字段契约、原始与确认值追踪、来源链路、字段状态、稳定字段错误、业务日期、删除源、跨 UID/Session 撤销、不同内容重放冲突、并发幂等、门诊不自动写用药；OpenAPI 3.1 validator；Flutter analyze/68 tests；APK；Android 16 emulator 11 临床/化验/OCR tests；隔离 wheel/Worker smoke；required Core checks run `33128787775` | APPROVED；2026-08-27 已合入 `main` (`74a048c`) |
| #44 | `3391e08` | Ruff；pytest -W error 120；Alembic 全新、现网 0027→0031、0031↔0030/check；真实医嘱草稿契约、逐药确认、P0 药名/剂量/频率、来源删除、跨 UID/Session 撤销、业务日期、原始/确认值追踪、字段状态、差异重放拒绝、确认/对账/执行并发幂等、六种调和状态、明确停药证据、事务中途失败整体回滚；OpenAPI 3.1 validator；Flutter analyze/72 tests；APK；Android 16/API 36 安装启动；隔离 wheel/Worker smoke；required Core checks run `33130429127` | APPROVED；2026-08-27 已合入 `main` (`ea68881`) |
| #45 | `1df6e27` | 已合入最新 `main` 与远端并修复 revision 异步串扰、旧水印泄漏、本地持久化失败恢复及重复启动；Ruff；pytest -W error 120；Alembic 全新升级至 0031/check；Flutter analyze/87 tests；APK；Android 16/API 36 模拟器安装、冷启动、前台与无致命崩溃；required Core checks run `33131716391` 成功 | CHANGES_REQUESTED；Issue #26 要求至少一台 Android 真机，当前仅有模拟器；四类材料成功、失败重试、重启持久化和新 revision 隔离的真机验收为 NOT_RUN，未合并 |
| #46 | `203e965` | 从旧集成基线重建到当前 `main`；修复当前四类 Schema/数据集/兜底不兼容、评测分母漏计失败、并发 UNIQUE 500、删除材料仍可兜底及迁移 head；Ruff；pytest -W error 129；Alembic 全新至 0032/check、0032↔0031；40 份离线评分器 Schema/P0/P1/P2 100%、critical 0（仅测试替身）；Flutter analyze/72 tests；APK；Android 16/API 36 安装启动；精确 head Core checks run `33133003147` 成功 | CHANGES_REQUESTED；真实 Qwen 40 样本、模拟器四类完整 E2E、至少一台 Android 真机四类 E2E 均为 NOT_RUN，未合并 |
| #47 | `db29e4d` | 基于最新 `main` 重建；修复影像/门诊/医嘱当前模型兼容、来源修订漏入 digest、自然月新鲜度边界、当前 UID 确认隔离、详情 API 与 Flutter 忽略真实快照、用药/事件/规则逐点来源；新增详情归属、来源变更新版本、旧快照不变、事务整体回滚等用例；Ruff；pytest -W error 125；Alembic 全新至 0031/check；Flutter analyze/74 tests；APK；Android 16/API 36 安装及冷启动；精确 head Core checks run `33134413819` 成功 | APPROVED；2026-08-27 已合入 `main` (`3fb5f85`) |
| #48 | `4367c3f` | 隔离组合当前 `main`、修复后 #26 与 #48；修复 #28 详情契约冲突、Dashboard 编译失败、更新摘要来源签名、异步详情后的滚动恢复、本地认证读取失败隔离；Ruff；pytest -W error 126；跨 UID 报告/文件、冻结快照、文件不可用回退；Alembic 全新至 0031/check；Flutter analyze/95 tests；小屏 1/2/3+ 点、历史折叠、任意点追溯、手工/医院来源、水印与失败回退；APK；Android 16/API 36 安装冷启动；精确 head Core checks run `33135601387` 成功 | CHANGES_REQUESTED；#26/PR #45 尚未合入；常规/小屏 Android 模拟器完整三层 E2E 与至少一台 Android 真机黄金路径均为 NOT_RUN，未合并 |
| #49 | `fa4612a` | 隔离组合当前 `main`、修复后 #26/#48 与 #49，并以保留原 PR head 祖先关系的非强推方式更新分支；移除旧客户端 PDF 生成器与直接 `pdf` 依赖；实现不可变快照服务端 PDF、鉴权下载、按账号隔离私有缓存，以及 logout/401/恢复拒绝/账号切换全量清理和会话变化时在途写入失效；修复安全存储清理失败后仍撤销 bearer/清除 PDF 且允许重试；Ruff；pytest 134；Alembic 全新至 0032/check、0031→0032→0031→0032；OpenAPI 9 tests；Flutter analyze/107 tests；APK；Android 16/API 36 安装冷启动；精确 head Core checks run `33140414991` 成功 | CHANGES_REQUESTED；依赖 #29/PR #48 与 #26/PR #45 尚未合入；模拟器生成/轮询/鉴权下载/保存/分享/打印及失败重试/取消完整 E2E、至少一台 Android 真机完整 E2E 均为 NOT_RUN，未合并 |

最终合并规则：每个堆叠 PR 在父 PR 合入后改为直接面向 `main`，同步最新 `main`，重新获得 GitHub Approval 和 Core checks 成功后才合并。

## 生产部署记录

- 部署时间：2026-08-27（America/Los_Angeles）。
- 生产 commit：`main@048039836e608fd4207dda094c5e00f225268810`。
- 上一 release：`/opt/pomi/releases/1ff82edfc3ad3ca04e95569bb2597796f93b9d8d`，保留用于回滚。
- 当前 release：`/opt/pomi/releases/048039836e608fd4207dda094c5e00f225268810`。
- 切换前备份：`/var/backups/pomi/pomi-20260827T225509Z.sqlite3`（SHA-256 sidecar，权限 `0600 pomi:pomi`）；Alembic 生产库从 `20260827_0015` 升级到 `20260827_0027 (head)`。
- 新材料存储：`POMI_STORAGE_ROOT=/var/lib/pomi/storage`，目录权限 `0700 pomi:pomi`；原环境文件备份为 `/etc/pomi/pomi.env.before-0480398`。
- 验证：SQLite `integrity_check=ok`；`pomi-api.service=active`；公网 `/health/live` 和 `/health/ready` 成功。
- 鉴权冒烟：注册 201、登录 200、`/api/auth/me` 200、退出 204、退出后 Dashboard 401。
- 业务冒烟：患者画像、用药、经期、体重、Dashboard、材料列表、最近患者自述均返回 200；生产业务日期 `2026-08-28` 下第 7 个自然日 `2026-08-22` 补录与历史查询返回 200，`editable=true` 且月统计即时更新。
- 暴露面：生产 `/docs` 与 `/openapi.json` 继续返回 404。
