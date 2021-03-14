die() {
    [[ -n "$1" ]] && echo $1 >&2
    exit 1
}

