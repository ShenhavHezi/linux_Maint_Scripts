#!/usr/bin/env bash
# linux_maint_conf.sh - config loader for linux-maint

# Loads config in this order (lowest to highest precedence):
#  1) /etc/linux_maint/linux-maint.conf
#  2) /etc/linux_maint/conf.d/*.conf (lexical order)
# Env vars override these (because they are already set before sourcing).

lm_load_main_conf(){
  local f="/etc/linux_maint/linux-maint.conf"
  [ -f "$f" ] || return 0
  # shellcheck disable=SC1090
  . "$f"
}

lm_load_conf_d(){
  local d="/etc/linux_maint/conf.d"
  [ -d "$d" ] || return 0
  local f
  shopt -s nullglob
  for f in "$d"/*.conf; do
    # shellcheck disable=SC1090
    . "$f"
  done
}

lm_load_config(){
  # best-effort; do not fail hard
  lm_load_main_conf || true
  lm_load_conf_d || true
}
