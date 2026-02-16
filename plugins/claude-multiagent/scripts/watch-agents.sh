#!/bin/bash
# Watches .agent-status.md and renders a pretty Unicode table
# Uses fswatch for efficient event-driven updates, falls back to polling

# Force UTF-8 for Unicode box-drawing characters
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

elapsed_since() {
  # Convert a unix timestamp to human-readable elapsed time
  local start="$1"
  if ! [[ "$start" =~ ^[0-9]+$ ]]; then
    echo "$start"  # Not a timestamp, return as-is
    return
  fi
  local now
  now=$(date +%s)
  local diff=$(( now - start ))
  if [ $diff -lt 60 ]; then
    echo "${diff}s"
  elif [ $diff -lt 3600 ]; then
    echo "$(( diff / 60 ))m $(( diff % 60 ))s"
  else
    echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m"
  fi
}

render_table() {
  local file="$1"
  local -a lines
  local -a widths
  local ncols=0
  local duration_col=-1

  # Read lines into array, resolve Duration column timestamps
  local line_idx=0
  while IFS= read -r line; do
    if [ $line_idx -eq 0 ]; then
      # Find which column is "Started" so we can convert timestamps
      IFS=$'\t' read -ra hdr <<< "$line"
      for ((c=0; c<${#hdr[@]}; c++)); do
        if [ "${hdr[$c]}" = "Started" ]; then
          duration_col=$c
        fi
      done
      # Rename "Started" to "Duration" for display
      line="${line/Started/Duration}"
    elif [ $duration_col -ge 0 ]; then
      # Replace the timestamp with elapsed time
      IFS=$'\t' read -ra cells <<< "$line"
      cells[$duration_col]=$(elapsed_since "${cells[$duration_col]}")
      # Rejoin with tabs
      local joined=""
      for ((c=0; c<${#cells[@]}; c++)); do
        [ $c -gt 0 ] && joined+=$'\t'
        joined+="${cells[$c]}"
      done
      line="$joined"
    fi
    lines+=("$line")
    ((line_idx++))
  done < "$file"

  [ ${#lines[@]} -eq 0 ] && return

  # Calculate column widths
  for line in "${lines[@]}"; do
    IFS=$'\t' read -ra cells <<< "$line"
    local i=0
    for cell in "${cells[@]}"; do
      local len=${#cell}
      if [ $i -ge $ncols ]; then
        ncols=$((i + 1))
        widths[$i]=0
      fi
      [ $len -gt ${widths[$i]:-0} ] && widths[$i]=$len
      ((i++))
    done
  done

  # Add padding
  for ((i=0; i<ncols; i++)); do
    widths[$i]=$(( ${widths[$i]} + 2 ))
  done

  # Build horizontal borders
  local top_border="┌"
  local mid_border="├"
  local bot_border="└"
  for ((i=0; i<ncols; i++)); do
    local w=${widths[$i]}
    local bar=""
    for ((j=0; j<w; j++)); do bar+="─"; done
    if [ $i -lt $((ncols-1)) ]; then
      top_border+="${bar}┬"
      mid_border+="${bar}┼"
      bot_border+="${bar}┴"
    else
      top_border+="${bar}┐"
      mid_border+="${bar}┤"
      bot_border+="${bar}┘"
    fi
  done

  # Print top border
  echo "$top_border"

  # Print rows
  local row_idx=0
  for line in "${lines[@]}"; do
    IFS=$'\t' read -ra cells <<< "$line"
    local row="│"
    for ((i=0; i<ncols; i++)); do
      local cell="${cells[$i]:-}"
      local w=${widths[$i]}
      local len=${#cell}
      if [ $row_idx -eq 0 ]; then
        # Center-align headers
        local pad=$(( (w - len) / 2 ))
        local rpad=$(( w - len - pad ))
        local lspaces="" rspaces=""
        for ((j=0; j<pad; j++)); do lspaces+=" "; done
        for ((j=0; j<rpad; j++)); do rspaces+=" "; done
        row+="${lspaces}${cell}${rspaces}│"
      else
        # Left-align data with 1 space padding
        local rpad=$(( w - len - 1 ))
        local rspaces=""
        for ((j=0; j<rpad; j++)); do rspaces+=" "; done
        row+=" ${cell}${rspaces}│"
      fi
    done
    echo "$row"
    # Print separator after header
    if [ $row_idx -eq 0 ]; then
      echo "$mid_border"
    fi
    ((row_idx++))
  done

  # Print bottom border
  echo "$bot_border"
}

resolve_status_file() {
  if [ -f ".agent-status.md" ]; then
    echo ".agent-status.md"
  elif [ -f "$HOME/.claude/agent-status.md" ]; then
    echo "$HOME/.claude/agent-status.md"
  fi
}

render_screen() {
  clear
  local status_file
  status_file=$(resolve_status_file)
  echo "⚡ Agent Status"
  echo ""
  if [ -n "$status_file" ] && [ -f "$status_file" ]; then
    render_table "$status_file"
  else
    echo "  No agents running."
  fi
  echo ""
  echo "↻ $(date '+%H:%M:%S')"
}

# Initial render
render_screen

if command -v fswatch &>/dev/null; then
  # Event-driven: watch both possible locations, re-render on change
  # --latency 0.3: debounce rapid writes (e.g. printf > file)
  # --one-per-batch: single event per batch of changes
  fswatch --latency 0.3 --one-per-batch \
    ".agent-status.md" "$HOME/.claude/agent-status.md" 2>/dev/null \
  | while read -r _; do
    render_screen
  done
  # fswatch exited (e.g. neither file exists yet) -- fall through to polling
fi

# Fallback: poll every 5s (also used while waiting for status file to appear)
while true; do
  sleep 5
  render_screen
done
