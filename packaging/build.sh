#!/usr/bin/env bash
# Builds the release files into dist/:
#   mvn-devops-<version>.zip      Windows (devops.bat) and any system with Bash
#   mvn-devops-<version>.tar.gz   Linux and macOS
#   mvn-devops_<version>_all.deb  Debian, Ubuntu
#   mvn-devops-<version>-1.noarch.rpm  Fedora, RHEL, Rocky, openSUSE
#   SHA256SUMS
# Usage: packaging/build.sh [version]   (default: the VERSION file)
# The Linux packages need nfpm (https://nfpm.goreleaser.com) on PATH or in $NFPM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=${1:-$(cat "$ROOT/VERSION")}
VERSION=${VERSION#v}
DIST=${DIST:-"$ROOT/dist"}
NFPM=${NFPM:-nfpm}
name="mvn-devops-$VERSION"

rm -rf "$DIST"
STAGE="$DIST/stage/$name"
mkdir -p "$STAGE"
cp -R "$ROOT"/{.gitattributes,devops.sh,devops.bat,lib,modules,pipelines,templates,docs,README.md,CHANGELOG.md,LICENSE} "$STAGE/"
printf '%s\n' "$VERSION" > "$STAGE/VERSION"
find "$STAGE" -name '*.sh' -exec chmod 755 {} +

( cd "$DIST/stage" && zip -qr "$DIST/$name.zip" "$name" && tar -czf "$DIST/$name.tar.gz" "$name" )

config=$(< "$ROOT/packaging/nfpm.yaml")
config=${config//'${VERSION}'/$VERSION}
printf '%s\n' "${config//'${STAGE}'/$STAGE}" > "$DIST/stage/nfpm.yaml"
for packager in deb rpm; do
  "$NFPM" package --config "$DIST/stage/nfpm.yaml" --packager "$packager" --target "$DIST/" > /dev/null
done

rm -rf "$DIST/stage"
if command -v sha256sum > /dev/null; then sum=(sha256sum); else sum=(shasum -a 256); fi
( cd "$DIST" && "${sum[@]}" -- * > SHA256SUMS )
ls -1 "$DIST"
