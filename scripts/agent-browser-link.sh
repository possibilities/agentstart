# shellcheck shell=bash

# Internal helper sourced by scripts/install.sh. Resolve the global npm entry
# before replacing the stable fleet address: PATH may already find that address
# from a prior run, and linking it to itself creates an unusable symlink loop.
link_agent_browser() {
    [ "$#" -eq 1 ] || die "link_agent_browser requires the global npm prefix"

    local npm_prefix="$1"
    local source
    local source_link
    local target="$HOME/.local/bin/agent-browser"

    case "$npm_prefix" in
        /*) ;;
        *) die "npm global prefix is not absolute: $npm_prefix" ;;
    esac

    source_link="$npm_prefix/bin/agent-browser"
    source=$(realpath "$source_link") \
        || die "could not resolve npm's global agent-browser entrypoint: $source_link"
    [ -x "$source" ] \
        || die "npm's global agent-browser entrypoint is not executable: $source"
    [ "$source" != "$target" ] \
        || die "npm's global agent-browser entrypoint resolves to its stable link: $target"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        die "refusing to replace independent file: $target"
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$source" "$target"
    [ "$(readlink "$target")" = "$source" ] \
        || die "stable agent-browser link did not retain its resolved npm target"
    [ -x "$target" ] || die "linked agent-browser is not executable: $target"
}
