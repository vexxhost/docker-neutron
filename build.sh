#!/usr/bin/env bash
# Customer build script for the docker-neutron image.
#
# Selects an OpenStack release, clones each upstream Neutron-related repository
# at the ref pinned for that release, applies any patches found under
# patches/<org>/<repo>/, and runs `docker buildx build` with the matching base
# images and build contexts.
#
# Usage:
#   ./build.sh                          # builds release 2024.2 -> neutron:local
#   ./build.sh -r 2024.2                # explicit release
#   ./build.sh -r master                # master/development line (CI-equivalent)
#   ./build.sh -t my-neutron:v1         # custom image tag
#   ./build.sh -w /tmp/neutron-src      # custom source workdir
#   RELEASE=2024.2 IMAGE_TAG=neutron:dev ./build.sh   # env vars also work
#
# Requirements:
#   - bash 4+, git, docker (with buildx; included in Docker 23+)
#   - network access to github.com and ghcr.io
#
# On Windows, run this from WSL or Git Bash.

set -euo pipefail

RELEASE="${RELEASE:-2024.2}"
IMAGE_TAG="${IMAGE_TAG:-neutron:local}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-${REPO_ROOT}/build}"
PATCHES_ROOT="${REPO_ROOT}/patches"

usage() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts ":r:t:w:h" opt; do
  case "${opt}" in
    r) RELEASE="${OPTARG}" ;;
    t) IMAGE_TAG="${OPTARG}" ;;
    w) WORKDIR="${OPTARG}" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown flag: -${OPTARG}" >&2; usage >&2; exit 2 ;;
    :)  echo "Flag -${OPTARG} requires an argument" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Per-release configuration.
#
# SOURCES        : "owner/repo|ref" entries. `ref` may be a tag (e.g.
#                  2024.2-eol), a branch (e.g. stable/2024.2), or a commit SHA.
# VENV_BUILDER_IMAGE / PYTHON_BASE_IMAGE : base images that carry the release's
#                  upper-constraints.txt and runtime packages. Pinned by digest
#                  for reproducibility; passed to the Dockerfile as build-args.
#
# Notes for 2024.2 (Dalmatian, EOL):
#   - Most OpenStack repos deleted stable/2024.2 and left an immutable
#     `2024.2-eol` tag, which is what we pin.
#   - neutron-vpnaas has no eol tag yet, so it is pinned to the current
#     stable/2024.2 branch tip (commit SHA) for reproducibility.
#   - The vexxhost neutron add-ons have no per-release branch; they track main
#     and are pinned to known-good commits.
#   - vexxhost/atmosphere (source of the ovsinit crate) is pinned to its
#     stable/2024.2 branch tip.
# ---------------------------------------------------------------------------
case "${RELEASE}" in
  2024.2|dalmatian)
    VENV_BUILDER_IMAGE="ghcr.io/vexxhost/openstack-venv-builder:2024.2@sha256:e81f2137e5454a88dd4d8385430009157282980e6cf9fcc020d849da72190358"
    PYTHON_BASE_IMAGE="ghcr.io/vexxhost/python-base:2024.2@sha256:706b17e0b077a48b75b067d85420c70fda903272b73d2ce1200ac297867ea058"
    SOURCES=(
      "openstack/neutron|2024.2-eol"
      "openstack/neutron-dynamic-routing|2024.2-eol"
      "openstack/neutron-vpnaas|11ffc53800e528d0b0544f7467a7487e0822bd3f"
      "openstack/networking-baremetal|2024.2-eol"
      "openstack/networking-generic-switch|2024.2-eol"
      "openstack/tap-as-a-service|2024.2-eol"
      "vexxhost/neutron-policy-server|a215317bfa147f29dd4e85ff96a54982384c8ba1"
      "vexxhost/neutron-ovn-network-logging-parser|392a445022a87fb460f113bd5e3315760da105e7"
      "vexxhost/atmosphere|51b74fd4d7204a784b93dfad718ed2154ae5dd0b"
    )
    ;;
  master|main)
    # Development line. Matches the SHAs in .github/workflows/build.yml and the
    # default base images baked into the Dockerfile.
    VENV_BUILDER_IMAGE="ghcr.io/vexxhost/openstack-venv-builder:main@sha256:06eaecf7662b1dcbfc39a1171ac060fa3b1cebdd93476e23283e1326c5772fe2"
    PYTHON_BASE_IMAGE="ghcr.io/vexxhost/python-base:main@sha256:cd5f90fbe48ea093f842d4a685b9edfa5c80f4768b066f9b9957bbf47155c245"
    SOURCES=(
      "openstack/neutron|9925d26bc22397cb1e6e87d7417b7f753ca2245a"
      "openstack/neutron-dynamic-routing|5f608f7d3d43396cb956241e4ae2d5759bfb126d"
      "openstack/neutron-vpnaas|574bed1358e668364e3a69a91f249fd65cb11911"
      "openstack/networking-baremetal|f327f9118240efd606890bce1dc6e9690749b860"
      "openstack/networking-generic-switch|053d1243535efc985766b7bdcbabe4954380190f"
      "vexxhost/neutron-policy-server|a215317bfa147f29dd4e85ff96a54982384c8ba1"
      "vexxhost/neutron-ovn-network-logging-parser|392a445022a87fb460f113bd5e3315760da105e7"
      "openstack/tap-as-a-service|f7b99350c74a2a561ea366127c490d5a40b6e93d"
      "vexxhost/atmosphere|main"
    )
    ;;
  *)
    echo "error: unsupported release '${RELEASE}'" >&2
    echo "supported: 2024.2 (alias dalmatian), master (alias main)" >&2
    exit 2
    ;;
esac

# Build contexts passed to `docker buildx build`. Format: "name|relative-path".
# `name` matches the `--mount=type=bind,from=<name>` references in Dockerfile.
# `relative-path` is resolved against ${WORKDIR}.
BUILD_CONTEXTS=(
  "neutron|openstack/neutron"
  "neutron-dynamic-routing|openstack/neutron-dynamic-routing"
  "neutron-vpnaas|openstack/neutron-vpnaas"
  "networking-baremetal|openstack/networking-baremetal"
  "networking-generic-switch|openstack/networking-generic-switch"
  "neutron-policy-server|vexxhost/neutron-policy-server"
  "neutron-ovn-network-logging-parser|vexxhost/neutron-ovn-network-logging-parser"
  "tap-as-a-service|openstack/tap-as-a-service"
  "ovsinit-src|vexxhost/atmosphere/crates/ovsinit"
)

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command '$1' not found in PATH" >&2
    exit 1
  }
}

require git
require docker
docker buildx version >/dev/null 2>&1 || {
  echo "error: 'docker buildx' is required (install Docker 23+ or buildx plugin)" >&2
  exit 1
}

# Resolve a user-supplied ref (tag, branch, or SHA) to something checkout can
# use, preferring tags, then remote-tracking branches, then a raw commit.
resolve_ref() {
  local dest="$1" ref="$2"
  if git -C "${dest}" rev-parse -q --verify "refs/tags/${ref}^{commit}" >/dev/null 2>&1; then
    echo "refs/tags/${ref}"
  elif git -C "${dest}" rev-parse -q --verify "refs/remotes/origin/${ref}^{commit}" >/dev/null 2>&1; then
    echo "refs/remotes/origin/${ref}"
  elif git -C "${dest}" rev-parse -q --verify "${ref}^{commit}" >/dev/null 2>&1; then
    echo "${ref}"
  else
    return 1
  fi
}

prepare_source() {
  local repo="$1" ref="$2"
  local url="https://github.com/${repo}.git"
  local dest="${WORKDIR}/${repo}"

  echo "==> ${repo}@${ref}"
  if [[ -d "${dest}/.git" ]]; then
    git -C "${dest}" fetch --quiet --tags --force --prune origin
  else
    mkdir -p "$(dirname "${dest}")"
    # Full clone so tags (e.g. *-eol) and all branches are available locally.
    git clone --quiet "${url}" "${dest}"
  fi

  local resolved
  if ! resolved="$(resolve_ref "${dest}" "${ref}")"; then
    echo "error: could not resolve ref '${ref}' in ${repo}" >&2
    exit 1
  fi

  git -C "${dest}" checkout --quiet --detach --force "${resolved}"
  git -C "${dest}" reset --hard --quiet HEAD
  git -C "${dest}" clean -fdx --quiet

  local patch_dir="${PATCHES_ROOT}/${repo}"
  if [[ -d "${patch_dir}" ]]; then
    shopt -s nullglob
    local patches=("${patch_dir}"/*.patch)
    shopt -u nullglob
    if (( ${#patches[@]} > 0 )); then
      echo "    applying ${#patches[@]} patch(es) from patches/${repo}/"
      git -C "${dest}" apply --verbose "${patches[@]}"
    fi
  fi
}

echo "==> Building OpenStack release: ${RELEASE}"
echo "    venv-builder: ${VENV_BUILDER_IMAGE}"
echo "    python-base : ${PYTHON_BASE_IMAGE}"
echo

mkdir -p "${WORKDIR}"

for entry in "${SOURCES[@]}"; do
  IFS='|' read -r repo ref <<<"${entry}"
  prepare_source "${repo}" "${ref}"
done

echo
echo "==> docker buildx build -> ${IMAGE_TAG}"

build_args=(
  --tag "${IMAGE_TAG}"
  --build-arg "VENV_BUILDER_IMAGE=${VENV_BUILDER_IMAGE}"
  --build-arg "PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE}"
  --load
)
for entry in "${BUILD_CONTEXTS[@]}"; do
  IFS='|' read -r name path <<<"${entry}"
  build_args+=(--build-context "${name}=${WORKDIR}/${path}")
done
build_args+=("${REPO_ROOT}")

docker buildx build "${build_args[@]}"

echo
echo "Successfully built image: ${IMAGE_TAG} (OpenStack ${RELEASE})"
