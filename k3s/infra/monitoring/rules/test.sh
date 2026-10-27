#!/usr/bin/env bash
# Unit-tests alerts.prometheusrule.yaml with promtool. Run: bash test.sh
# Needs promtool and yq (brew install prometheus yq).
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# promtool reads plain rule groups, not the PrometheusRule wrapper.
yq '{"groups": .spec.groups}' alerts.prometheusrule.yaml > "$tmp/alerts.rules.yaml"
cp alerts.test.yaml "$tmp/alerts.test.yaml"

promtool check rules "$tmp/alerts.rules.yaml"
promtool test rules "$tmp/alerts.test.yaml"
