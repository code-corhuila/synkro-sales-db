#!/usr/bin/env bash
# Check status as well as assertion output, even in conditional shell functions.
no_fail_lines() {
  local out status=0
  out=$("$@" 2>&1) || status=$?
  printf '%s\n' "$out"
  [[ $status -eq 0 ]] || return "$status"
  ! grep -q '^FAIL' <<< "$out"
}
