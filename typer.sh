#!/bin/bash

# Author: Haitham Aouati
# GitHub: github.com/haithamaouati

# Colors & styles
CLR_RESET="\e[0m"
CLR_GREY="\e[90m"
CLR_WHITE="\e[97m"
CLR_RED="\e[31m"
CLR_GREEN="\e[32m"
STYLE_UNDERLINE="\e[4m"
HIDE_CURSOR="\e[?25l"
SHOW_CURSOR="\e[?25h"

# Lessons
LESSONS=(
  "the quick brown fox jumps over the lazy dog"
  "bash scripting teaches patience and precision"
  "speed without accuracy is just noise"
)

lesson=${LESSONS[$RANDOM % ${#LESSONS[@]}]}
len=${#lesson}

# Session Stats
typed=""
pos=0
correct=0
errors=0
start=$(date +%s%N)  # nanoseconds
aborted=0

# Banner art
banner() {
  clear
  cat <<"EOF"
 _____
|_   _|_ _ ___ ___ ___
  | | | | | . | -_|  _|
  |_| |_  |  _|___|_|
      |___|_|
EOF
  echo -e "\nTyping practice lessons to improve your speed and accuracy.\n" | pv -qL 10
  echo -e " Author: Haitham Aouati"
  echo -e " GitHub: ${STYLE_UNDERLINE}github.com/haithamaouati${CLR_RESET}\n"
}

# Cleanup
cleanup() {
  stty sane
  echo -e "$CLR_RESET$SHOW_CURSOR"
}
trap cleanup EXIT

# Terminal raw mode
stty -echo -icanon time 0 min 1
echo -ne "$HIDE_CURSOR"

render() {
  # Clear line
  echo -ne "\r\033[2K"

  # Render lesson with underline cursor
  for ((i=0; i<len; i++)); do
    char="${lesson:i:1}"
    [[ $i -eq $pos ]] && prefix="$STYLE_UNDERLINE" || prefix=""

    if (( i >= ${#typed} )); then
      echo -ne "${prefix}${CLR_GREY}${char}${CLR_RESET}"
    else
      if [[ "${typed:i:1}" == "$char" ]]; then
        echo -ne "${prefix}${CLR_WHITE}${char}${CLR_RESET}"
      else
        echo -ne "${prefix}${CLR_RED}${char}${CLR_RESET}"
      fi
    fi
  done
}

banner
echo "Type the following (ESC to quit):"
echo
render

# Typing loop
while (( pos < len )); do
  IFS= read -rsn1 key

  # ESC to abort
  if [[ $key == $'\e' ]]; then
    aborted=1
    break
  fi

  # Backspace (DEL or CTRL-H)
  if [[ $key == $'\x7f' || $key == $'\b' ]] && (( pos > 0 )); then
    last_char="${typed: -1}"
    typed="${typed::-1}"
    ((pos--))
    if [[ "$last_char" == "${lesson:pos:1}" ]]; then
      ((correct--))
    else
      ((errors--))
    fi
  elif [[ $key =~ [[:print:]] ]]; then
    expected="${lesson:pos:1}"
    typed+="$key"
    ((pos++))
    if [[ "$key" == "$expected" ]]; then
      ((correct++))
    else
      ((errors++))
    fi
  fi

  render
done

# Final Stats
end=$(date +%s%N)
elapsed_ms=$(( (end - start)/1000000 ))
elapsed_sec=$(echo "scale=2; $elapsed_ms/1000" | bc)
accuracy=$(echo "scale=2; ($correct / $len) * 100" | bc)
words=$(echo "$len / 5" | bc -l)
minutes=$(echo "$elapsed_sec / 60" | bc -l)
wpm=$(echo "scale=2; $words / $minutes" | bc)

# Clear line before showing final lesson
echo -ne "\r\033[2K"

if (( aborted )); then
  # Aborted: show full lesson in red
  echo -e "${CLR_RED}${lesson}${CLR_RESET}"
  echo -e "\nSession Aborted!"
else
  # Completed: show letters with mistakes red, correct letters white, full green if perfect
  if (( errors == 0 )); then
    echo -e "${CLR_GREEN}${lesson}${CLR_RESET}"
  else
    for ((i=0; i<len; i++)); do
      char="${lesson:i:1}"
      if [[ "${typed:i:1}" == "$char" ]]; then
        echo -ne "${CLR_WHITE}${char}${CLR_RESET}"
      else
        echo -ne "${CLR_RED}${char}${CLR_RESET}"
      fi
    done
    echo
  fi

  echo -e "\nSession Complete!"
fi

# Stats with colors
echo -e "Total Time: ${elapsed_sec}s"
echo -e "Total Correct: ${CLR_GREEN}${correct}${CLR_RESET}"
echo -e "Total Errors: ${CLR_RED}${errors}${CLR_RESET}"
echo -e "Accuracy: ${accuracy}%"
echo -e "WPM: ${wpm}"
