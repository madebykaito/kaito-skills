# Sourced by writers of the project memory files. Do not reuse an old lock
# based on elapsed time: its writer may still be inside a slow filesystem call.
memory_unlock() {
  [ "$(cat "$memory_lock_dir/owner" 2>/dev/null)" = "$$" ] || return 0
  rm "$memory_lock_dir/owner" && rmdir "$memory_lock_dir"
}

memory_lock() {
  [ -w "$1" ] || return 73
  memory_lock_dir="$1/.lock"
  memory_lock_wait=0
  until mkdir "$memory_lock_dir" 2>/dev/null; do
    [ -w "$1" ] || return 73
    [ -e "$memory_lock_dir" ] || [ -d "$1" ] || return 1
    memory_lock_wait=$((memory_lock_wait + 1))
    [ "$memory_lock_wait" -lt 21 ] || return 74
    sleep 0.1
  done
  if ! printf '%s\n' "$$" > "$memory_lock_dir/owner"; then
    rm -f "$memory_lock_dir/owner"
    rmdir "$memory_lock_dir"
    return 1
  fi
  trap 'memory_unlock || :' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}
