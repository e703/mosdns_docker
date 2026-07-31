# README

整合实现 [vector + loki 实现 mosdns 数据看板](https://icyleaf.com/2023/08/using-vector-transform-mosdns-logging-to-grafana-via-loki/#prometheus)
- 数据已持久化, 无需重复配置.
- 效果与 blog 中一致.

LOG
- 2024-05-2: 初版, 还未尽力非常长时间测试, 有 bug 请评论或提 issue.

## 使用前

更新 prometheus/prometheus.yml

```yaml
    static_configs:
      - targets:
          - 192.168.1.1:8338 # mosdns 监听地址, 更新为 host ip 地址
```

dashboard/mosdns/config/dns.yaml 的 addr 为本地运营商 dns 地址

```yaml
  # local dns
  - tag: local
    type: forward
    args:
      concurrent: 1
      upstreams:
        - addr: "udp://192.168.1.1:53" # 更新为本地 dns 地址, 一般是 网关地址
```

dashboard/mosdns/config/dat_exec.yaml 的 preset 为本地公网 ip

```yaml
  # 附加 ecs cn 信息
  - tag: ecs_cn
    type: "ecs_handler"
    args:
      forward: false # 是否转发来自下游的 ecs
      preset: 202.120.2.100 # 发送预设 ecs（改为本地公网 IP，同城市同运营商）
      send: true # 是否发送 ecs
      mask4: 24 # ipv4 掩码。默认 24
      mask6: 48 # ipv6 掩码。默认 48
```

## 首次部署（新机器）

### 1. 生成 geo 数据

mosdns 的分流依赖 geoip/geosite 数据文件。首次部署需运行 `update_geo_dat.sh` 生成：

```bash
cd dashboard
# 检查依赖（curl + v2dat）
./update_geo_dat.sh --check
# 生成数据到 mosdns/config/dat/
./update_geo_dat.sh
```

v2dat 工具的获取（三选一）：
- **PATH 安装**（推荐）：`sudo go install github.com/urlesistiana/v2dat@latest`
- **仓库内置**：把 v2dat 二进制放到 `dashboard/` 目录（脚本会自动发现）
- **环境变量**：`export V2DAT=/path/to/v2dat`

脚本会自动按 `环境变量 V2DAT → PATH → 仓库内 ./v2dat` 的顺序查找。

### 2. 启动

```bash
docker compose up -d --build
```

## 数据更新

geo 数据建议定期更新（新域名、新广告规则等）。更新流程：

```bash
cd dashboard
./update_geo_dat.sh              # 下载并解包最新数据
docker compose restart mosdns    # 重启 mosdns 使新数据生效（无需重建镜像）
```

可加入 crontab 定时执行（每天凌晨 3 点更新数据并重启 mosdns）：

```cron
# 更新 geo 数据并重启 mosdns 使其生效
0 3 * * * /path/to/dashboard/update_geo_dat.sh >> /var/log/mosdns_dat_update.log 2>&1
15 3 * * * docker compose -f /path/to/dashboard/docker-compose.yaml restart mosdns >> /var/log/mosdns_dat_update.log 2>&1
```

安装到 crontab：
```bash
crontab -e
# 粘贴上面的配置，把 /path/to/dashboard 改为实际路径
```

> 注：更新脚本只刷新 `mosdns/config/dat/`（mosdns 通过挂载直接读取），重启 mosdns 即生效，
> 无需 `docker compose build`。

## 使用

```bash
docker compose up -d
```

启动后访问 `ip:3000`

如 [vector + loki 实现 mosdns 数据看板#grafana](https://icyleaf.com/2023/08/using-vector-transform-mosdns-logging-to-grafana-via-loki/#grafana) 章节配置.
- 添加 prometheus 和 loki 的数据源后,导入 mosdns v5 看板.

## 调试

ip:9090 为 prometheus 端口