#!/usr/bin/env bash
# Tests scripts/check.sh: valid inputs pass, every invalid input and unsafe
# context is refused. Runs anywhere with bash: bash test/check_test.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
check="${here}/../scripts/check.sh"
failures=0

defaults() {
  export GITHUB_EVENT_NAME=push RUNNER_OS=Linux RUNNER_ARCH=X64
  export INPUT_VERSION=0.1.0-beta.2 INPUT_TARGETS="" INPUT_FAIL_ON="" INPUT_INIT=""
  export INPUT_CONCURRENCY="" INPUT_TIMEOUT="" INPUT_JOB_SUMMARY=true
  export INPUT_VERIFY_SIGNATURE=true INPUT_ALLOW_PULL_REQUEST_TARGET=false
}

expect() { # expect pass|fail "name" VAR=value...
  local want="$1" name="$2"
  shift 2
  (
    defaults
    for kv in "$@"; do export "${kv?}"; done
    bash "${check}" >/dev/null 2>&1
  )
  local code=$?
  if [[ "${want}" == pass && ${code} -ne 0 ]] || [[ "${want}" == fail && ${code} -eq 0 ]]; then
    echo "FAIL: ${name} (want ${want}, exit ${code})"
    failures=$((failures + 1))
  else
    echo "ok:   ${name}"
  fi
}

expect pass "defaults"
expect pass "stable version" INPUT_VERSION=1.2.3
expect pass "every fail-on" INPUT_FAIL_ON=critical
expect pass "fail-on none" INPUT_FAIL_ON=none
expect pass "macOS arm64" RUNNER_OS=macOS RUNNER_ARCH=ARM64
expect pass "targets list" INPUT_TARGETS=$'infra/prod\ninfra/staging\n'
expect pass "timeout" INPUT_TIMEOUT=1h30m
expect pass "pull_request_target when allowed" GITHUB_EVENT_NAME=pull_request_target INPUT_ALLOW_PULL_REQUEST_TARGET=true

expect fail "pull_request_target by default" GITHUB_EVENT_NAME=pull_request_target
expect fail "windows" RUNNER_OS=Windows
expect fail "32-bit" RUNNER_ARCH=X86
expect fail "version with v" INPUT_VERSION=v0.1.0
expect fail "version with shell" 'INPUT_VERSION=0.1.0;id'
expect fail "version latest" INPUT_VERSION=latest
expect fail "bad fail-on" INPUT_FAIL_ON=severe
expect fail "bad init" INPUT_INIT=sometimes
expect fail "concurrency 0" INPUT_CONCURRENCY=0
expect fail "concurrency 65" INPUT_CONCURRENCY=65
expect fail "concurrency text" INPUT_CONCURRENCY=four
expect fail "bad timeout" INPUT_TIMEOUT=30
expect fail "bad boolean" INPUT_JOB_SUMMARY=yes
expect fail "control characters" INPUT_TARGETS=$'infra\x1b[31m'

if ((failures > 0)); then
  echo "${failures} check test(s) failed"
  exit 1
fi
echo "all check tests passed"
