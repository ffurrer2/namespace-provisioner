#!/bin/bash
# SPDX-License-Identifier: MIT
set -e

golangci-lint run --verbose --no-config --issues-exit-code 0 ./... 1>&2
