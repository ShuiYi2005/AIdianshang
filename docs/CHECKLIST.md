# CHECKLIST

## 修改前

- [ ] 是否已阅读 `.spec/README.md`
- [ ] 是否已确认要修改的文件属于允许范围
- [ ] 是否没有把业务逻辑写进 `deployment/`、`workflows/` 或平台目录

## 修改后

- [ ] `docker compose -f deployment/docker-compose.yml config` 通过
- [ ] `docker compose -f deployment/docker-compose.yml up -d` 可启动
- [ ] Dify Web 可访问
- [ ] Dify API 可访问
- [ ] `db-simulator` 健康检查通过
- [ ] worker 使用 Redis broker
