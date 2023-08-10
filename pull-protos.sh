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
    repoNames=$(
        jq --raw-output '.[] | select(
            .archived == false and
            .size != 0 and
            .license.spdx_id == "Apache-2.0"
        ) | .name' <<< "$repos"
    )

    targetPath="$(pwd)/protos"
    pushd "$(mktemp -d)" > /dev/null
    rm -rf "${targetPath}"
    mkdir -p "${targetPath}"

    for repo in $repoNames; do
        echo "Downloading protos from ${repo}"

        downloadRepoArchive "$repo"
        mkdir "${repo}"
        tar -xzf "${repo}.tar.gz"
        rm "${repo}.tar.gz"
        unpackDir=$(ls -d "${org}-${repo}"*)
        ref=${unpackDir##*-}
        pushd "${unpackDir}" > /dev/null

        protos=$(find . -type f -name '*.proto' -not -path '*/vendor/*')

        copied=0
        for proto in $protos; do
            echo "  ${proto}"

            filename=$(basename "${proto}")
            filenamePrefix=${filename%%.proto}

            if ! grep -q "package ${filenamePrefix};" "${proto}"; then
                # Fix package name to the filename to prevent collisions
                sed -i "s/^package .*;$/package ${filenamePrefix};/" "${proto}"
                continue
            fi

            if [[ ! -e "${targetPath}/${filename}" ]]; then
                cp -n "${proto}" "${targetPath}/${filename}"
                copied=$((copied + 1))
                continue
            fi

            if diff -q "${proto}" "${targetPath}/${filename}"; then
                continue
            fi

            diff "$proto" "${targetPath}/${filename}" || true
            echo
        done

        if [[ $copied -ne 0 ]]; then
            echo "${org}/${repo} ${ref}" >> "${targetPath}/.refs"
        fi

        popd > /dev/null
        rm -rf "${repo}"
    done

    sort -o "${targetPath}/.refs" "${targetPath}/.refs"
}

main
