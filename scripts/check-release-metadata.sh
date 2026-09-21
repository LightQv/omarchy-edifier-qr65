#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/manifest.json"
readme="$repo_root/README.md"
changelog="$repo_root/CHANGELOG.md"

version=$(/usr/bin/jq -er '.version | select(type == "string")' "$manifest")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Invalid manifest version: %s\n' "$version" >&2
  exit 1
}

escaped_version=${version//./\.}
/usr/bin/grep -Eq "^## \[$escaped_version\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog" || {
  printf 'CHANGELOG.md has no dated release section for %s\n' "$version" >&2
  exit 1
}

canonical_base='https://github.com/LightQv/omarchy-edifier-qr65'
/usr/bin/grep -Fq "[$version]: $canonical_base/releases/tag/v$version" "$changelog" || {
  printf 'CHANGELOG.md has no release link for %s\n' "$version" >&2
  exit 1
}
/usr/bin/grep -Fq "[Unreleased]: $canonical_base/compare/v$version...HEAD" "$changelog" || {
  printf 'CHANGELOG.md has no comparison link after %s\n' "$version" >&2
  exit 1
}

/usr/bin/grep -Fq 'https://github.com/LightQv/omarchy-edifier-qr65.git' "$readme" || {
  printf '%s\n' 'README.md does not use the canonical repository URL' >&2
  exit 1
}
/usr/bin/grep -Fq 'ef4d923106adcf9cbb80a087b306c9eb16fdf1fd' "$readme" || {
  printf '%s\n' 'README.md does not pin the reviewed daemon commit' >&2
  exit 1
}

[[ -s "$repo_root/preview.png" ]] || {
  printf '%s\n' 'Missing marketplace preview: preview.png' >&2
  exit 1
}

for instructions in AGENTS.md CLAUDE.md GEMINI.md .cursorrules .windsurfrules \
    .github/copilot-instructions.md; do
  [[ ! -e "$repo_root/$instructions" ]] || {
    printf 'Auto-discovered agent instructions must not ship: %s\n' "$instructions" >&2
    exit 1
  }
done

while IFS= read -r tracked; do
  case "$tracked" in
    AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|GEMINI.md|*/GEMINI.md|\
    .github/instructions/*.instructions.md|*/.github/instructions/*.instructions.md)
      printf 'Auto-discovered agent instructions must not ship: %s\n' "$tracked" >&2
      exit 1
      ;;
  esac
done < <(git -C "$repo_root" ls-files --cached --others --exclude-standard)

printf 'Release metadata %s is consistent.\n' "$version"
