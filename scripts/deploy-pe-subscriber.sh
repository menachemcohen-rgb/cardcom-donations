#!/usr/bin/env bash
# Deploys the PlatformEventSubscriberConfigs (CardcomLpSubscriber B6.3, ChargeSuccessSubscriber B6.9.2, DonationSetupSubscriber N42) with the integration username.
# This is a real deploy: run it only when you mean to. Usage: scripts/deploy-pe-subscriber.sh <org-alias> <integration-username>
set -euo pipefail
ORG="${1:?org alias}"; USERNAME="${2:?integration username}"
TMP="$(mktemp -d)"
mkdir -p "$TMP/force-app/main/default/platformEventSubscriberConfigs"
for f in deploy-templates/platformEventSubscriberConfigs/*.platformEventSubscriberConfig-meta.xml; do
  sed "s|INTEGRATION_USERNAME|${USERNAME}|" "$f" > "$TMP/force-app/main/default/platformEventSubscriberConfigs/$(basename "$f")"
done
printf '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"62.0"}\n' > "$TMP/sfdx-project.json"
(cd "$TMP" && sf project deploy start --target-org "$ORG" --source-dir force-app)
rm -rf "$TMP"
