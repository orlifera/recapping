#!/usr/bin/env bash
#
# Tiny to-do list that gets appended to each morning's recap.
#
#   ./todo.sh add "Finish the gate screen"   add a to-do
#   ./todo.sh                                 list open to-dos (also: list)
#   ./todo.sh done 2                          complete & remove to-do #2
#   ./todo.sh clear                           remove all open to-dos
#   ./todo.sh edit                            open the raw list in $EDITOR
#
# Tip: alias it so you can run it from anywhere. Add to ~/.zshrc:
#   alias todo="$HOME/daily-recap/todo.sh"
# then: todo add "..."

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODO_FILE="$SCRIPT_DIR/todos.txt"
DONE_FILE="$SCRIPT_DIR/todos.done.log"
touch "$TODO_FILE"

cmd="${1:-list}"
case "$cmd" in
  add)
    shift
    text="$*"
    [ -z "$text" ] && { echo "usage: todo.sh add \"what to do\"" >&2; exit 1; }
    printf '%s\n' "$text" >> "$TODO_FILE"
    echo "Added: $text"
    ;;

  list|ls)
    if [ ! -s "$TODO_FILE" ]; then
      echo "No open to-dos. Add one:  ./todo.sh add \"...\""
      exit 0
    fi
    n=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      n=$((n + 1))
      printf '%2d. %s\n' "$n" "$line"
    done < "$TODO_FILE"
    ;;

  done|do|rm|complete)
    shift
    num="${1:-}"
    case "$num" in
      ''|*[!0-9]*) echo "usage: todo.sh done <number>" >&2; exit 1 ;;
    esac
    line="$(sed -n "${num}p" "$TODO_FILE")"
    [ -z "$line" ] && { echo "No to-do #$num" >&2; exit 1; }
    tmp="$(mktemp)"
    awk -v n="$num" 'NR != n' "$TODO_FILE" > "$tmp" && mv "$tmp" "$TODO_FILE"
    printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$line" >> "$DONE_FILE"
    echo "Done: $line"
    ;;

  clear)
    : > "$TODO_FILE"
    echo "Cleared all open to-dos."
    ;;

  edit)
    "${EDITOR:-vi}" "$TODO_FILE"
    ;;

  -h|--help|help)
    sed -n '2,20p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'
    ;;

  *)
    echo "Unknown command: $cmd  (try: add, list, done, clear, edit)" >&2
    exit 1
    ;;
esac
