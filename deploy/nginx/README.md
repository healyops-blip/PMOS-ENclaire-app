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
certificate already exists before enabling this site. If it does not, install
the HTTP bootstrap site first, obtain the certificate through the isolated ACME
webroot, then replace it with the HTTPS site. This does not stop other Nginx
sites:

```bash
sudo install -d -o www-data -g www-data -m 0755 /var/www/certbot
sudo cp /opt/pomi/current/deploy/nginx/pomi-api-http.conf /etc/nginx/sites-available/pomi-api.conf
sudo nginx -t
sudo systemctl reload nginx
sudo certbot certonly --webroot -w /var/www/certbot -d api.healy1012-ops.top
sudo cp /opt/pomi/current/deploy/nginx/pomi-api.conf /etc/nginx/sites-available/pomi-api.conf
sudo nginx -t
sudo systemctl reload nginx
```

The HSTS header applies only to `api.healy1012-ops.top`; it deliberately omits
`includeSubDomains` and `preload`. Enable the configuration only after HTTPS is
stable and a rollback plan exists. FastAPI must never listen on a public
interface in production.
