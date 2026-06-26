# Chat Media Upload Nginx Limit

Если на сервере в логах появляется `client intended to send too large body`, для Timeweb/Nginx нужен больший лимит:

```nginx
client_max_body_size 20M;
```

Пример ручного обновления конфигурации:

```bash
sudo nano /etc/nginx/nginx.conf
sudo nginx -t
sudo systemctl reload nginx
```

Менять сервер автоматически не нужно. Сначала обновите конфиг вручную и проверьте `nginx -t`.
