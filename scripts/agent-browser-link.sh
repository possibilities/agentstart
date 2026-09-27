# shellcheck shell=bash

# Internal helper sourced by scripts/install.sh. AgentStack's Package API owns
# installation and updates; this address follows its current release without
# pinning or reinstalling a global npm package during ordinary convergence.
link_agent_browser() {
    [ "$#" -eq 0 ] || die "link_agent_browser takes no arguments"

    local state="${AGENTSTACK_STATE_DIR:-$HOME/.local/state/agentstack}"
    local source="$state/browser/toolchain/current/node_modules/agent-browser/bin/agent-browser-darwin-arm64"
    local target="$HOME/.local/bin/agent-browser"
    local previous=""
    local npm_prefix
    local global=""

    [ -x "$source" ] || {
        printf 'AgentStart installer: AgentStack has no managed agent-browser; install an exact release through its Package API.\n' >&2
        return 0
    }

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        die "refusing to replace independent file: $target"
    fi
    if [ -L "$target" ]; then
        previous=$(readlink "$target")
        npm_prefix=$(npm prefix --global)
        if [ -L "$npm_prefix/bin/agent-browser" ]; then
            global=$(realpath "$npm_prefix/bin/agent-browser")
        fi
        [ "$previous" = "$source" ] || [ "$previous" = "$global" ] \
            || die "refusing to replace independent agent-browser link: $target -> $previous"
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$source" "$target"
    [ "$(readlink "$target")" = "$source" ] \
        || die "stable agent-browser link did not retain AgentStack's managed target"
    [ -x "$target" ] || die "linked agent-browser is not executable: $target"
}
