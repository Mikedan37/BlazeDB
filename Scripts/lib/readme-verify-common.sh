#!/bin/bash
# Shared helpers for README quickstart/sample verification scripts.
# Worktrees verify a clean source snapshot but must not cold-compile BlazeDB in
# isolation — that duplicates memory use on CI and triggers OOM (Killed: 9).

# shellcheck disable=SC2034  # ROOT_DIR set by caller before source
: "${ROOT_DIR:?ROOT_DIR must be set before sourcing readme-verify-common.sh}"

README_VERIFY_BUILD_PATH="${ROOT_DIR}/.build"

# Build `product` from worktree sources using the main repo's SwiftPM build path,
# then run the executable (not `swift run`, which re-resolves and adds overhead).
readme_verify_run_product() {
    local product="$1"
    local worktree_dir="$2"

    if [ -z "$product" ] || [ -z "$worktree_dir" ]; then
        echo "readme_verify_run_product: product and worktree_dir required" >&2
        return 2
    fi

    (
        cd "$worktree_dir"
        env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
            swift build --product "$product" --build-path "$README_VERIFY_BUILD_PATH" -c debug
        local bin_dir
        bin_dir="$(
            env -i PATH="$PATH" HOME="$HOME" \
                swift build --product "$product" --build-path "$README_VERIFY_BUILD_PATH" -c debug --show-bin-path
        )"
        env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
            "$bin_dir/$product"
    )
}
