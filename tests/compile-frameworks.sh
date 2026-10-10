#!/usr/bin/env bash
# Compile the framework samples with scripts/compile.sh, then run them.
# That path applies the same runtime/storage rewrites as a normal one-click compile.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="${TYPEPHP_JOBS:-2}"
export TYPEPHP_JOBS="${JOBS}"

cd "${ROOT}"

# target|compile.sh command|binary|cli <args> | http <port> | fpm <conf>
targets=(
    "laravel|laravel-cli|build/laravel|cli|about"
    "webman|webman|build/webman|http|8787"
    "laravel-fpm|laravel-fpm|build/laravel-fpm|fpm|php-fpm.conf"
)
if [[ $# -gt 0 ]]; then
    selected=()
    for spec in "${targets[@]}"; do
        IFS='|' read -r name _ <<<"${spec}"
        for want in "$@"; do
            if [[ "${name}" == "${want}" ]]; then
                selected+=("${spec}")
            fi
        done
    done
    targets=("${selected[@]}")
    if ((${#targets[@]} == 0)); then
        echo "unknown target: $*" >&2
        exit 2
    fi
else
    # FPM builds another private PHP. Ask for it by name.
    targets=(
        "laravel|laravel-cli|build/laravel|cli|about"
        "webman|webman|build/webman|http|8787"
    )
fi

failures=()

run_http() {
    local bin="$1" port="$2" log="$3"
    "${bin}" start >"${log}" 2>&1 &
    local pid=$!
    local body="" code="" ok=0
    local i
    for i in $(seq 1 25); do
        if ! kill -0 "${pid}" 2>/dev/null; then
            break
        fi
        code="$(curl -sS -m 2 -o /tmp/typephp-http-body -w '%{http_code}' "http://127.0.0.1:${port}/" || true)"
        if [[ "${code}" =~ ^[23] ]]; then
            body="$(head -c 400 /tmp/typephp-http-body || true)"
            ok=1
            break
        fi
        sleep 1
    done
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
    if [[ "${ok}" -eq 1 ]]; then
        echo "HTTP ${code} ${body}"
        return 0
    fi
    echo "HTTP check failed on port ${port}"
    tail -n 40 "${log}" || true
    return 1
}

# One FastCGI request to public/index.php. php-fpm.conf listens on 127.0.0.1:9000.
run_fpm() {
    local bin="$1" conf="$2" log="$3"
    local public="${PWD}/public/index.php"
    "${bin}" --fpm-config "${conf}" >"${log}" 2>&1 &
    local pid=$!
    local ok=0
    local i
    for i in $(seq 1 20); do
        if ! kill -0 "${pid}" 2>/dev/null; then
            break
        fi
        if python3 - "${public}" <<'PY'
import socket, struct, sys
script = sys.argv[1]
def length(n):
    return bytes([n]) if n < 128 else struct.pack(">I", n | 0x80000000)
def nv(pairs):
    out = b""
    for key, value in pairs:
        key, value = key.encode(), value.encode()
        out += length(len(key)) + length(len(value)) + key + value
    return out
def rec(kind, body, req=1):
    pad = (8 - len(body) % 8) % 8
    return struct.pack(">BBHHBB", 1, kind, req, len(body), pad, 0) + body + b"\x00" * pad
params = nv([
    ("GATEWAY_INTERFACE", "CGI/1.1"),
    ("REQUEST_METHOD", "GET"),
    ("SCRIPT_FILENAME", script),
    ("SCRIPT_NAME", "/index.php"),
    ("REQUEST_URI", "/up"),
    ("QUERY_STRING", ""),
    ("SERVER_PROTOCOL", "HTTP/1.1"),
    ("SERVER_NAME", "127.0.0.1"),
    ("SERVER_PORT", "80"),
    ("HTTP_HOST", "127.0.0.1"),
    ("DOCUMENT_ROOT", script.rsplit("/", 1)[0]),
])
try:
    sock = socket.create_connection(("127.0.0.1", 9000), 2)
except OSError:
    sys.exit(1)
sock.sendall(rec(1, struct.pack(">HB5x", 1, 0)) + rec(4, params) + rec(4, b"") + rec(5, b""))
data = b""
while True:
    chunk = sock.recv(65536)
    if not chunk:
        break
    data += chunk
    if len(data) > 200000:
        break
out = b""
i = 0
while i + 8 <= len(data):
    _, kind, _, length, pad, _ = struct.unpack(">BBHHBB", data[i:i + 8])
    i += 8
    body = data[i:i + length]
    i += length + pad
    if kind == 6:
        out += body
    elif kind == 3:
        break
text = out.decode("utf-8", "replace")
if "Application up" not in text or "Status: 500" in text or "Status: 404" in text:
    sys.stdout.write(text[:400].replace("\r", "") + "\n")
    sys.exit(1)
print("FPM /up: Application up")
PY
        then
            ok=1
            break
        fi
        sleep 1
    done
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
    if [[ "${ok}" -eq 1 ]]; then
        return 0
    fi
    echo "FPM check failed"
    tail -n 40 "${log}" || true
    return 1
}

for spec in "${targets[@]}"; do
    IFS='|' read -r name command binary mode arg <<<"${spec}"
    dest="${ROOT}/tests/frameworks/${name%-fpm}"
    if [[ "${name}" == "laravel-fpm" ]]; then
        dest="${ROOT}/tests/frameworks/laravel"
    fi
    echo "===== compile ${name} via compile.sh ${command} ====="
    if ! "${ROOT}/scripts/compile.sh" "${command}" "${dest}"; then
        echo "FAIL ${name}: compile error"
        failures+=("${name}:compile")
        continue
    fi
    if [[ ! -x "${dest}/${binary}" ]]; then
        echo "FAIL ${name}: ${binary} was not produced"
        failures+=("${name}:missing-binary")
        continue
    fi
    echo "built ${dest}/${binary}"
    (
        cd "${dest}"
        if [[ "${mode}" == http ]]; then
            run_http "./${binary}" "${arg}" "build/run.log"
        elif [[ "${mode}" == fpm ]]; then
            run_fpm "./${binary}" "${arg}" "build/run.log"
        else
            "./${binary}" ${arg}
        fi
    ) >"${dest}/build/run.log" 2>&1 || {
        echo "FAIL ${name}: binary did not run"
        tail -n 40 "${dest}/build/run.log" || true
        failures+=("${name}:run")
        continue
    }
    echo "RUN ${name}"
    cat "${dest}/build/run.log"
done

if [[ -f "${ROOT}/tests/frameworks/webman/build/runtime/logs/workerman.log" ]]; then
    echo "webman log follows the binary"
fi
if [[ -d "${ROOT}/tests/frameworks/laravel/build/storage" ]]; then
    echo "laravel storage follows the binary"
fi

if ((${#failures[@]} > 0)); then
    echo "failed: ${failures[*]}" >&2
    exit 1
fi
echo "all framework binaries compiled and ran"
