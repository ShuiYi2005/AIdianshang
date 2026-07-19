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
# 轻量向量 RAG 验收

- [ ] `GET /api/rag/status` 显示模型缓存、Weaviate 和索引状态。
- [ ] 训练中心“知识库同步”可启动同步、显示进行中、成功或失败状态，并可重试。
- [ ] `POST /api/rag/search` 在索引成功后返回 `retrieval_mode=vector`、资料来源、版本与切片标识。
- [ ] Weaviate 或模型不可用时，`hybrid` 返回 `keyword_fallback`；`vector` 不伪装关键词结果。
