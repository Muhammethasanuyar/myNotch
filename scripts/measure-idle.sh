#!/usr/bin/env bash
# Samples the running MyNotch's CPU with `top` and prints the average and peak.
# Usage: scripts/measure-idle.sh [seconds=30]   (launch the app in the state to measure first)
set -euo pipefail
seconds="${1:-30}"
pid="$(pgrep -x MyNotch | head -1)" || { echo "MyNotch is not running" >&2; exit 1; }
# One sample every 2 s; the first `top` sample is a cumulative figure, so it is dropped.
# `top` prints a decimal comma in Turkish locales, so the CPU column is normalised before summing.
samples=$(( seconds / 2 + 1 ))
top -l "$samples" -s 2 -stats pid,cpu,mem -pid "$pid" \
  | LC_ALL=C awk -v pid="$pid" '$1 == pid { n++; if (n > 1) { cpu = $2; gsub(",", ".", cpu); cpu += 0; sum += cpu; if (cpu > max) max = cpu; last = $3 } }
         END { if (n > 1) printf "MyNotch pid %s: avg %.2f%% CPU, peak %.2f%% over %d samples, mem %s\n", pid, sum / (n - 1), max, n - 1, last }'
