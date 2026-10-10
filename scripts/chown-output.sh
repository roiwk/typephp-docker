#!/usr/bin/env bash
# Hand root-owned files in the project back to the host user.
# The container compiles as root. Without this, the binary and runtime files
# stay owned by root and the host user cannot update them.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    exit 0
fi

dir="${1:-.}"
if [[ ! -d "${dir}" ]]; then
    exit 0
fi

if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
    uid="${HOST_UID}"
    gid="${HOST_GID}"
else
    uid="$(stat -c %u "${dir}")"
    gid="$(stat -c %g "${dir}")"
fi

# The project directory itself is already root-owned. Nothing to reassign.
if [[ "${uid}" == 0 ]]; then
    exit 0
fi

find "${dir}" -xdev -uid 0 -exec chown -h "${uid}:${gid}" {} +
