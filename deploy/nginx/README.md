# Nginx deployment

`pomi-api.conf` terminates TLS for `api.healy1012-ops.top` and proxies only to
FastAPI on `127.0.0.1:8010`. Port 8010 avoids the existing service on port 8000.
It also provides edge authentication throttling,
security headers, request-size limits, and bounded proxy timeouts.

Install and validate:

```bash
sudo cp deploy/nginx/pomi-api.conf /etc/nginx/sites-available/pomi-api.conf
sudo ln -s /etc/nginx/sites-available/pomi-api.conf /etc/nginx/sites-enabled/pomi-api.conf
sudo nginx -t
sudo systemctl reload nginx
```

The certificate paths expect a Let's Encrypt certificate. Confirm that the
certificate already exists before enabling this site. If it does not, obtain
one only after DNS points at the server; for a new server with Nginx not yet
serving traffic, `certbot certonly --standalone` can provision it before this
configuration is enabled:

```bash
sudo certbot certonly --standalone -d api.healy1012-ops.top
```

The HSTS header applies only to `api.healy1012-ops.top`; it deliberately omits
`includeSubDomains` and `preload`. Enable the configuration only after HTTPS is
stable and a rollback plan exists. FastAPI must never listen on a public
interface in production.
