#!/usr/bin/env bash
# ECS 构建/测试统一入口
#
# 用法：
#   scripts/ecs.sh bootstrap <configure_preset>
#   scripts/ecs.sh configure <configure_preset>
#   scripts/ecs.sh build <build_preset> [--target T ...] [-j N]
#   scripts/ecs.sh test <test_preset> [-R regex] [-j N]
#   scripts/ecs.sh install <configure_preset> [--prefix DIR]
#   scripts/ecs.sh doctor
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ecs_env.sh
source "${SCRIPT_DIR}/lib/ecs_env.sh"

usage() {
  cat <<'EOF'
ECS 构建/测试工具

  scripts/ecs.sh bootstrap <configure_preset>
  scripts/ecs.sh configure <configure_preset>
  scripts/ecs.sh build <build_preset> [--target T ...] [-j N]
  scripts/ecs.sh test <test_preset> [-R regex] [-j N]
  scripts/ecs.sh install <configure_preset> [--prefix DIR]   # 打包安装（不构建）
  scripts/ecs.sh doctor

configure_preset 例：llvm-ninja-release | llvm-ninja-debug | llvm-ninja-asan | llvm-ninja-release-local
build/test preset 例：llvm-ninja-release | llvm-ninja-debug | llvm-ninja-asan | llvm-ninja-release-local

build 禁止隐式 reconfigure：CMake/依赖变更后须先 configure 对应 preset，再 build。
EOF
}

doctor() {
  echo "ECS_ROOT=${ECS_ROOT}"
  echo "ECS_CMAKE_ROOT=${ECS_CMAKE_ROOT:-<unset>}"
  echo "uname=$(uname -s 2>/dev/null || echo unknown)"
  if command -v cmake >/dev/null 2>&1; then
    echo "cmake=$(command -v cmake)"
    cmake --version | head -n 1
  else
    echo "cmake=NOT FOUND"
  fi
  _ctest="$(_ecs_resolve_ctest || true)"
  if [[ -n "${_ctest}" ]]; then
    echo "ctest=${_ctest}"
  else
    echo "ctest=NOT FOUND"
  fi
  if command -v conan >/dev/null 2>&1; then
    echo "conan=$(command -v conan)"
    conan --version
  else
    echo "conan=NOT FOUND"
  fi
  unset _ctest
  echo "ECS_REAL_CMAKE=${ECS_REAL_CMAKE:-<unset>}"
}

_ecs_resolve_ctest() {
  if command -v ctest >/dev/null 2>&1; then
    command -v ctest
    return 0
  fi
  if [[ -n "${ECS_REAL_CMAKE:-}" ]]; then
    local dir candidate
    dir="$(dirname "${ECS_REAL_CMAKE}")"
    for candidate in "${dir}/ctest.exe" "${dir}/ctest"; do
      if [[ -x "${candidate}" || -f "${candidate}" ]]; then
        printf '%s' "${candidate}"
        return 0
      fi
    done
  fi
  return 1
}

_ecs_binary_dir() {
  local preset="$1" py
  py="$(command -v python3 || command -v python || true)"
  if [[ -z "${py}" ]]; then
    echo "[ecs.sh] 需要 python3 解析 preset 的 binaryDir" >&2
    return 1
  fi
  "${py}" "${SCRIPT_DIR}/lib/ecs_preset_query.py" "${preset}" binaryDir
}

_ecs_toolchain_file() {
  local preset="$1" py
  py="$(command -v python3 || command -v python || true)"
  if [[ -z "${py}" ]]; then
    echo "[ecs.sh] 需要 python3 解析 preset 的 toolchain" >&2
    return 1
  fi
  "${py}" "${SCRIPT_DIR}/lib/ecs_preset_query.py" "${preset}" toolchain
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  bootstrap)
    [[ $# -ge 1 ]] || { usage; exit 2; }
    exec bash "${SCRIPT_DIR}/bootstrap_conan.sh" "$1"
    ;;
  configure)
    [[ $# -ge 1 ]] || { usage; exit 2; }
    preset="$1"
    shift || true
    # 首次配置自动引导：preset 的 conan toolchain 不存在时先跑 bootstrap。
    _tc="$(_ecs_toolchain_file "${preset}" 2>/dev/null || true)"
    if [[ -n "${_tc}" ]] && [[ ! -f "${_tc}" ]]; then
      echo "[ecs.sh configure] conan toolchain 缺失，自动 bootstrap: ${preset}"
      bash "${SCRIPT_DIR}/bootstrap_conan.sh" "${preset}"
    fi
    unset _tc
    exec cmake --preset "${preset}" "$@"
    ;;
  build)
    [[ $# -ge 1 ]] || { usage; exit 2; }
    preset="$1"
    shift
    # shellcheck source=lib/ecs_build_guard.sh
    source "${SCRIPT_DIR}/lib/ecs_build_guard.sh"
    _ecs_run_build_guard "${preset}" || exit 1
    exec cmake --build --preset "${preset}" "$@"
    ;;
  test)
    [[ $# -ge 1 ]] || { usage; exit 2; }
    preset="$1"
    shift
    extra=(--output-on-failure)
    while [[ $# -gt 0 ]]; do
      extra+=("$1")
      shift
    done
    if ! printf '%s\n' "${extra[@]}" | grep -q -- '-j'; then
      extra+=(-j 4)
    fi
    _ctest="$(_ecs_resolve_ctest || true)"
    if [[ -z "${_ctest}" ]]; then
      echo "[ecs.sh test] ctest not found. Run: scripts/ecs.sh doctor" >&2
      exit 127
    fi
    exec "${_ctest}" --preset "${preset}" "${extra[@]}"
    ;;
  install)
    [[ $# -ge 1 ]] || { usage; exit 2; }
    preset="$1"
    shift
    _bin="$(_ecs_binary_dir "${preset}")" || exit 1
    exec cmake --install "${_bin}" "$@"
    ;;
  doctor)
    doctor
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    echo "未知子命令: ${cmd}" >&2
    usage
    exit 2
    ;;
esac
