# Gateway 一键部署指南

本指南介绍 `gatewaybushu.tar.gz` 一键部署压缩包的结构、部署流程以及常见运维操作，并比较通过 Nginx 代理提供下载与使用 AWS S3 托管安装资源的优缺点。

## 压缩包内容

解压 `gatewaybushu.tar.gz` 后的目录主要包含：

- `deploy.sh`：部署入口脚本，根据 `config.yaml` 选择性更新各服务。
- `config.yaml`：部署配置模板，设置配置文件目标目录以及服务开关。
- `config/`：各服务所需的 YAML 配置，运行时会复制到 `config_dest`。
- `alarmsrv/`、`apigateway/`、`hissrv/`、`netsrv/`：每个服务目录均包含镜像包 (`*.tar.gz`)、`load_image.sh`（加载镜像）和 `start.sh`（启动容器）。

## 部署前准备

- 操作系统：已安装 Docker (支持 aarch64/ARM) 和 Bash 的 Linux 主机或工控机。
- 运行依赖：
  - `python3`：`deploy.sh` 解析 YAML 配置时使用。
  - `redis-cli`：仅当 `apigateway` 启动脚本需要验证 Redis 连接时使用，可选安装。
- 磁盘空间：确保有足够空间存放镜像压缩包与解压后的镜像层。

## 快速部署流程

1. **解压压缩包**
   ```bash
   tar -xzvf gatewaybushu.tar.gz
   cd bushu
   ```
2. **编辑部署配置**
   - 打开 `config.yaml`，设置配置文件目标路径 `config_dest`。
   - 将需要更新的服务开关（如 `update_hissrv`）改为 `true`，其他保持 `false` 即可跳过。
3. **执行部署脚本**
   ```bash
   bash deploy.sh            # 使用默认 config.yaml
   bash deploy.sh my.yaml    # 或者传入自定义配置文件路径
   ```
4. **等待脚本完成**
   - 每个服务会依次执行 `load_image.sh` 和 `start.sh`。
   - `apigateway` 启动脚本会在本地健康检查通过后给出访问地址。
5. **验证服务状态**
   - 使用 `docker ps` 确认容器处于 `Up` 状态。
   - 根据具体服务访问健康检查或 Web UI。

## `config.yaml` 字段说明

| 字段 | 说明 | 示例 |
| --- | --- | --- |
| `config_dest` | 运行时配置文件的目标目录，`deploy.sh` 会将 `config/` 下的文件复制到该目录。 | `/extp/test/config` |
| `update_alarmsrv` | 是否加载并启动报警服务镜像。 | `true`/`false` |
| `update_apigateway` | 是否更新 API 网关服务。 | `true`/`false` |
| `update_hissrv` | 是否更新历史数据服务。 | `true`/`false` |
| `update_netsrv` | 是否更新现场网络服务。 | `true`/`false` |

> `deploy.sh` 会严格检查上述变量是否存在；缺失时会直接退出并提示错误。

## 服务目录结构

每个服务目录提供一致的操作体验：

- `load_image.sh`
  - 检查镜像压缩包是否存在。
  - 停止并删除同名容器与历史镜像。
  - 通过 `docker load` 导入镜像，并统一打上 `latest` 标签。
  - 清理悬空镜像层，避免磁盘冗余。
- `start.sh`
  - 再次校验 Docker 依赖。
  - 根据本地镜像情况优先使用 `latest` 标签。
  - 停止旧容器，使用 `--network=host`、`--restart=unless-stopped` 方式重新拉起。
  - 提供运行所需的卷挂载（日志、配置）和环境变量。
  - 自检通过后输出访问入口、健康检查、日志查看命令等。

如需自定义环境变量或挂载，可直接编辑对应服务目录中的 `start.sh` 后重新执行 `deploy.sh`。

## 常见运维操作

- **仅更新配置文件**：将新配置放入 `config/`，保持所有 `update_*` 为 `false`，执行 `deploy.sh` 只会刷新配置。
- **手工重启某个服务**：进入对应目录，直接运行 `bash start.sh` 即可。
- **重新打包一键部署包**：在 `bushu/` 所在目录执行 `tar -czvf gatewaybushu.tar.gz bushu`。
- **查看运行日志**：
  ```bash
  docker logs voltageems-apigateway
  docker logs voltageems-hissrv
  ```

## Nginx 代理下载 vs AWS S3

| 方案 | 优点 | 缺点 | 适用场景 |
| --- | --- | --- | --- |
| **Nginx 代理下载** | 自建服务器，可与现有内网认证集成；本地局域网下载速度快；支持自定义限速、白名单策略 | 需要自行维护服务器与证书；跨区域访问加速有限；需处理高并发时的缓存与容灾 | 企业内网、离线或半离线环境、需要精细权限控制的场景 |
| **AWS S3** | 高可靠性与弹性扩展；自带全球 CDN（配合 CloudFront）；生命周期管理与版本控制便捷；与 CI/CD、发布流程整合容易 | 依赖公网访问，网络波动时下载不稳定；按存储与流量计费，成本需监控；国内访问存在延迟或合规要求 | 公有云部署、全球分发、需要快速发布与回滚的项目 |

> 若目标环境在封闭网络或工业现场，推荐通过 Nginx 在本地或厂内机房提供镜像下载；面向多地区客户或需要大规模分发时，可使用 S3 + CloudFront，并通过 IAM/STS 控制访问权限。

## 故障排查建议

- `deploy.sh` 报错找不到配置：确认传入的 YAML 路径正确且键名拼写无误。
- `load_image.sh` 报 Docker 未安装：在目标主机安装 Docker，并确保当前用户具备运行权限。
- `start.sh` 健康检查失败：查看容器日志，检查所依赖的 Redis、数据库等外部服务是否就绪。
- 容器频繁重启：使用 `docker inspect <container>` 或 `docker logs` 获取详细错误信息，必要时调整 `start.sh` 的环境变量。

## 后续规划

- 将 `config.yaml` 参数化并引入校验工具（例如 `yq`）提高可维护性。
- 在 CI 中自动生成 `gatewaybushu.tar.gz` 并附带 SHA 校验值，提升发布可靠性。
- 根据现场需求添加一键回滚脚本（保存旧镜像并快速恢复）。

如需补充说明或进一步自动化脚本，可在本指南基础上扩展章节。
