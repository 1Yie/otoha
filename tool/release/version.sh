#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: version.sh VERSION [--push]

Create an Otoha release commit and annotated Git tag.

  VERSION  Stable semantic version without a prefix, for example 1.0.1
  --push   Atomically push the current branch and tag to origin
EOF
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage >&2
  exit 64
fi

version="$1"
push_release=false
if [ "$#" -eq 2 ]; then
  if [ "$2" != "--push" ]; then
    usage >&2
    exit 64
  fi
  push_release=true
fi

if ! [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Version must use stable SemVer without a prefix, for example 1.0.1." >&2
  exit 64
fi

repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Run this script inside the Otoha Git repository." >&2
  exit 69
}
cd "$repository_root"

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
  echo "Release tags cannot be created from a detached HEAD." >&2
  exit 65
}
if [ "$branch" != "main" ]; then
  echo "Create releases from main; current branch is $branch." >&2
  exit 65
fi

if ! git diff --quiet ||
  ! git diff --cached --quiet ||
  [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "Commit or remove all working-tree changes before creating a release." >&2
  exit 65
fi

if git show-ref --verify --quiet "refs/tags/$version"; then
  echo "Tag $version already exists." >&2
  exit 65
fi

current="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
if ! [[ "$current" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([1-9][0-9]*)$ ]]; then
  echo "pubspec.yaml has an unsupported version: $current" >&2
  exit 65
fi

current_version="${current%%+*}"
current_build="${current#*+}"
IFS=. read -r current_major current_minor current_patch <<< "$current_version"
IFS=. read -r next_major next_minor next_patch <<< "$version"
if ((next_major < current_major)) ||
  ((next_major == current_major && next_minor < current_minor)) ||
  ((next_major == current_major && next_minor == current_minor && next_patch <= current_patch)); then
  echo "Version $version must be newer than $current_version." >&2
  exit 65
fi

next_build=$((current_build + 1))
next="$version+$next_build"
temporary_pubspec="$(mktemp)"
trap 'rm -f "$temporary_pubspec"' EXIT
awk -v release_version="$next" '
  $1 == "version:" { print "version: " release_version; replaced = 1; next }
  { print }
  END { if (!replaced) exit 1 }
' pubspec.yaml > "$temporary_pubspec"
cat "$temporary_pubspec" > pubspec.yaml
rm -f "$temporary_pubspec"
trap - EXIT

git add pubspec.yaml
git commit -m "chore(release): prepare $version"
git tag --annotate "$version" --message "Otoha $version"

echo "Created Otoha $next at tag $version."
if $push_release; then
  git remote get-url origin >/dev/null 2>&1 || {
    echo "Remote origin is not configured; the local commit and tag were kept." >&2
    exit 69
  }
  git push --atomic origin "$branch" "refs/tags/$version"
  echo "Pushed $branch and tag $version to origin."
else
  echo "Review the release, then push it with:"
  echo "  git push --atomic origin $branch refs/tags/$version"
fi
