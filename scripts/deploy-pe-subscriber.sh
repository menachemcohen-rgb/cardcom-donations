#!/usr/bin/env bash
# Deploys PlatformEventSubscriberConfig CardcomLpSubscriber (B6.3) with the org's integration username.
# This is a real deploy: run it only when you mean to. Usage: scripts/deploy-pe-subscriber.sh <org-alias> <integration-username>
set -euo pipefail
ORG="${1:?org alias}"; USERNAME="${2:?integration username}"
TMP="$(mktemp -d)"
mkdir -p "$TMP/force-app/main/default/platformEventSubscriberConfigs"
sed "s|INTEGRATION_USERNAME|${USERNAME}|" deploy-templates/platformEventSubscriberConfigs/CardcomLpSubscriber.platformEventSubscriberConfig-meta.xml \
  > "$TMP/force-app/main/default/platformEventSubscriberConfigs/CardcomLpSubscriber.platformEventSubscriberConfig-meta.xml"
printf '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"62.0"}\n' > "$TMP/sfdx-project.json"
(cd "$TMP" && sf project deploy start --target-org "$ORG" --source-dir force-app)
rm -rf "$TMP"
