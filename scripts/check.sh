#!/usr/bin/env bash
# Validates the action's inputs and refuses unsafe contexts before anything
# is downloaded or run. Inputs arrive as INPUT_* environment variables.
set -euo pipefail

# Set by GitHub Actions and action.yml; fail fast if one is missing.
: "${RUNNER_OS:?}" "${RUNNER_ARCH:?}" "${INPUT_VERSION:?}" "${INPUT_JOB_SUMMARY:?}"
: "${INPUT_VERIFY_SIGNATURE:?}" "${INPUT_ALLOW_PULL_REQUEST_TARGET:?}"
: "${INPUT_TARGETS=}" "${INPUT_FAIL_ON=}" "${INPUT_INIT=}" "${INPUT_CONCURRENCY=}" "${INPUT_TIMEOUT=}"

fail() {
  echo "::error title=guvna::$*"
  exit 1
}

# Untrusted code + secrets: pull_request_target runs with the base
# repository's secrets, so scanning a pull request's Terraform code there
# would let that code use your credentials.
if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request_target" && "${INPUT_ALLOW_PULL_REQUEST_TARGET}" != "true" ]]; then
  fail "refusing to run on pull_request_target: it can run untrusted code with your secrets. Scan on a schedule or on pushes to protected branches instead (see the README)."
fi

case "${RUNNER_OS}" in
  Linux | macOS) ;;
  *) fail "unsupported runner OS '${RUNNER_OS}': use a Linux or macOS runner" ;;
esac
case "${RUNNER_ARCH}" in
  X64 | ARM64) ;;
  *) fail "unsupported runner architecture '${RUNNER_ARCH}': use x64 or arm64" ;;
esac

[[ "${INPUT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]] ||
  fail "version must be a release version such as 0.1.0-beta.2 (no leading v)"

if [[ -n "${INPUT_FAIL_ON}" ]]; then
  case "${INPUT_FAIL_ON}" in
    info | low | medium | high | critical | none) ;;
    *) fail "fail-on must be one of info, low, medium, high, critical, none" ;;
  esac
fi

if [[ -n "${INPUT_INIT}" ]]; then
  case "${INPUT_INIT}" in
    auto | always | never) ;;
    *) fail "init must be one of auto, always, never" ;;
  esac
fi

if [[ -n "${INPUT_CONCURRENCY}" ]]; then
  if [[ ! "${INPUT_CONCURRENCY}" =~ ^[0-9]{1,2}$ ]] || ((10#${INPUT_CONCURRENCY} < 1 || 10#${INPUT_CONCURRENCY} > 64)); then
    fail "concurrency must be a whole number from 1 to 64"
  fi
fi

if [[ -n "${INPUT_TIMEOUT}" ]]; then
  [[ "${INPUT_TIMEOUT}" =~ ^([0-9]+(\.[0-9]+)?(ns|us|ms|s|m|h))+$ ]] ||
    fail "timeout must be a duration such as 30m or 1h30m"
fi

for pair in JOB_SUMMARY:job-summary VERIFY_SIGNATURE:verify-signature ALLOW_PULL_REQUEST_TARGET:allow-pull-request-target; do
  var="INPUT_${pair%%:*}"
  case "${!var}" in
    true | false) ;;
    *) fail "${pair#*:} must be true or false" ;;
  esac
done

if [[ "${INPUT_VERIFY_SIGNATURE}" != "true" ]]; then
  echo "::warning title=guvna::verify-signature is off: only the SHA-256 checksum will be checked."
fi

# Targets are passed to guvna one per line, after "--", so they can never be
# read as flags. Control characters other than newline and tab are refused.
if LC_ALL=C grep -q $'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' <<<"${INPUT_TARGETS}"; then
  fail "targets contain control characters"
fi
