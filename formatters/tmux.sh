#!/usr/bin/env bash

formatter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$formatter_dir/plain.sh" --surface tmux "$@"
