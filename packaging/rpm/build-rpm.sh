#!/usr/bin/env bash
set -euo pipefail

: "${RPM_VERSION:?}"
: "${RPM_BUILDNUM:?}"
: "${RPM_SHORTSHA:?}"
: "${GH_OWNER:?}"
: "${HOST_UID:?}"
: "${HOST_GID:?}"

dnf install -y --setopt=install_weak_deps=False rpm-build >/dev/null

WORK=$(pwd)
TOPDIR="${WORK}/packaging/rpm/rpmbuild"
SOURCES_DIR="${WORK}/packaging/rpm/sources"
OUT="${WORK}/packaging/rpm/out"
SPEC=$(ls "${WORK}/packaging/rpm/"*.spec | head -1)

rm -rf "${TOPDIR}" "${OUT}"
mkdir -p "${TOPDIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "${OUT}"

cp "${SOURCES_DIR}"/* "${TOPDIR}/SOURCES/"
cp "${SPEC}"          "${TOPDIR}/SPECS/"

rpmbuild \
    --define "_topdir ${TOPDIR}" \
    --define "_version ${RPM_VERSION}" \
    --define "_buildnum ${RPM_BUILDNUM}" \
    --define "_shortsha ${RPM_SHORTSHA}" \
    --define "_owner ${GH_OWNER}" \
    --define "_changelog_date $(LC_ALL=C date -u '+%a %b %d %Y')" \
    -bb "${TOPDIR}/SPECS"/*.spec

find "${TOPDIR}/RPMS" -name '*.rpm' -exec cp -v {} "${OUT}/" \;

chown -R "${HOST_UID}:${HOST_GID}" "${TOPDIR}" "${OUT}"

ls -lh "${OUT}/"
