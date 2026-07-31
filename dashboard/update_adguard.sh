#!/bin/bash
set -euo pipefail

# 获取脚本所在的真实绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# 切换到 docker-compose.yaml 所在目录
cd "$SCRIPT_DIR" || exit 1

SERVICE_NAME="adguardhome"
IMAGE_NAME="adguard/adguardhome"

# 1. 获取当前的镜像 ID
OLD_ID=$(docker images -q "$IMAGE_NAME:latest")

# 2. 拉取最新镜像
echo "正在检查 AdGuard Home 镜像更新..."
docker compose pull "$SERVICE_NAME"

# 3. 获取拉取后的新镜像 ID
NEW_ID=$(docker images -q "$IMAGE_NAME:latest")

# 4. 对比镜像 ID
if [ "$OLD_ID" = "$NEW_ID" ] && [ -n "$OLD_ID" ]; then
    echo "【提示】AdGuard Home 当前已是最新版本，无需重启。"
    exit 0
fi

echo "【检测到更新】正在重新部署 AdGuard Home..."

# 5. 使用 Docker Compose 重建并启动容器
docker compose up -d "$SERVICE_NAME"

# 6. 清理无用镜像
docker image prune -f

echo "【成功】AdGuard Home 新版本已成功运行！"
