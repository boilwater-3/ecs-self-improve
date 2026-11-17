#!/usr/bin/env bash
# Conan 引导脚本：从 CMakePresets.json / CMakeUserPresets.json 动态解析 preset 参数并执行 conan install。
#
# 用法：
#   scripts/bootstrap_conan.sh <preset>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ecs_env.sh
source "${SCRIPT_DIR}/lib/ecs_env.sh"

# --- 参数校验 ---
if [[ $# -ne 1 ]]; then
    echo "用法: $0 <configure_preset>" >&2
    exit 2
fi

PRESET="$1"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONANFILE="${SOURCE_DIR}/conanfile.py"

if [[ ! -f "${CONANFILE}" ]]; then
    echo "错误: 未找到 conanfile.py: ${CONANFILE}" >&2
    exit 1
fi

if ! command -v conan >/dev/null 2>&1; then
    echo "错误: 未找到 conan 可执行文件，请先安装 Conan 2.x（pip install conan）" >&2
    exit 1
fi

PY="$(command -v python3 || command -v python || true)"
if [[ -z "${PY}" ]]; then
    echo "错误: 需要 python3 解析 CMakePresets.json" >&2
    exit 1
fi

_query() {
    ECS_ROOT="${SOURCE_DIR}" "${PY}" "${SCRIPT_DIR}/lib/ecs_preset_query.py" "${PRESET}" "$1"
}

CONFIGURE_PRESET="$(_query configurePreset)"
PACKAGE_MANAGER="$(_query packageManager)"
if [[ "${PACKAGE_MANAGER}" != "conan" ]]; then
    echo "[bootstrap_conan] preset '${CONFIGURE_PRESET}' 的 PACKAGE_MANAGER=${PACKAGE_MANAGER}，无需 Conan 引导。"
    exit 0
fi

BINARY_DIR="$(_query binaryDir)"
BUILD_TYPE="$(_query buildType)"
ENABLE_TESTING="$(_query enableTesting)"
CPPSTD="$(_query cppstd)"

# --- 组装 conan install 公共参数 ---------------------------------------------
if [[ -z "${BUILD_TYPE}" ]]; then
    BUILD_TYPE="Release"
fi

CONAN_COMMON_ARGS=(
    install "${SOURCE_DIR}"
    --output-folder "${BINARY_DIR}"
    --build=missing
    -s "compiler.cppstd=${CPPSTD}"
    -o "&:enable_testing=${ENABLE_TESTING}"
)

# --- 执行 -------------------------------------------------------------------
echo "[bootstrap_conan] preset=${CONFIGURE_PRESET}"
echo "[bootstrap_conan] output-folder=${BINARY_DIR}"
echo "[bootstrap_conan] build_type=${BUILD_TYPE}"
echo "[bootstrap_conan] cppstd=${CPPSTD}"
echo "[bootstrap_conan] enable_testing=${ENABLE_TESTING}"
echo

echo "[bootstrap_conan] 运行: conan ${CONAN_COMMON_ARGS[*]} -s build_type=${BUILD_TYPE}"
echo
conan "${CONAN_COMMON_ARGS[@]}" -s "build_type=${BUILD_TYPE}"

# --- 报告生成的 toolchain 路径 ----------------------------------------------
TOOLCHAIN="$(_query toolchain)"
if [[ -z "${TOOLCHAIN}" ]]; then
    TOOLCHAIN="${BINARY_DIR}/build/${BUILD_TYPE}/generators/conan_toolchain.cmake"
fi

echo
echo "[bootstrap_conan] 成功。生成的 toolchain:"
echo "  ${TOOLCHAIN}"
if [[ ! -f "${TOOLCHAIN}" ]]; then
    echo "警告: 预期路径未找到 toolchain 文件，请检查 conan 输出。" >&2
fi
echo
echo "下一步："
echo "  cmake --preset ${CONFIGURE_PRESET}"
