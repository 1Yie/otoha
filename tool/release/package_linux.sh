#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: package_linux.sh BUNDLE_DIRECTORY VERSION NODE_BINARY OUTPUT_DIRECTORY" >&2
  exit 64
fi

bundle_directory="$1"
version="$2"
node_binary="$(readlink -f "$3")"
output_directory="$4"
stage_directory="$(mktemp -d)"
rpm_top_directory="$(mktemp -d)"

cleanup() {
  rm -rf "$stage_directory" "$rpm_top_directory"
}
trap cleanup EXIT

install -d "$stage_directory/usr/lib/otoha"
cp -a "$bundle_directory/." "$stage_directory/usr/lib/otoha/"
if [ ! -f "$stage_directory/usr/lib/otoha/sidecar/src/index.mjs" ] ||
  [ ! -f "$stage_directory/usr/lib/otoha/sidecar/node_modules/youtubei.js/package.json" ]; then
  rm -rf "$stage_directory/usr/lib/otoha/sidecar"
  cp -a sidecar "$stage_directory/usr/lib/otoha/sidecar"
fi
if [ ! -x "$stage_directory/usr/lib/otoha/node/bin/node" ]; then
  install -Dm755 "$node_binary" "$stage_directory/usr/lib/otoha/node/bin/node"
fi

node_root="$(dirname "$(dirname "$node_binary")")"
if [ ! -f "$stage_directory/usr/lib/otoha/node/LICENSE" ] &&
  [ -f "$node_root/LICENSE" ]; then
  install -Dm644 "$node_root/LICENSE" "$stage_directory/usr/lib/otoha/node/LICENSE"
fi

install -d "$stage_directory/usr/bin"
ln -s ../lib/otoha/otoha "$stage_directory/usr/bin/otoha"
install -Dm644 linux/packaging/im.ingstar.otoha.desktop \
  "$stage_directory/usr/share/applications/im.ingstar.otoha.desktop"
install -Dm644 snap/gui/otoha.png \
  "$stage_directory/usr/share/icons/hicolor/256x256/apps/im.ingstar.otoha.png"

install -d "$stage_directory/DEBIAN" "$output_directory"
printf '%s\n' \
  'Package: otoha' \
  "Version: $version" \
  'Section: sound' \
  'Priority: optional' \
  'Architecture: amd64' \
  'Maintainer: Ingstar' \
  'Depends: libayatana-appindicator3-1, libgtk-3-0, libmpv2, libsecret-1-0' \
  'Description: Otoha desktop music player' \
  > "$stage_directory/DEBIAN/control"
dpkg-deb --root-owner-group --build \
  "$stage_directory" "$output_directory/Otoha_${version}_amd64.deb"
rm -rf "$stage_directory/DEBIAN"

install -d "$rpm_top_directory/BUILD" "$rpm_top_directory/BUILDROOT" \
  "$rpm_top_directory/RPMS" "$rpm_top_directory/SOURCES" \
  "$rpm_top_directory/SPECS" "$rpm_top_directory/SRPMS"
rpm_version="${version//+/_}"
spec_file="$rpm_top_directory/SPECS/otoha.spec"
printf '%s\n' \
  'Name: otoha' \
  "Version: $rpm_version" \
  'Release: 1%{?dist}' \
  'Summary: Otoha desktop music player' \
  'License: MIT' \
  'BuildArch: x86_64' \
  '' \
  '%description' \
  'Otoha desktop music player.' \
  '' \
  '%files' \
  '/usr/bin/otoha' \
  '/usr/lib/otoha' \
  '/usr/share/applications/im.ingstar.otoha.desktop' \
  '/usr/share/icons/hicolor/256x256/apps/im.ingstar.otoha.png' \
  > "$spec_file"
rpmbuild --define "_topdir $rpm_top_directory" --buildroot "$stage_directory" \
  -bb "$spec_file"
rpm_package="$(find "$rpm_top_directory/RPMS" -type f -name 'otoha-*.rpm' -print -quit)"
test -n "$rpm_package"
cp "$rpm_package" "$output_directory/Otoha_${version}_x86_64.rpm"
