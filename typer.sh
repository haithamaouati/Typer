#!/usr/bin/env bash
#
# Typer - terminal typing practice
# Author: Haitham Aouati
# GitHub: github.com/haithamaouati
#
# Requirements: bash >= 4.0, coreutils (stty, date, sleep). No bc/pv needed.

set -euo pipefail

# --- Preconditions ----------------------------------------------------------
if (( BASH_VERSINFO[0] < 4 )); then
  printf 'Error: bash 4.0 or newer is required.\n' >&2
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  printf 'Error: this program must be run in an interactive terminal.\n' >&2
  exit 1
fi

# --- Colors & styles (real escape bytes, printed with printf '%s') ----------
readonly CLR_RESET=$'\e[0m'
readonly CLR_GREY=$'\e[90m'
readonly CLR_WHITE=$'\e[97m'
readonly CLR_RED=$'\e[31m'
readonly CLR_GREEN=$'\e[32m'
readonly STYLE_UNDERLINE=$'\e[4m'
readonly HIDE_CURSOR=$'\e[?25l'
readonly SHOW_CURSOR=$'\e[?25h'
readonly CLEAR_LINE=$'\r\e[2K'

# --- Lessons ----------------------------------------------------------------
readonly LESSONS=(
  "the quick brown fox jumps over the lazy dog"
  "bash scripting teaches patience and precision"
  "speed without accuracy is just noise"
)

lesson=${LESSONS[RANDOM % ${#LESSONS[@]}]}
len=${#lesson}

# --- Session stats ----------------------------------------------------------
typed=""
pos=0
correct=0
errors=0
start_ms=0      # set on the first keystroke, not at launch
aborted=0

# --- Terminal state handling ------------------------------------------------
TTY_STATE=""

cleanup() {
  # Restore the exact terminal settings the user had before we started.
  if [[ -n $TTY_STATE ]]; then
    stty "$TTY_STATE" 2>/dev/null || stty sane 2>/dev/null || true
  fi
  printf '%s%s' "$CLR_RESET" "$SHOW_CURSOR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# --- Helpers ----------------------------------------------------------------

# Current time in milliseconds (uses EPOCHREALTIME on Bash 5+, else GNU date).
now_ms() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local t=${EPOCHREALTIME//[.,]/}   # microseconds; tolerate locale decimal comma
    printf '%s' "$(( 10#$t / 1000 ))"
  else
    printf '%s' "$(( $(date +%s%N) / 1000000 ))"
  fi
}

# fmt2 <value_x100> <varname>: store "int.dd" (fixed-point, 2 decimals) in varname.
fmt2() {
  printf -v "$2" '%d.%02d' "$(( $1 / 100 ))" "$(( $1 % 100 ))"
}

# Pure-bash typewriter effect (replaces `pv -qL`).
typewriter() {
  local text=$1 delay=${2:-0.02} i
  for (( i = 0; i < ${#text}; i++ )); do
    printf '%s' "${text:i:1}"
    sleep "$delay"
  done
  printf '\n'
}

banner() {
  printf '\e[2J\e[H'   # clear screen without depending on $TERM/terminfo
  cat <<'EOF'
 _____
|_   _|_ _ ___ ___ ___
  | | | | | . | -_|  _|
  |_| |_  |  _|___|_|
      |___|_|
EOF
  printf '\n'
  typewriter "Typing practice lessons to improve your speed and accuracy."
  printf '\n Author: Haitham Aouati\n'
  printf ' GitHub: %sgithub.com/haithamaouati%s\n\n' "$STYLE_UNDERLINE" "$CLR_RESET"
}

# Draw the lesson: grey = untyped, white = correct, red = wrong, underline = cursor.
render() {
  local buf=$CLEAR_LINE i char style color
  for (( i = 0; i < len; i++ )); do
    char=${lesson:i:1}
    style=""
    if (( i == pos )); then
      style=$STYLE_UNDERLINE
    fi

    if (( i >= ${#typed} )); then
      color=$CLR_GREY
    elif [[ ${typed:i:1} == "$char" ]]; then
      color=$CLR_WHITE
    else
      color=$CLR_RED
    fi
    buf+="${style}${color}${char}${CLR_RESET}"
  done
  printf '%s' "$buf"
}

# Final (non-interactive) rendering of the lesson after a finished session.
render_final() {
  local buf=$CLEAR_LINE i char
  if (( errors == 0 )); then
    buf+="${CLR_GREEN}${lesson}${CLR_RESET}"
  else
    for (( i = 0; i < len; i++ )); do
      char=${lesson:i:1}
      if [[ ${typed:i:1} == "$char" ]]; then
        buf+="${CLR_WHITE}${char}${CLR_RESET}"
      else
        buf+="${CLR_RED}${char}${CLR_RESET}"
      fi
    done
  fi
  printf '%s\n' "$buf"
}

# --- Start ------------------------------------------------------------------
banner

# Discard anything typed while the banner was animating.
while IFS= read -rsn1 -t 0.01 _; do :; done

TTY_STATE=$(stty -g)
stty -echo -icanon time 0 min 1
printf '%s' "$HIDE_CURSOR"

printf 'Type the following (ESC to quit):\n\n'
render

# --- Typing loop ------------------------------------------------------------
while (( pos < len )); do
  # If stdin closes (EOF/hangup), treat it as an abort instead of spinning.
  if ! IFS= read -rsn1 key; then
    aborted=1
    break
  fi

  # ESC: a bare ESC quits; ESC followed by more bytes (arrows, Alt+key) is ignored.
  if [[ $key == $'\e' ]]; then
    if IFS= read -rsn1 -t 0.05 _; then
      while IFS= read -rsn1 -t 0.005 _; do :; done   # drain the rest of the sequence
      continue
    fi
    aborted=1
    break
  fi

  if [[ $key == $'\x7f' || $key == $'\b' ]]; then
    # Backspace: undo the last character and its score
    if (( pos > 0 )); then
      last_char=${typed:pos-1:1}
      typed=${typed%?}
      pos=$(( pos - 1 ))
      if [[ $last_char == "${lesson:pos:1}" ]]; then
        correct=$(( correct - 1 ))
      else
        errors=$(( errors - 1 ))
      fi
    fi
  elif [[ -n $key && $key == [[:print:]] ]]; then
    # Start the clock on the first real keystroke
    if (( start_ms == 0 )); then
      start_ms=$(now_ms)
    fi
    expected=${lesson:pos:1}
    typed+=$key
    pos=$(( pos + 1 ))
    if [[ $key == "$expected" ]]; then
      correct=$(( correct + 1 ))
    else
      errors=$(( errors + 1 ))
    fi
  fi

  render
done

# --- Final stats (integer math only, no bc) ---------------------------------
elapsed_ms=0
if (( start_ms > 0 )); then
  elapsed_ms=$(( $(now_ms) - start_ms ))
fi

typed_total=$(( correct + errors ))

accuracy_x100=0
if (( typed_total > 0 )); then
  accuracy_x100=$(( correct * 10000 / typed_total ))
fi

# Net WPM = (correct chars / 5) per minute = correct * 12000 / elapsed_ms
wpm_x100=0
if (( elapsed_ms > 0 )); then
  wpm_x100=$(( correct * 1200000 / elapsed_ms ))
fi

fmt2 $(( elapsed_ms / 10 )) elapsed_fmt
fmt2 "$accuracy_x100"       accuracy_fmt
fmt2 "$wpm_x100"            wpm_fmt

# --- Report -----------------------------------------------------------------
if (( aborted )); then
  printf '%s%s%s%s\n' "$CLEAR_LINE" "$CLR_RED" "$lesson" "$CLR_RESET"
  printf '\nSession Aborted!\n'
else
  render_final
  printf '\nSession Complete!\n'
fi

printf 'Total Time: %ss\n'    "$elapsed_fmt"
printf 'Total Correct: %s%d%s\n' "$CLR_GREEN" "$correct" "$CLR_RESET"
printf 'Total Errors: %s%d%s\n'  "$CLR_RED"   "$errors"  "$CLR_RESET"
printf 'Accuracy: %s%%\n'     "$accuracy_fmt"
printf 'WPM: %s\n'            "$wpm_fmt"
