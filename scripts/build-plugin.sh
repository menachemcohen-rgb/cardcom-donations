#!/usr/bin/env bash
# Builds dist/org-donations-<version>.zip for "Plugins → Add New → Upload" (B7.15). Tests and dev tooling are left out.
# Usage: scripts/build-plugin.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=wordpress/org-donations
VER=$(sed -n 's/^ \* Version: *//p' "$SRC/org-donations.php" | head -1)
[ -n "$VER" ] || { echo "Version not found in $SRC/org-donations.php" >&2; exit 1; }
for f in $(find "$SRC" -name '*.php' -not -path '*/vendor/*'); do php -l "$f" >/dev/null; done
mkdir -p dist
OUT="dist/org-donations-$VER.zip"
rm -f "$OUT"
(cd wordpress && zip -qr "../$OUT" org-donations \
  -x 'org-donations/tests/*' 'org-donations/vendor/*' 'org-donations/composer.json' 'org-donations/composer.lock' \
     'org-donations/phpunit.xml.dist' 'org-donations/.phpunit.cache/*' '*/.DS_Store')
echo "Built $OUT"
unzip -l "$OUT" | tail -n +4 | head -n -2 | awk '{print $4}'
