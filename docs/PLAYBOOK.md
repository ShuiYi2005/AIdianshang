# PLAYBOOK

## 启动

```powershell
docker compose -f deployment/docker-compose.yml up -d
```

## 查看状态

```powershell
docker compose -f deployment/docker-compose.yml ps
```

## 验证

```powershell
Invoke-RestMethod http://localhost:8001/health
Invoke-WebRequest http://localhost:8080 -UseBasicParsing
Invoke-WebRequest http://localhost:5001/console/api/setup -UseBasicParsing
Invoke-WebRequest http://localhost:5678 -UseBasicParsing
```

## 修改服务

1. 先查 `specs/` 和 `.spec/`。
2. 业务代码只改 `services/`。
3. 部署参数只改 `deployment/`。
4. 修改后重新运行验证。
