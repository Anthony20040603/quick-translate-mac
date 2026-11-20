#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/quicktranslate-clang-cache"
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
