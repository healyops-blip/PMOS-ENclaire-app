# Issue #30：私有报告 PDF 生成与 Android 交付

## 不可变数据边界

PDF Worker 仅加载 `report_snapshot.id` 指向的 `snapshot_json`，并在渲染前重新计算
SHA-256 与任务冻结的 `snapshot_hash` 比较。渲染期间不查询患者画像、用药、化验、经期、
体重、OCR 或认证表，因此任务入队后新增或修改业务数据不会进入该 PDF。若快照缺失、状态
不是 `succeeded` 或哈希不一致，任务安全失败，不使用当前业务数据补齐。

PDF 不读取 #26 本地认证演示状态，不包含医院认证水印、交易哈希、签名或公章。页面固定
显示“模拟数据，仅供演示”和患者自述/非诊断免责声明。

## 数据模型、幂等与恢复

`report_file` 保存 PDF 元数据和任务状态；文件本体位于 `POMI_STORAGE_ROOT/report-pdfs/`
私有目录。数据库只保存相对路径。任务键为：

```text
sha256(report_id + NUL + snapshot_hash + NUL + template_version)
```

相同组合只有一行。`queued` 或租约已过期的 `processing` 行可被 Worker 原子领取；渲染是
确定性的，Worker 崩溃后可安全重做并通过临时文件 + `os.replace` 原子落盘。成功行不会被
重复领取。失败行仅在用户再次 `POST` 后回到 `queued`，不影响 App 报告和已有成功文件。

部署必须同时启用 `pomi-report-pdf-worker.service`。中文字体 WenQuanYi Micro Hei 与许可证
随 Python wheel 管理，服务器不需要安装系统字体。

## 鉴权 API

所有请求必须携带当前 Bearer Session；非所属 UID 统一看不到报告或 PDF。

```http
POST /api/reports/{report_id}/pdf
Authorization: Bearer <session>
Idempotency-Key: <8..128 chars>

GET /api/reports/{report_id}/pdf
Authorization: Bearer <session>

GET /api/reports/{report_id}/pdf/file
Authorization: Bearer <session>
```

POST/状态响应 `data`：

| 字段 | 含义 |
| --- | --- |
| `report_id` / `file_id` | 报告和私有文件任务标识 |
| `generation_status` | `queued` / `processing` / `succeeded` / `failed` |
| `template_version` | 服务端静态模板版本 |
| `attempt_count` | Worker 领取次数（含恢复执行） |
| `file_name` / `mime_type` | 成功后为下载文件名 / `application/pdf` |
| `file_size_bytes` / `file_hash` | 成功文件长度与 SHA-256 |
| `generated_at` | 成功落盘时间 |
| `failure_reason` | 可安全展示的失败原因，不含医疗正文 |
| `download_url` | 始终为 `null`；客户端固定调用鉴权文件接口 |

文件响应使用 `Cache-Control: private, no-store`，不返回存储路径、静态目录 URL、二维码或
可转发链接。日志只记录任务/报告标识和状态，不记录快照正文、Session 或凭证。

## Flutter 行为与缓存

客户端创建任务后短轮询状态；离开页面即停止轮询。成功后把鉴权响应写入应用临时缓存，
先校验响应是 PDF，再允许用户主动调用 Android 系统分享面板或打印预览。网络、下载、
分享或打印失败仅显示提示并允许重试，不修改服务端成功文件或 App 内报告。

缓存文件属于临时副本：Repository 启动下载前清理超过 24 小时的旧 PDF，并限制最多保留
最近 4 份；新下载采用原子临时文件重命名。退出账户时可调用显式清理。用户通过系统面板
另存的副本不属于应用缓存清理范围。
实际 App 在退出登录和切换 UID 时清空该私有临时缓存；清理异常不得阻止 Session
从安全存储移除或返回登录页。

## 自动化与设备验收

- 后端覆盖模型/迁移/Repository、租约恢复、失败重试、UID 隔离、固定快照、稳定哈希、
  中文字体、分页、来源附录、不可比原因和鉴权下载。
- Flutter 覆盖 DTO/轮询、鉴权下载、缓存清理、失败重试及分享/打印入口。
- 模拟器和真机记录见 `docs/android-report-pdf-acceptance.md`。未实际执行的项目必须标记
  `NOT_RUN`，不得把自动化测试冒充真机结果。
