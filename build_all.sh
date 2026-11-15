#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for target in legacy rootful rootless roothide trollfools; do
    bash "$project_root/scripts/build_target.sh" "$target"
done
