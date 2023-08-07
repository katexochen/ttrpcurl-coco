#!/usr/bin/env bash

set -euo pipefail

org="confidential-containers"

function ghAPI() {
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

function downloadRepoArchive() {
    ghAPI "/repos/${org}/${1}/tarball" > "${1}.tar.gz"
}

function main() {
    repos=$(ghAPI "/orgs/${org}/repos?type=source&per_page=100")
    repos=$(jq --raw-output '.[] | select( .archived == false and .size != 0 ) | .name' <<< "$repos")

    targetPath="$(pwd)/protos"
    pushd "$(mktemp -d)" > /dev/null

    for repo in $repos; do
        echo "Downloading protos from ${repo}"

        downloadRepoArchive "$repo"
        mkdir "${repo}"
        tar -xzf "${repo}.tar.gz" -C "${repo}" --strip-components=1
        rm "${repo}.tar.gz"
        pushd "${repo}" > /dev/null

        protos=$(find . -type f -name '*.proto' -not -path '*/vendor/*')

        for proto in $protos; do
            echo "  ${proto}"

            filename=$(basename "${proto}")

            if [[ ! -e "${targetPath}/${filename}" ]]; then
                cp -n "${proto}" "${targetPath}/${filename}"
                continue
            fi

            if diff -q "${proto}" "${targetPath}/${filename}"; then
                continue
            fi

            diff "$proto" "${targetPath}/${filename}" || true
            echo
        done

        popd > /dev/null
        rm -rf "${repo}"
    done
}

main
