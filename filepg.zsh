#!/usr/bin/env zsh
# filepg.zsh - File operations with progress bar for zsh
# GitHub: https://github.com/2O48/zsh-filepg
# Author: 2O48
# License: MIT

setopt extended_glob
setopt no_nomatch
setopt mark_dirs

# ================================
# 🔧 Completion System Initialization
# ================================
if [[ -o interactive ]]; then
  autoload -Uz compinit
  if [[ ! -f ~/.zcompdump || $(( $(date +%s) - $(stat -c %Y ~/.zcompdump 2>/dev/null || echo 0) )) -gt 86400 ]]; then
    compinit
  fi
fi

# -------------------------------
# Utility: Format size (B, K, M, G)
# -------------------------------
_human_size() {
  local size=$1
  if [[ $size -lt 1024 ]]; then
    echo "${size}B"
  elif [[ $size -lt $((1024**2)) ]]; then
    echo "$((size/1024))K"
  elif [[ $size -lt $((1024**3)) ]]; then
    echo "$((size/(1024**2)))M"
  else
    echo "$((size/(1024**3)))G"
  fi
}

# -------------------------------
# Draw progress bar
# -------------------------------
_draw_progress() {
  local done=$1 total=$2 elapsed=$3
  [[ $total -eq 0 ]] && total=1

  local percent=$(( done * 100 / total ))
  local bar_width=50
  local filled=$(( percent * bar_width / 100 ))
  local empty=$(( bar_width - filled ))

  local bar="["
  bar+=$(printf "%0.s=" $(seq 1 $filled) 2>/dev/null || yes = | head -n $filled)
  bar+=$(printf "%0.s " $(seq 1 $empty) 2>/dev/null || yes " " | head -n $empty)
  bar+="]"

  local remain_sec=0
  if (( done > 0 )); then
    remain_sec=$(( (total - done) * elapsed / done ))
  fi

  local eta_hms=$(printf "%02d:%02d:%02d" \
    $((remain_sec / 3600)) \
    $(((remain_sec % 3600) / 60)) \
    $((remain_sec % 60)))

  printf "\r%s %3d%% %s/%s ETA %s" \
    "$bar" "$percent" \
    "$(_human_size $done)" \
    "$(_human_size $total)" \
    "$eta_hms"
}

# -------------------------------
# Parse arguments: --x=, -t, --x
# -------------------------------
_parse_args() {
  DRY_RUN=0
  typeset -ga _PX_EXCLUDES=() _PX_ARGS=()
  local i=0
  while (( i < $# )); do
    local arg="${@[i+1]}"
    case "$arg" in
      --test|-t)
        DRY_RUN=1
        ;;
      --x=*)
        local exlist="${arg#--x=}"
        [[ -n "$exlist" ]] && _PX_EXCLUDES+=("${=exlist}")
        ;;
      --x)
        (( ++i )) && [[ $i -lt $# ]] && _PX_EXCLUDES+=("${@[i+1]}")
        ;;
      *)
        _PX_ARGS+=("$arg")
        ;;
    esac
    (( ++i ))
  done
}

# -------------------------------
# Expand glob patterns safely
# -------------------------------
_expand_glob() {
  local pattern="$1"
  setopt local_options extended_glob
  unsetopt nomatch
  if [[ "$pattern" == *[*?[]* ]]; then
    local files=(${(~)pattern}(N))
    print -l ${files}
  else
    [[ -e "$pattern" ]] && echo "$pattern"
  fi
}

# -------------------------------
# Check if sudo is needed
# -------------------------------
_need_sudo() {
  for p in "$@"; do
    local d="$p"
    [[ -d "$p" || ! -e "$p" ]] && d="$(dirname "$p")"
    [[ -w "$d" ]] || return 0
  done
  return 1
}

# -------------------------------
# Run command safely (dry-run support)
# -------------------------------
_run() {
  if (( DRY_RUN )); then
    printf '[DRY-RUN] %s\n' "$*"
    return 0
  fi

  "$@"
  local exit_status=$?

  case "${1}" in
    rm|rmdir|find) return 0 ;;
    *) return $exit_status ;;
  esac
}

# -------------------------------
# Calculate total size (macOS/Linux compatible)
# -------------------------------
_calculate_total_size() {
  local total=0
  for file in "$@"; do
    [[ ! -e "$file" ]] && continue
    local size=0
    if [[ -f "$file" ]]; then
      size=$(command stat -f%z "$file" 2>/dev/null || command stat -c%s "$file" 2>/dev/null || echo 0)
    elif [[ -d "$file" ]]; then
      size=$(du -k "$file" 2>/dev/null | awk '{total += $1} END {print (total+0)*1024}')
    fi
    total=$(( total + size ))
  done
  echo $total
}

# -------------------------------
# Get target size (macOS/Linux compatible)
# -------------------------------
_get_target_size() {
  local target="$1"
  if [[ -f "$target" ]]; then
    command stat -f%z "$target" 2>/dev/null || command stat -c%s "$target" 2>/dev/null || echo 0
  elif [[ -d "$target" ]]; then
    du -k "$target" 2>/dev/null | awk '{total += $1} END {print (total+0)*1024}'
  else
    echo 0
  fi
}

# -------------------------------
# Execute batch operation with progress
# -------------------------------
_execute_batch_operation() {
  setopt local_options no_notify no_monitor

  local operation="$1"
  local dst="$2"
  shift 2

  # Now $@ is the complete rsync options + -- + source file
  local full_rsync_args=("$@")
  local sources=()
  local i=0
  # Extract the source files after --
  while (( i < $# )); do
    if [[ "${@[i+1]}" == "--" ]]; then
      sources=("${@[i+2,-1]}")
      break
    fi
    ((i++))
  done

  [[ ${#sources[@]} -eq 0 ]] && return 0

  local total_size=$(_calculate_total_size "${sources[@]}")
  [[ $total_size -eq 0 ]] && return 0

  local start_time=$(date +%s)
  local prev_size=0
  local _sudo=()

  _need_sudo "$dst" && { sudo -v || return 1; _sudo=(sudo); }

  if (( DRY_RUN )); then
    printf '[DRY-RUN] %s rsync %s %s/\n' "${_sudo[*]}" "${full_rsync_args[*]}" "$dst"
    for ((i=1; i<=100; i++)); do
      local s=$(( total_size * i / 100 ))
      local t=$(( $(date +%s) - start_time ))
      _draw_progress $s $total_size $t
      sleep 0.05
    done
    echo
    return 0
  fi

  # ✅ Correct call: sudo rsync [options] --sources... dst/
  "${_sudo[@]}" rsync "${rsync_opts[@]}" -- "${sources[@]}" "$dst/" &
  local pid=$!

  while kill -0 $pid 2>/dev/null; do
    local current=0
    for src in "${sources[@]}"; do
      local target="$dst/${src##*/}"
      current=$(( current + $(_get_target_size "$target") ))
    done

    if (( current != prev_size )); then
      local elapsed=$(( $(date +%s) - start_time ))
      _draw_progress $current $total_size $elapsed
      prev_size=$current
    fi

    sleep 0.3
  done

  wait $pid
  local result=$?

  local elapsed=$(( $(date +%s) - start_time ))
  _draw_progress $total_size $total_size $elapsed
  echo

  # Clean up source files after moving
  if [[ "$operation" == "move" && $DRY_RUN -eq 0 && $result -eq 0 ]]; then
    for src in "${sources[@]}"; do
      [[ -d "$src" ]] && _run find "$src" -type d -empty -delete 2>/dev/null
      [[ -f "$src" && -e "$src" ]] && _run rm -f -- "$src" 2>/dev/null
    done
  fi

  return $result
}

# -------------------------------
# Base function for cp/mv
# -------------------------------
_cpmv_base() {
  local operation="$1"
  shift

  _parse_args "$@"
  local excludes=("${_PX_EXCLUDES[@]}")
  local args=("${_PX_ARGS[@]}")

  (( ${#args[@]} < 2 )) && {
    if [[ "$operation" == "copy" ]]; then
      echo "Usage: cppg [--x=\"...\"] [-t|--test] <source...> <destination>"
    else
      echo "Usage: mvpg [--x=\"...\"] [-t|--test] <source...> <destination>"
    fi
    return 1
  }

  local dst="${args[-1]}"
  local sources=("${args[@]:0:-1}")
  local all_sources=()

  for src in "${sources[@]}"; do
    local matches=("${(@f)$(_expand_glob "$src")}")
    for f in "${matches[@]}"; do
      [[ -e "$f" ]] && all_sources+=("$f")
    done
  done

  (( ${#all_sources[@]} == 0 )) && { echo "No matching files found"; return 1; }

  local filtered=()
  for f in "${all_sources[@]}"; do
    local matched=0
    for e in "${excludes[@]}"; do
      if [[ "$e" == *[*?[]* ]]; then
        [[ "$f" == ${~e} ]] && matched=1 && break
      else
        [[ "$f" = "$e" ]] && matched=1 && break
      fi
    done
    (( matched == 0 )) && filtered+=("$f")
  done

  (( ${#filtered[@]} == 0 )) && { echo "No files to process (all excluded)"; return 0; }

  if (( DRY_RUN )); then
    local verb="$([[ "$operation" == "copy" ]] && echo "Copy" || echo "Move")"
    echo "Will $verb the following:"
    local total_size=0
    for f in "${filtered[@]}"; do
      local sz=$(_get_target_size "$f")
      sz=${sz:-0}
      total_size=$(( total_size + sz ))
      local type="$([[ -f "$f" ]] && echo "File" || echo "Dir")"
      printf "(%s) %s -> %s (%s)\n" "$type" "$f" "$dst" "$(_human_size $sz)"
    done
    echo "Total: $(_human_size $total_size)"
    return 0
  fi

  # Building the rsync command
  local rsync_cmd=(-aHAX --partial --inplace)
  for e in "${excludes[@]}"; do
    rsync_cmd+=(--exclude="$e")
  done
  if [[ "$operation" == "move" ]]; then
    rsync_cmd+=(--remove-source-files)
  fi

  # Directly call _execute_batch_operation and pass in the complete command structure
  _execute_batch_operation "$operation" "$dst" "${rsync_cmd[@]}" -- "${filtered[@]}"
}

# -------------------------------
# cppg: Copy with progress
# -------------------------------
cppg() {
  _cpmv_base "copy" "$@"
}

# -------------------------------
# mvpg: Move with progress
# -------------------------------
mvpg() {
  _cpmv_base "move" "$@"
}

# -------------------------------
# rmpg: Remove with progress and confirmation
# -------------------------------
rmpg() {
  _parse_args "$@"
  local args=("${_PX_ARGS[@]}")
  (( ${#args[@]} == 0 )) && { echo "Usage: rmpg [--x=\"...\"] [-t|--test] <files...>"; return 1; }

  local excludes=("${_PX_EXCLUDES[@]}")
  local all_targets=()

  for pattern in "${args[@]}"; do
    local matches=("${(@f)$(_expand_glob "$pattern")}")
    for f in "${matches[@]}"; do
      [[ -e "$f" ]] && all_targets+=("$f")
    done
  done

  all_targets=(${(u)all_targets})

  local filtered=()
  for f in "${all_targets[@]}"; do
    local matched=0
    for e in "${excludes[@]}"; do
      if [[ "$e" == *[*?[]* ]]; then
        [[ "$f" == ${~e} ]] && matched=1 && break
      else
        [[ "$f" = "$e" ]] && matched=1 && break
      fi
    done
    (( matched == 0 )) && filtered+=("$f")
  done

  (( ${#filtered[@]} == 0 )) && { echo "No files to delete (all excluded)"; return 0; }

  if (( DRY_RUN )); then
    echo "Preview (dry-run):"
    local total_size=0
    for f in "${filtered[@]}"; do
      local sz=$(_get_target_size "$f")
      sz=${sz:-0}
      total_size=$(( total_size + sz ))
      local type="$([[ -f "$f" ]] && echo "File" || echo "Dir")"
      printf "(%s) %s (%s)\n" "$type" "$f" "$(_human_size $sz)"
    done
    echo "Total: $(_human_size $total_size)"
    return 0
  fi

  echo "Will Delete the following:"
  local total_size=0
  local file_sizes=()
  for f in "${filtered[@]}"; do
    local sz=$(_get_target_size "$f")
    sz=${sz:-0}
    file_sizes+=("$sz")
    total_size=$(( total_size + sz ))
    local type="$([[ -f "$f" ]] && echo "File" || echo "Dir")"
    printf "(%s) %s (%s)\n" "$type" "$f" "$(_human_size $sz)"
  done
  echo "Total: $(_human_size $total_size)"

  read "confirm?Confirm deletion? [y/N]: "
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Cancelled"; return 0; }

  local deleted=0 start=$(date +%s)
  local _sudo=()
  local i=0
  for f in "${filtered[@]}"; do
    local sz=${file_sizes[i]}
    deleted=$(( deleted + sz ))
    _need_sudo "$f" && [[ ${#_sudo[@]} -eq 0 ]] && { sudo -v; _sudo=(sudo); }
    if [[ -f "$f" ]]; then
      _run "${_sudo[@]}" rm -f -- "$f"
    elif [[ -d "$f" ]]; then
      _run "${_sudo[@]}" rm -rf -- "$f"
    fi
    local elapsed=$(( $(date +%s) - start ))
    _draw_progress $deleted $total_size $elapsed
    ((i++))
  done

  local elapsed=$(( $(date +%s) - start ))
  _draw_progress $total_size $total_size $elapsed
  echo
}

# -------------------------------
# Completion for --x=
# -------------------------------
_x_complete() {
  local cur context state line
  cur="${words[CURRENT]}"

  if [[ "$cur" != --x=* ]]; then
    _files -/
    return
  fi

  local raw="${cur#--x=}"
  local dir="." prefix=""

  if [[ "$raw" == */* ]]; then
    dir="${raw%/*}"
    prefix="${raw##*/}"
    dir="${dir/#~/$HOME}"
  else
    prefix="$raw"
  fi

  if [[ -d "$dir" ]]; then
    dir="$(cd -q "$dir" && pwd)"
  else
    _files -/
    return
  fi

  local -a matches
  for file in "$dir"/* "$dir"/.*; do
    [[ -e "$file" ]] || continue
    local fname="${file##*/}"
    [[ "$fname" == .* ]] && [[ "$fname" == "." || "$fname" == ".." ]] && continue
    [[ "$fname" == "$prefix"* ]] && matches+=("$fname")
  done

  (( ${#matches[@]} == 0 )) && return 1

  local prefix_str="--x="
  if [[ "$raw" == */* ]]; then
    prefix_str="--x=${raw%/*}/"
  fi

  compadd -U -Q -S '' -p "$prefix_str" -- "${matches[@]}"
}

# -------------------------------
# Register completion
# -------------------------------
if [[ -o interactive ]] && (( ${+functions[_x_complete]} )); then
  compdef _x_complete cppg mvpg rmpg
fi