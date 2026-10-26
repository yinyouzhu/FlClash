#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ref=upstream/main
build=0

usage() {
  cat <<'EOF'
usage: tool/sync_upstream.sh [ref] [--build]

  ref      upstream/main (default), a tag such as v0.9.3, or a commit
  --build  also run a macOS debug build to verify the tree

Merges upstream into dev, refreshes the Core submodule, regenerates Dart
code, and runs static analysis.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --build) build=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; usage; exit 1 ;;
    *) ref="$arg" ;;
  esac
done

group() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::$1"; else echo "==> $1"; fi
}

endgroup() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::"; fi
}

if [[ -n "$(git status --porcelain)" ]]; then
  echo "worktree is dirty, commit or stash before syncing" >&2
  git status --short >&2
  exit 1
fi

current="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current" != "dev" ]]; then
  echo "expected branch dev, on $current" >&2
  exit 1
fi

group "fetch upstream"
git fetch upstream --tags --prune
endgroup

group "update main mirror"
git checkout main
git merge --ff-only "$ref"
git push origin main || echo "warning: main not pushed to origin" >&2
endgroup

group "merge $ref into dev"
git checkout dev
if ! git merge --no-edit "$ref"; then
  echo "conflicts above; resolve them, then re-run this script" >&2
  exit 1
fi
endgroup

group "update Core submodule"
git submodule update --init --recursive
endgroup

group "dart dependencies"
flutter pub get
endgroup

group "code generation"
dart run build_runner build --delete-conflicting-outputs
endgroup

group "drop codegen hash noise"
reverted=0
while read -r file; do
  [[ -z "$file" ]] && continue
  other="$(git diff -U0 -- "$file" | awk '/^[+-]/ && !/^(\+\+\+|---)/ && !/^[+-]String _\$.*Hash\(\) => r/')"
  if [[ -z "$other" ]]; then
    git checkout -- "$file"
    reverted=$((reverted + 1))
  fi
done < <(git diff --name-only)
echo "reverted $reverted file(s) whose only change was a provider hash"
endgroup

group "analyze"
flutter analyze --no-fatal-infos
endgroup

if [[ $build -eq 1 ]]; then
  group "macOS debug build"
  flutter build macos --debug
  endgroup
fi

echo
echo "now at $(git log --oneline -1)"
echo "your footprint against upstream:"
git diff --stat upstream/main | tail -1
