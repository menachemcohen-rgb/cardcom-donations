#!/usr/bin/env bash
# Validates / deploys the folder built by scripts/prod/build-prod.py (docs/production-deployment.md).
# Real changes to the org except "validate". Usage:
#   scripts/prod/deploy-prod.sh <alias> phase1            # first install: custom metadata types + records (real deploy, no Apex)
#   scripts/prod/deploy-prod.sh <alias> validate          # check-only, runs the project's test classes, prints a job id
#   scripts/prod/deploy-prod.sh <alias> quick <job-id>    # deploys the validated job (within 10 days, no change in between)
#   scripts/prod/deploy-prod.sh <alias> deploy            # validate + deploy in one go (only when you mean it)
set -euo pipefail
ALIAS="${1:?org alias}"; MODE="${2:?phase1|validate|quick|deploy}"
DIR="$(cd "$(dirname "$0")/../.." && pwd)/build/prod"
[ -d "$DIR/force-app" ] || { echo "Run scripts/prod/build-prod.py first" >&2; exit 1; }
if [ "$MODE" = phase1 ]; then
  # Validation rules read $CustomMetadata.Cardcom_Setting__mdt.Default: the types and records must exist first.
  cd "$DIR-phase1" && exec sf project deploy start --target-org "$ALIAS" --source-dir force-app --test-level NoTestRun --wait 30
fi
cd "$DIR"
TESTS=()
while read -r t; do [ -n "$t" ] && TESTS+=(--tests "$t"); done < tests.txt
case "$MODE" in
  validate) sf project deploy validate --target-org "$ALIAS" --source-dir force-app --test-level RunSpecifiedTests "${TESTS[@]}" --wait 120 --verbose ;;
  quick)    sf project deploy quick --target-org "$ALIAS" --job-id "${3:?job id from validate}" --wait 60 ;;
  deploy)   sf project deploy start --target-org "$ALIAS" --source-dir force-app --test-level RunSpecifiedTests "${TESTS[@]}" --wait 120 --verbose ;;
  *) echo "mode: phase1 | validate | quick <job-id> | deploy" >&2; exit 1 ;;
esac
