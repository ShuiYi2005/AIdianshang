# PLAYBOOK

## 启动

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```

## 查看状态

```powershell
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml ps
```

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

## 修改服务

1. 先查 `specs/` 和 `.spec/`。
2. 业务代码只改 `services/`。
3. 部署参数只改 `deployment/`。
4. 修改后重新运行验证。
