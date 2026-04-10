#!/usr/bin/env bash
# Session-scoped counters for threshold-based hook behavior.
# Usage: source "scripts/hooks/lib/session-counters.sh"

_SESSION_COUNTER_FILE="/tmp/archetype-session-counters-${SESSION_ID:-${PPID:-$$}}.json"

# Increment a counter by 1, returns the new value.
session_counter_increment() {
  local key="${1:?session_counter_increment requires a key}"
  local current=0

  if [[ -f "$_SESSION_COUNTER_FILE" ]]; then
    current="$(jq -r --arg k "$key" '.[$k] // 0' "$_SESSION_COUNTER_FILE" 2>/dev/null || echo "0")"
  fi

  local new_val=$((current + 1))

  if [[ -f "$_SESSION_COUNTER_FILE" ]]; then
    local tmp
    tmp="$(jq --arg k "$key" --argjson v "$new_val" '.[$k] = $v' "$_SESSION_COUNTER_FILE" 2>/dev/null)" || tmp="{\"$key\":$new_val}"
    echo "$tmp" > "$_SESSION_COUNTER_FILE"
  else
    echo "{\"$key\":$new_val}" > "$_SESSION_COUNTER_FILE"
  fi

  echo "$new_val"
}

# Get a counter's current value (0 if not set).
session_counter_get() {
  local key="${1:?session_counter_get requires a key}"

  if [[ -f "$_SESSION_COUNTER_FILE" ]]; then
    jq -r --arg k "$key" '.[$k] // 0' "$_SESSION_COUNTER_FILE" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}
