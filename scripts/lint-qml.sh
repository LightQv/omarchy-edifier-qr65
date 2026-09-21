#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_shell=${OMARCHY_SHELL_PATH:-/usr/share/omarchy/shell}

if command -v pyside6-qmllint >/dev/null 2>&1; then
  qmllint=$(command -v pyside6-qmllint)
elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  qmllint=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
  qmllint=$(command -v qmllint)
else
  printf '%s\n' 'Qt 6 qmllint is required.' >&2
  exit 1
fi

[[ -d "$omarchy_shell/Ui" && -d "$omarchy_shell/Commons" ]] || {
  printf 'Omarchy shell QML modules not found at %s\n' "$omarchy_shell" >&2
  exit 1
}

import_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-edifier-qr65-qml.XXXXXX")
trap 'rm -rf -- "$import_root"' EXIT
ln -s "$omarchy_shell" "$import_root/qs"

qml_files=("$repo_root"/*.qml)
"$qmllint" \
  --ignore-settings \
  -W 0 \
  --import disable \
  --missing-property disable \
  --missing-type disable \
  --unresolved-type disable \
  --unqualified disable \
  -I "$import_root" \
  "${qml_files[@]}"
