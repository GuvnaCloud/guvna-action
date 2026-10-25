#!/usr/bin/env bash
# Downloads a guvna release from github.com/GuvnaCloud/releases, verifies it
# and puts the binary on PATH. Verification, in order:
#   1. (default) the Sigstore signature on checksums.txt, which must come from
#      guvna's own release workflow for exactly this tag;
#   2. always: the archive's SHA-256 against checksums.txt.
# Nothing is extracted or run before both pass.
set -euo pipefail

# Set by GitHub Actions and action.yml (already validated by check.sh).
: "${RUNNER_OS:?}" "${RUNNER_ARCH:?}" "${RUNNER_TEMP:?}" "${GITHUB_PATH:?}"
: "${INPUT_VERSION:?}" "${INPUT_VERIFY_SIGNATURE:?}"

fail() {
  echo "::error title=guvna::$*"
  exit 1
}

version="${INPUT_VERSION}"
case "${RUNNER_OS}" in
  Linux) os=linux ;;
  macOS) os=darwin ;;
  *) fail "unsupported runner OS ${RUNNER_OS}" ;;
esac
case "${RUNNER_ARCH}" in
  X64) arch=amd64 ;;
  ARM64) arch=arm64 ;;
  *) fail "unsupported runner architecture ${RUNNER_ARCH}" ;;
esac

base="https://github.com/GuvnaCloud/releases/releases/download/v${version}"
archive="guvna_${version}_${os}_${arch}.tar.gz"
identity="https://github.com/GuvnaCloud/guvna/.github/workflows/release.yml@refs/tags/v${version}"
issuer="https://token.actions.githubusercontent.com"

work="$(mktemp -d "${RUNNER_TEMP}/guvna-install.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

download() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 -o "${work}/$1" "${base}/$1" ||
    fail "could not download $1 for guvna ${version}. Does release v${version} exist?"
}

download checksums.txt
download "${archive}"

if [[ "${INPUT_VERIFY_SIGNATURE}" == "true" ]]; then
  download checksums.txt.sigstore.json
  cosign verify-blob \
    --bundle "${work}/checksums.txt.sigstore.json" \
    --certificate-identity "${identity}" \
    --certificate-oidc-issuer "${issuer}" \
    "${work}/checksums.txt" >/dev/null ||
    fail "signature verification failed for guvna ${version}: refusing to install"
  echo "Verified Sigstore signature: ${identity}"
fi

expected="$(awk -v f="${archive}" '$2 == f { print $1 }' "${work}/checksums.txt")"
[[ "${expected}" =~ ^[0-9a-f]{64}$ ]] || fail "no checksum for ${archive} in checksums.txt"
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "${work}/${archive}" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "${work}/${archive}" | cut -d' ' -f1)"
fi
[[ "${actual}" == "${expected}" ]] || fail "checksum mismatch for ${archive}: refusing to install"
echo "Verified SHA-256: ${archive}"

# Extract only the binary.
mkdir "${work}/x"
tar -xzf "${work}/${archive}" -C "${work}/x" guvna || fail "could not extract guvna from ${archive}"

bin="${RUNNER_TEMP}/guvna-bin"
mkdir -p "${bin}"
install -m 0755 "${work}/x/guvna" "${bin}/guvna"
echo "${bin}" >>"${GITHUB_PATH}"
"${bin}/guvna" version
