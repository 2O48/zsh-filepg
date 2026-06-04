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
  (( done < 0 )) && done=0
  (( done > total )) && done=$total

  local percent=$(( done * 100 / total ))
  local remain_sec=0
  if (( done > 0 )); then
    remain_sec=$(( (total - done) * elapsed / done ))
  fi

  local eta_hms=$(printf "%02d:%02d:%02d" \
    $((remain_sec / 3600)) \
    $(((remain_sec % 3600) / 60)) \
    $((remain_sec % 60)))

  local done_human="$(_human_size $done)"
  local total_human="$(_human_size $total)"
  local progress_text=$(printf " %3d%% %s/%s ETA %s" \
    "$percent" "$done_human" "$total_human" "$eta_hms")

  local columns=${COLUMNS:-80}
  local bar_width=$(( columns - ${#progress_text} - 2 ))
  (( bar_width > 50 )) && bar_width=50
  (( bar_width < 10 )) && bar_width=10

  local filled=$(( percent * bar_width / 100 ))
  local empty=$(( bar_width - filled ))

  local bar="["
  bar+=$(printf "%0.s=" $(seq 1 $filled) 2>/dev/null || yes = | head -n $filled)
  bar+=$(printf "%0.s " $(seq 1 $empty) 2>/dev/null || yes " " | head -n $empty)
  bar+="]"

  printf "\r\033[2K%s%s" "$bar" "$progress_text" >&2
}

_finish_progress() {
  printf "\n" >&2
}

# -------------------------------
# Store original patterns without pre-processing
# -------------------------------
_auto_escape_pattern() {
  local pattern="$1"
  echo "$pattern"
}

# -------------------------------
# Parse arguments: only --x=... allowed, no bare --x
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
        local ex="${arg#--x=}"
        if [[ -n "$ex" ]]; then
          # Auto-escape the pattern
          local escaped_pattern=$(_auto_escape_pattern "$ex")
          _PX_EXCLUDES+=("$escaped_pattern")
        fi
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
# Resolve where a copied/moved source will appear
# -------------------------------
_operation_target_path() {
  local src="$1" dst="$2" source_count="$3"
  if (( source_count == 1 )) && [[ ! -d "$dst" ]]; then
    echo "$dst"
  else
    echo "$dst/${src##*/}"
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

  # Now $@ is the complete rsync options + -- + source files
  local rsync_opts=()
  local sources=()
  local seen_separator=0
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--" && $seen_separator -eq 0 ]]; then
      seen_separator=1
      continue
    fi
    if (( seen_separator )); then
      sources+=("$arg")
    else
      rsync_opts+=("$arg")
    fi
  done

  [[ ${#sources[@]} -eq 0 ]] && return 0

  local total_size=$(_calculate_total_size "${sources[@]}")
  [[ $total_size -eq 0 ]] && return 0

  local start_time=$(date +%s)
  local prev_size=0
  local _sudo=()

  _need_sudo "$dst" && { sudo -v || return 1; _sudo=(sudo); }

  local source_count=${#sources[@]}
  local target_paths=()
  local target_baselines=()
  local src target
  for src in "${sources[@]}"; do
    target="$(_operation_target_path "$src" "$dst" "$source_count")"
    target_paths+=("$target")
    target_baselines+=("$(_get_target_size "$target")")
  done

  local rsync_dst="$dst/"
  if (( source_count == 1 )) && [[ ! -d "$dst" ]]; then
    rsync_dst="$dst"
  fi

  if (( DRY_RUN )); then
    printf '[DRY-RUN] %s rsync %s -- %s %s\n' "${_sudo[*]}" "${rsync_opts[*]}" "${sources[*]}" "$rsync_dst"
    local step
    for step in {1..100}; do
      local s=$(( total_size * step / 100 ))
      local t=$(( $(date +%s) - start_time ))
      _draw_progress $s $total_size $t
      sleep 0.05
    done
    _finish_progress
    return 0
  fi

  "${_sudo[@]}" rsync "${rsync_opts[@]}" -- "${sources[@]}" "$rsync_dst" &
  local pid=$!

  while kill -0 $pid 2>/dev/null; do
    local current=0
    local pending_targets=("${target_paths[@]}")
    local pending_baselines=("${target_baselines[@]}")
    while (( ${#pending_targets[@]} > 0 )); do
      local current_target_size=$(_get_target_size "${pending_targets[1]}")
      local delta=$(( current_target_size - pending_baselines[1] ))
      (( delta < 0 )) && delta=0
      current=$(( current + delta ))
      shift pending_targets
      shift pending_baselines
    done
    (( current > total_size )) && current=$total_size

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
  _finish_progress

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

  # Filter files based on exclude patterns
  local filtered=()
  for f in "${all_sources[@]}"; do
    local matched=0
    local fname="${f##*/}"
    for original_pattern in "${excludes[@]}"; do
      # Real-time escape user provided patterns
      local working_pattern="$original_pattern"
      working_pattern="${working_pattern//\\/\\\\}"  # \ -> \\
      working_pattern="${working_pattern//\(/\(}"    # ( -> \(
      working_pattern="${working_pattern//\)/\)}"    # ) -> \)
      working_pattern="${working_pattern//\[/\[}"    # [ -> \[
      working_pattern="${working_pattern//\]/\]}"    # ] -> \]
      working_pattern="${working_pattern//\{/\\\{}"   # { -> \{
      working_pattern="${working_pattern//\}/\\\}}"   # } -> \}
      working_pattern="${working_pattern//\|/\\|}"   # | -> \|
      working_pattern="${working_pattern//\~/\\~}"   # ~ -> \~
      working_pattern="${working_pattern//\^/\\^}"   # ^ -> \^
      working_pattern="${working_pattern//\$/\\\$}"  # $ -> \$
      working_pattern="${working_pattern//\`/\\\`}"  # ` -> \`
      working_pattern="${working_pattern// /\\ }"    # space -> \space
      working_pattern="${working_pattern//\"/\\\"}"  # " -> \"
      working_pattern="${working_pattern//\'/\\\'}"  # ' -> \'
      # Note: * and ? are preserved as glob wildcards
      
      # Use eval for safe pattern matching
      local eval_string="[[ '$fname' == $working_pattern ]]"
      if eval "$eval_string" 2>/dev/null; then
        matched=1
        break
      fi
    done
    if (( matched == 0 )); then
      filtered+=("$f")
    fi
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

  local rsync_cmd=(-aHAX --partial --inplace)
  for e in "${excludes[@]}"; do
    rsync_cmd+=(--exclude="$e")  # rsync natively uses glob patterns
  done
  if [[ "$operation" == "move" ]]; then
    rsync_cmd+=(--remove-source-files)
  fi

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
# Build a recursive delete plan
# -------------------------------
_collect_delete_plan() {
  typeset -ga _DELETE_FILES=() _DELETE_SIZES=() _DELETE_DIRS=()
  local f item
  local find_cmd=(find)
  (( ${#_sudo[@]} > 0 )) && find_cmd=("${_sudo[@]}" find)

  for f in "$@"; do
    if [[ -L "$f" || -f "$f" ]]; then
      _DELETE_FILES+=("$f")
      _DELETE_SIZES+=("$(_get_target_size "$f")")
    elif [[ -d "$f" ]]; then
      while IFS= read -r -d $'\0' item; do
        _DELETE_FILES+=("$item")
        _DELETE_SIZES+=("$(_get_target_size "$item")")
      done < <("${find_cmd[@]}" "$f" \( -type f -o -type l \) -print0 2>/dev/null)

      while IFS= read -r -d $'\0' item; do
        _DELETE_DIRS+=("$item")
      done < <("${find_cmd[@]}" "$f" -depth -type d -print0 2>/dev/null)
    fi
  done
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

  # Filter files based on exclude patterns (same logic as _cpmv_base)
  local filtered=()
  for f in "${all_targets[@]}"; do
    local matched=0
    local fname="${f##*/}"
    for original_pattern in "${excludes[@]}"; do
      # Real-time escape user provided patterns
      local working_pattern="$original_pattern"
      working_pattern="${working_pattern//\(/\(}"
      working_pattern="${working_pattern//\)/\)}"
      working_pattern="${working_pattern// /\\ }"
      
      # Use eval for safe pattern matching
      local eval_string="[[ '$fname' == $working_pattern ]]"
      if eval "$eval_string" 2>/dev/null; then
        matched=1
        break
      fi
    done
    if (( matched == 0 )); then
      filtered+=("$f")
    fi
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

  local _sudo=()
  for f in "${filtered[@]}"; do
    _need_sudo "$f" && [[ ${#_sudo[@]} -eq 0 ]] && { sudo -v; _sudo=(sudo); }
  done

  _collect_delete_plan "${filtered[@]}"

  local deleted=0 start=$(date +%s)
  _draw_progress 0 $total_size 0

  local pending_delete_files=("${_DELETE_FILES[@]}")
  local pending_delete_sizes=("${_DELETE_SIZES[@]}")
  while (( ${#pending_delete_files[@]} > 0 )); do
    local sz=${pending_delete_sizes[1]:-0}
    _run "${_sudo[@]}" rm -f -- "${pending_delete_files[1]}"
    deleted=$(( deleted + sz ))
    local elapsed=$(( $(date +%s) - start ))
    _draw_progress $deleted $total_size $elapsed
    shift pending_delete_files
    shift pending_delete_sizes
  done

  for f in "${_DELETE_DIRS[@]}"; do
    _run "${_sudo[@]}" rmdir -- "$f" 2>/dev/null
  done

  local elapsed=$(( $(date +%s) - start ))
  _draw_progress $total_size $total_size $elapsed
  _finish_progress
}
