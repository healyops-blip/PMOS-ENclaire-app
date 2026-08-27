# Pomi 后端接口文档

本文档专门说明已实现的账号与 Session 接口。患者画像、日常记录、材料、OCR、对账和报告接口见 [`frontend-backend-integration.md`](frontend-backend-integration.md)，机器可读定义以 [`../contracts/openapi/pomi-api-v1.yaml`](../contracts/openapi/pomi-api-v1.yaml) 为准。区块链不属于 P0 后端范围。

## 1. 公共约定

### 1.1 服务地址

| 环境 | Base URL |
| --- | --- |
| 线上服务器 | `https://api.healy1012-ops.top` |
| 本地开发 | `http://127.0.0.1:8000` |

除 `204 No Content` 外，接口请求和响应均使用 JSON：

```http
Content-Type: application/json
```

### 1.2 认证方式

登录成功后，后端返回一次性明文 `session_id`。需要登录的接口必须携带：

```http
Authorization: Bearer <session_id>
```

说明：

- `session_id` 是不透明的随机凭据，客户端不得解析或自行生成。
- 服务端只保存 `session_id` 的哈希，不保存明文。
- 默认有效期为 7 天，实际过期时间以登录响应的 `expires_at` 为准。
- 客户端应把 `session_id` 存入系统安全存储，不得写入日志、埋点或普通明文缓存。
- 收到认证接口的 `401` 后，客户端应清除本地 Session 并引导用户重新登录。
- 客户端传入的 `uid` 不具有鉴权作用；当前用户身份只由有效 Session 决定。

### 1.3 时间格式

所有时间使用 ISO 8601 格式。示例：

```text
2026-09-03T04:00:00+00:00
```

### 1.4 通用错误结构

认证模块的业务错误和参数错误使用统一结构：

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid fields."
  }
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `error.code` | string | 稳定错误码，客户端应优先根据该字段分支处理 |
| `error.message` | string | 面向开发者的安全提示，不包含密码或账号是否存在等敏感信息 |

## 2. 接口总览

| 方法 | 路径 | 是否认证 | 成功状态 | 用途 |
| --- | --- | --- | --- | --- |
| `GET` | `/health/live` | 否 | `200` | 判断 FastAPI 进程是否存活 |
| `GET` | `/health/ready` | 否 | `200` | 判断 FastAPI 和数据库是否可用 |
| `POST` | `/api/auth/register` | 否 | `201` | 注册新账号，真实写入数据库 |
| `POST` | `/api/auth/login` | 否 | `200` | 使用账号名和密码登录并创建 Session |
| `GET` | `/api/auth/me` | 是 | `200` | 获取当前 Session 对应的账号信息 |
| `POST` | `/api/auth/logout` | 是 | `204` | 撤销当前 Session |

## 3. 公共数据结构

### 3.1 AccountResponse

```json
{
  "uid": "ee7abf29-b21f-4f52-865a-ecf4b50ab45c",
  "account_name": "new-user",
  "account_type": "user",
  "onboarding_completed": false,
  "status": "active",
  "phone_number": "+8613812345678",
  "phone_verified": false
}
```

| 字段 | 类型 | 是否可空 | 说明 |
| --- | --- | --- | --- |
| `uid` | string | 否 | 对外公开的账号唯一标识，UUID 格式；不要使用数据库内部自增 ID |
| `account_name` | string | 否 | 登录账号名，后端会去除首尾空格并转成小写 |
| `account_type` | string | 否 | 当前可能为 `user` 或 `admin` |
| `onboarding_completed` | boolean | 否 | 是否已经完成首次进入流程；前端据此决定进入引导页还是 Dashboard |
| `status` | string | 否 | 当前可能为 `active`、`disabled` 或 `locked` |
| `phone_number` | string | 是 | 注册时填写的手机号；当前未接入短信验证服务 |
| `phone_verified` | boolean | 否 | 手机号是否已验证；当前注册流程返回 `false` |

## 4. 健康检查

### 4.1 进程存活检查

```http
GET /health/live
```

该接口只验证 FastAPI 进程能够响应，不访问数据库。主要供 systemd、Nginx 或监控系统判断进程是否存活。

成功响应：`200 OK`

```json
{
  "status": "ok"
}
```

### 4.2 服务就绪检查

```http
GET /health/ready
```

该接口会执行一次轻量数据库查询。只有 FastAPI 和 SQLite 均可用时才返回成功，部署完成后的检查应优先使用此接口。

成功响应：`200 OK`

```json
{
  "status": "ok"
}
```

线上检查示例：

```bash
curl --fail https://api.healy1012-ops.top/health/ready
```

## 5. 用户注册

```http
POST /api/auth/register
```

注册会创建真实数据库账号，但不会自动登录，也不会返回 `session_id`。注册成功后，客户端需要继续调用登录接口。

### 5.1 请求体

```json
{
  "account_name": "new-user",
  "password": "StrongPass123",
  "phone_number": "+8613812345678"
}
```

| 字段 | 类型 | 必填 | 规则 |
| --- | --- | --- | --- |
| `account_name` | string | 是 | 3～64 个字符；首字符必须是小写字母或数字；其余可使用小写字母、数字、`.`、`_`、`-`；后端会去除首尾空格并转成小写 |
| `password` | string | 是 | 8～128 个字符；至少包含一个字母和一个数字 |
| `phone_number` | string | 否 | 7～20 位数字，可选 `+` 前缀；后端会移除空格和连字符；当前不会发送短信验证码 |

请求体不允许额外字段。例如客户端自行传入 `role`、`account_type` 或 `onboarding_completed` 会返回 `422`，避免普通用户注册时提升权限或绕过引导。

### 5.2 成功响应

状态：`201 Created`

响应体为 [AccountResponse](#31-accountresponse)。新注册账号默认值：

- `account_type = "user"`
- `onboarding_completed = false`
- `status = "active"`
- `phone_verified = false`

### 5.3 错误响应

| HTTP 状态 | 错误码 | 场景 |
| --- | --- | --- |
| `409` | `ACCOUNT_NAME_TAKEN` | 账号名已经存在；响应不会泄露其他账号信息 |
| `422` | `VALIDATION_ERROR` | 字段缺失、格式错误、密码强度不足或出现未定义字段 |
| `429` | `AUTH_RATE_LIMITED` | 同一来源短时间内注册请求过多；响应包含 `Retry-After` Header |

调用示例：

```bash
curl --request POST 'https://api.healy1012-ops.top/api/auth/register' \
  --header 'Content-Type: application/json' \
  --data '{
    "account_name": "new-user",
    "password": "StrongPass123",
    "phone_number": "+8613812345678"
  }'
```

## 6. 密码登录

```http
POST /api/auth/login
```

账号名和密码验证成功后创建新的 Session。每次成功登录都会返回新的 `session_id`，旧 Session 在未过期或未撤销时仍然有效。

### 6.1 请求体

```json
{
  "account_name": "new-user",
  "password": "StrongPass123",
  "client_platform": "android",
  "device_name": "Pixel Emulator"
}
```

| 字段 | 类型 | 必填 | 规则与用途 |
| --- | --- | --- | --- |
| `account_name` | string | 是 | 3～64 个字符；后端会去除首尾空格并转成小写 |
| `password` | string | 是 | 1～128 个字符；仅用于验证，不会出现在响应或日志中 |
| `client_platform` | string | 否 | 最长 32 个字符；Android 客户端建议固定传 `android` |
| `device_name` | string | 否 | 最长 128 个字符；用于标识本次登录设备，例如手机型号或模拟器名称 |

### 6.2 成功响应

状态：`200 OK`

```json
{
  "session_id": "一次性返回的不透明随机凭据",
  "token_type": "Bearer",
  "expires_at": "2026-09-03T04:00:00+00:00",
  "account": {
    "uid": "ee7abf29-b21f-4f52-865a-ecf4b50ab45c",
    "account_name": "new-user",
    "account_type": "user",
    "onboarding_completed": false,
    "status": "active",
    "phone_number": "+8613812345678",
    "phone_verified": false
  }
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `session_id` | string | 后续 Bearer 认证凭据；仅在登录响应中以明文返回 |
| `token_type` | string | 固定为 `Bearer` |
| `expires_at` | string | Session 绝对过期时间 |
| `account` | object | 当前登录账号的 AccountResponse |

### 6.3 错误响应

| HTTP 状态 | 错误码 | 场景 |
| --- | --- | --- |
| `401` | `INVALID_CREDENTIALS` | 账号不存在、密码错误或账号不可登录；三种情况使用相同响应，避免探测账号是否存在 |
| `422` | `VALIDATION_ERROR` | 请求字段缺失、长度不合法或包含额外字段 |
| `429` | `AUTH_RATE_LIMITED` | 同一来源短时间内登录请求过多；响应包含 `Retry-After` Header |

调用示例：

```bash
curl --request POST 'https://api.healy1012-ops.top/api/auth/login' \
  --header 'Content-Type: application/json' \
  --data '{
    "account_name": "new-user",
    "password": "StrongPass123",
    "client_platform": "android",
    "device_name": "Pixel Emulator"
  }'
```

## 7. 获取当前账号

```http
GET /api/auth/me
Authorization: Bearer <session_id>
```

后端根据 Bearer Session 确定当前账号。即使请求中附加其他 `uid`，也不会改变当前身份。

成功响应：`200 OK`

响应体为 [AccountResponse](#31-accountresponse)。

错误响应：

| HTTP 状态 | 错误码 | 场景 |
| --- | --- | --- |
| `401` | `AUTHENTICATION_REQUIRED` | 未提供 Session、Session 无效、已撤销、已过期，或账号状态不允许登录 |

`401` 响应同时包含：

```http
WWW-Authenticate: Bearer
```

调用示例：

```bash
curl 'https://api.healy1012-ops.top/api/auth/me' \
  --header 'Authorization: Bearer <session_id>'
```

## 8. 退出登录

```http
POST /api/auth/logout
Authorization: Bearer <session_id>
```

退出会撤销当前 Session。接口是幂等的：同一个 `session_id` 重复退出仍返回成功，不会产生服务端异常。

成功响应：`204 No Content`

`204` 没有响应体，客户端不要尝试解析 JSON。退出成功后，该 Session 再访问 `/api/auth/me` 会返回 `401`。

错误响应：

| HTTP 状态 | 错误码 | 场景 |
| --- | --- | --- |
| `401` | `AUTHENTICATION_REQUIRED` | 请求没有提供 Bearer Session |

调用示例：

```bash
curl --request POST 'https://api.healy1012-ops.top/api/auth/logout' \
  --header 'Authorization: Bearer <session_id>'
```

## 9. 错误码汇总

| HTTP 状态 | 错误码 | 客户端建议处理 |
| --- | --- | --- |
| `401` | `INVALID_CREDENTIALS` | 登录页提示“账号或密码错误”，不要区分账号不存在和密码错误 |
| `401` | `AUTHENTICATION_REQUIRED` | 清除本地 Session，返回登录页 |
| `409` | `ACCOUNT_NAME_TAKEN` | 注册页提示更换账号名 |
| `422` | `VALIDATION_ERROR` | 根据客户端本地校验提示用户检查输入；不要直接展示服务端英文信息 |
| `429` | `AUTH_RATE_LIMITED` | 禁用提交按钮并按照 `Retry-After` 秒数倒计时 |

## 10. Flutter 推荐联调流程

### 10.1 新用户

1. 调用 `/api/auth/register` 创建账号。
2. 注册成功后调用 `/api/auth/login`。
3. 安全保存 `session_id` 和 `expires_at`。
4. 根据 `account.onboarding_completed` 进入首次引导页或 Dashboard。
5. App 冷启动时调用 `/api/auth/me` 恢复登录状态。

### 10.2 老用户

1. 调用 `/api/auth/login`。
2. 安全保存 `session_id` 和 `expires_at`。
3. `onboarding_completed = true` 时进入 Dashboard。

### 10.3 退出

1. 携带当前 Session 调用 `/api/auth/logout`。
2. 无论本地是否重复触发退出，都只执行一次页面跳转。
3. 收到 `204` 后删除本地 Session，返回登录页。
4. 如果网络不可用，客户端可以先清除本地 Session；恢复联网后无需依赖退出响应才能显示登录页。

## 11. 非 HTTP 管理能力

以下功能仅允许在服务器本地执行，不是 App 接口：

```bash
pomi-admin seed-accounts
pomi-admin reset-password ACCOUNT_NAME
```

- `seed-accounts` 幂等创建初次进入用户和老用户。
- `reset-password` 修改密码后撤销该账号全部有效 Session。
- 当前不提供短信验证码、客户端自助找回密码、万能密码或公开管理员接口。

## 12. OpenAPI 说明

本地开发环境可以访问：

- Swagger UI：`/docs`
- ReDoc：`/redoc`
- OpenAPI JSON：`/openapi.json`

生产环境会关闭以上三个入口。健康检查接口也不会写入 OpenAPI Schema，因此前端联调以本文档和自动化测试为准。
