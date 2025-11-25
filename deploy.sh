#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/config.yaml}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "找不到配置文件: $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "需要 python3 来解析 YAML 配置" >&2
  exit 1
fi

# 使用 Python 解析简单的 key: value YAML 并导出为 shell 变量
eval "$(python3 - "$CONFIG_FILE" <<'PY'
import sys, shlex
config = {}
with open(sys.argv[1], encoding='utf-8') as f:
    for raw_line in f:
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip().lower()
        value = value.strip()
        if value.lower() in {"true", "false"}:
            value = value.lower()
        config[key] = value
for key, value in config.items():
    env_key = key.upper()
    print(f"{env_key}={shlex.quote(value)}")
PY
)"

: "${CONFIG_DEST:?请在配置文件中设置 config_dest}"
: "${LOG_DEST:?请在配置文件中设置 log_dest}"
: "${UPDATE_ALARMSRV:?请在配置文件中设置 update_alarmsrv}"
: "${UPDATE_APIGATEWAY:?请在配置文件中设置 update_apigateway}"
: "${UPDATE_HISSRV:?请在配置文件中设置 update_hissrv}"
: "${UPDATE_NETSRV:?请在配置文件中设置 update_netsrv}"

is_enabled() {
  local value="${1:-}"
  value="${value,,}"
  [[ "$value" == "true" || "$value" == "yes" || "$value" == "1" ]]
}

copy_config_files() {
  local source_dir="$SCRIPT_DIR/config"
  local target_dir="$CONFIG_DEST"

  mkdir -p "$target_dir"

  local source_real
  local target_real
  source_real=$(cd "$source_dir" && pwd)
  target_real=$(cd "$target_dir" && pwd)

  if [[ "$source_real" == "$target_real" ]]; then
    echo "配置目录 $source_real 与目标目录相同，跳过复制"
    return
  fi

  shopt -s nullglob
  for file in "$source_dir"/*; do
    if [[ -f "$file" ]]; then
      cp -f "$file" "$target_dir/"
      echo "已复制 $(basename "$file") 到 $target_dir"
    fi
  done
  shopt -u nullglob
}

run_service() {
  local service_name="$1"
  local update_flag="$2"
  local service_dir="$SCRIPT_DIR/$service_name"
  local load_script="$service_dir/load_image.sh"
  local start_script="$service_dir/start.sh"

  if ! is_enabled "$update_flag"; then
    echo "跳过 $service_name"
    return
  fi

  if [[ ! -d "$service_dir" ]]; then
    echo "未找到服务目录: $service_dir" >&2
    exit 1
  fi

  echo "加载镜像: $service_name"
  if [[ -f "$load_script" ]]; then
    (
      cd "$service_dir"
      bash "./$(basename "$load_script")"
    )
  else
    echo "未找到加载脚本: $load_script"
  fi

  echo "启动服务: $service_name"
  if [[ -f "$start_script" ]]; then
    (
      cd "$service_dir"
      bash "./$(basename "$start_script")"
    )
  else
    echo "未找到启动脚本: $start_script"
  fi
}

copy_config_files

run_service "alarmsrv" "$UPDATE_ALARMSRV"
run_service "apigateway" "$UPDATE_APIGATEWAY"
run_service "hissrv" "$UPDATE_HISSRV"
run_service "netsrv" "$UPDATE_NETSRV"
