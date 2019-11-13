#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

readonly TMP_FILE=$(mktemp)

echo '##########################################'
remark --use validate-links . > >(tee -a "$TMP_FILE") 2>&1
echo '##########################################'
remark --use 'lint-no-dead-urls=skipLocalhost:true' . > >(tee -a "$TMP_FILE") 2>&1
echo '##########################################'

warnings_count=$(grep --count --perl-regexp '^  \d+:\d+-\d+:\d+\  \[33mwarning' < "$TMP_FILE")
if [[ warnings_count -gt 0 ]]; then
  return 1
fi
