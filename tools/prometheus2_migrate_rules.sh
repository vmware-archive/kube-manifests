#!/bin/sh
set -eu

# Migrate prometheus-v1 .rules to prometheus-v2 .rules.yml,
# will create new .yml files without touching original .rules
cd common/config
for i in *.rules; do
    promtool update rules $i
done

