# POMI Smoke Web 服务器部署说明

本文供服务器 Agent 执行。目标是把 POMI Flutter Web Smoke 演示站部署到独立域名，并使用 Nginx 提供 HTTPS 静态服务。

## 1. 部署性质

- 类型：纯静态 Flutter Web 网站。
- 运行模式：`POMI_SMOKE_MODE=true`。
- 不连接真实 API、数据库或 OCR 服务。
- 不需要 Node.js、Python 运行时、Docker 或 systemd 服务。
- 登录状态可能保存在浏览器站点存储中；健康数据为浏览器内存模拟数据。
- 建议使用独立子域名，例如 `pomi.example.com`，不要部署在 URL 子目录下。

Smoke 演示账号：

```text
账号：smoke
密码：Pomi1234
```

## 2. 部署前需要提供的变量

服务器 Agent 在执行前必须设置以下变量：

```bash
DOMAIN="pomi.example.com"
PACKAGE="/tmp/pomi-web-0.1.0-deploy.zip"
EXPECTED_SHA256="由发布方提供的 SHA-256"
SITE_ROOT="/var/www/pomi-preview"
RELEASE_ID="$(date -u +%Y%m%d%H%M%S)"
RELEASE_DIR="$SITE_ROOT/releases/$RELEASE_ID"
```

将 `DOMAIN` 替换为真实域名。域名的 A/AAAA 记录必须已经指向当前服务器。

## 3. 服务器前置条件

以下命令以 Ubuntu/Debian 为例：

```bash
sudo apt-get update
sudo apt-get install -y nginx unzip rsync ca-certificates
```

如果服务器已经使用 Nginx、Caddy、宝塔或其他面板，不要覆盖现有全局配置；只新增当前域名的站点配置。

确认 80、443 端口可以从公网访问：

```bash
sudo ss -lntp | grep -E ':(80|443)\b' || true
```

## 4. 校验发布包

收到 ZIP 后先校验哈希，不匹配时必须停止部署：

```bash
test -f "$PACKAGE"
echo "$EXPECTED_SHA256  $PACKAGE" | sha256sum --check --strict
```

不要把 ZIP 直接解压到正在服务的目录。

## 5. 解压到新版本目录

正式部署包的静态网站位于 ZIP 内的 `application/release/`：

```bash
WORK_DIR="$(mktemp -d)"
unzip -q "$PACKAGE" -d "$WORK_DIR"

test -f "$WORK_DIR/application/release/index.html"
test -f "$WORK_DIR/application/release/app.html"
test -f "$WORK_DIR/application/release/main.dart.js"
test -f "$WORK_DIR/application/release/flutter_bootstrap.js"

sudo install -d -m 0755 "$SITE_ROOT/releases" "$RELEASE_DIR"
sudo rsync -a --delete "$WORK_DIR/application/release/" "$RELEASE_DIR/"
sudo chown -R root:root "$RELEASE_DIR"
sudo find "$RELEASE_DIR" -type d -exec chmod 0755 {} +
sudo find "$RELEASE_DIR" -type f -exec chmod 0644 {} +
```

检查发布目录中不得存在私钥、环境文件和数据库：

```bash
if find "$RELEASE_DIR" -type f \
  \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' \
     -o -name '*.p12' -o -name '*.pfx' -o -name '*.db' -o -name '*.sqlite*' \) \
  | grep -q .; then
  echo "发现禁止发布的敏感文件，停止部署。" >&2
  exit 1
fi
```

## 6. 建立当前版本软链接

首次部署：

```bash
sudo ln -sfn "$RELEASE_DIR" "$SITE_ROOT/current"
```

后续发布也始终先创建新的 `RELEASE_DIR`，验证后再原子切换 `current`，不要原地覆盖旧文件。

## 7. Nginx 配置

创建 `/etc/nginx/sites-available/pomi-preview.conf`：

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name pomi.example.com;

    root /var/www/pomi-preview/current;
    index index.html;
    charset utf-8;

    # Flutter Web 与应用内路由回退。
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 入口文件不能长期缓存，否则发布后可能继续加载旧版本。
    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        try_files $uri =404;
    }

    location = /app.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        try_files $uri =404;
    }

    location = /flutter_bootstrap.js {
        add_header Cache-Control "no-cache, must-revalidate" always;
        try_files $uri =404;
    }

    location = /flutter_service_worker.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        try_files $uri =404;
    }

    location = /main.dart.js {
        add_header Cache-Control "no-cache, must-revalidate" always;
        try_files $uri =404;
    }

    location ~* \.wasm$ {
        default_type application/wasm;
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
        try_files $uri =404;
    }

    location ~* \.(?:png|jpg|jpeg|gif|svg|ico|ttf|otf|woff|woff2)$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
        try_files $uri =404;
    }

    # 禁止通过 Web 读取隐藏的发布元数据。
    location ~ /\. {
        deny all;
    }

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types application/javascript application/json application/wasm image/svg+xml text/css;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-Frame-Options SAMEORIGIN always;
}
```

必须把配置中的两个位置替换为真实值：

```text
server_name pomi.example.com;
root /var/www/pomi-preview/current;
```

启用配置：

```bash
sudo ln -sfn /etc/nginx/sites-available/pomi-preview.conf \
  /etc/nginx/sites-enabled/pomi-preview.conf
sudo nginx -t
sudo systemctl reload nginx
```

## 8. 配置 HTTPS

如果服务器使用 Certbot：

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d "$DOMAIN" --redirect
sudo nginx -t
sudo systemctl reload nginx
```

如果使用宝塔、1Panel、Caddy 或云厂商证书功能，请在对应面板中为同一域名申请证书并强制 HTTPS，不要重复运行 Certbot。

## 9. 上线健康检查

```bash
curl -fsS -o /dev/null -w 'index=%{http_code}\n' "https://$DOMAIN/"
curl -fsS -o /dev/null -w 'app=%{http_code}\n' "https://$DOMAIN/app.html"
curl -fsS -o /dev/null -w 'js=%{http_code}\n' "https://$DOMAIN/main.dart.js"
curl -fsS -o /dev/null -w 'wasm=%{http_code}\n' \
  "https://$DOMAIN/canvaskit/canvaskit.wasm"
```

四项都应返回 `200`。再检查 HTML：

```bash
curl -fsS "https://$DOMAIN/" | grep -q 'Pomi Mobile Preview'
curl -fsS "https://$DOMAIN/app.html" | grep -q 'flutter_bootstrap.js'
```

## 10. 浏览器 Smoke 验收

必须使用无痕窗口或清除该域名的站点数据后验收：

1. 打开 `https://$DOMAIN/`。
2. 应显示带手机外框的 POMI 展示站。
3. 登录页应预填 `smoke / Pomi1234`。
4. 勾选协议并登录。
5. 个人信息、周期和当前用药页面应保留完整流程，同时预填演示数据。
6. 连续点击“下一步”和“进入首页”应成功进入首页，不得出现 `current_step` 缺失。
7. 刷新首页、记录、追踪、用药和个人中心页面，确认无红屏。
8. “患者自述生成报告”不得触发 Flutter 红屏；如果发布方尚未交付该修复，停止将该版本标记为正式演示版。

## 11. 回滚

列出已有版本：

```bash
ls -la "$SITE_ROOT/releases"
readlink -f "$SITE_ROOT/current"
```

回滚到上一版本：

```bash
PREVIOUS_RELEASE="/var/www/pomi-preview/releases/上一版本目录"
test -f "$PREVIOUS_RELEASE/index.html"
sudo ln -sfn "$PREVIOUS_RELEASE" "$SITE_ROOT/current"
sudo nginx -t
sudo systemctl reload nginx
```

回滚后再次执行第 9、10 节检查。

## 12. 部署结果回报格式

服务器 Agent 完成后应回复：

```text
域名：
服务器 IP：
部署版本：
发布包 SHA-256：
实际发布目录：
HTTPS 证书状态：
Nginx 配置检查：
四项 HTTP 健康检查结果：
Smoke 全流程结果：
回滚版本：
```
