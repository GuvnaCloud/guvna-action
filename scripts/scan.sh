#!/usr/bin/env bash
# Runs one drift scan and writes its reports: a table in the log, Markdown
# for the job summary and JSON for later steps, all from the same scan.
# Every report holds resource addresses and attribute names, never values.
set -euo pipefail

# Set by GitHub Actions and action.yml (already validated by check.sh).
: "${RUNNER_TEMP:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_STEP_SUMMARY:?}" "${INPUT_JOB_SUMMARY:?}"
: "${INPUT_TARGETS=}" "${INPUT_CONFIG=}" "${INPUT_FAIL_ON=}" "${INPUT_INIT=}" "${INPUT_CONCURRENCY=}" "${INPUT_TIMEOUT=}"

reports="$(mktemp -d "${RUNNER_TEMP}/guvna-report.XXXXXX")"
md="${reports}/drift-report.md"
json="${reports}/drift-report.json"

args=(drift scan --report "md=${md}" --report "json=${json}")
[[ -n "${INPUT_CONFIG}" ]] && args+=(--config "${INPUT_CONFIG}")
[[ -n "${INPUT_FAIL_ON}" ]] && args+=(--fail-on "${INPUT_FAIL_ON}")
[[ -n "${INPUT_INIT}" ]] && args+=(--init "${INPUT_INIT}")
[[ -n "${INPUT_CONCURRENCY}" ]] && args+=(--concurrency "${INPUT_CONCURRENCY}")
[[ -n "${INPUT_TIMEOUT}" ]] && args+=(--timeout "${INPUT_TIMEOUT}")

# One target per line; "--" ends flags, so a target can never become a flag.
targets=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "${line}" ]] && targets+=("${line}")
done <<<"${INPUT_TARGETS}"
if ((${#targets[@]} > 0)); then
  args+=(-- "${targets[@]}")
fi

set +e
guvna "${args[@]}"
code=$?
set -e

findings=""
if [[ -s "${json}" ]] && command -v jq >/dev/null; then
  findings="$(jq -r '.summary.total // empty' "${json}")"
fi
drift_found=false
[[ -n "${findings}" && "${findings}" != "0" ]] && drift_found=true

{
  echo "exit-code=${code}"
  echo "findings=${findings}"
  echo "drift-found=${drift_found}"
  echo "report-json=${json}"
  echo "report-markdown=${md}"
} >>"${GITHUB_OUTPUT}"

if [[ "${INPUT_JOB_SUMMARY}" == "true" && -s "${md}" ]]; then
  cat "${md}" >>"${GITHUB_STEP_SUMMARY}"
fi

exit "${code}"
