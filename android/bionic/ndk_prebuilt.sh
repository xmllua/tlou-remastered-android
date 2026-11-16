# --- NDK host prebuilt detection -------------------------------------------
# The NDK ships its host toolchain under toolchains/llvm/prebuilt/<host>.
# Upstream NDK releases use linux-x86_64; an aarch64-hosted NDK (for example
# the one AndroidPE provides on device) uses linux-arm64. Resolve the directory
# instead of hardcoding it so the same build scripts work on both hosts.
ndk_prebuilt() {
  local base=$1/toolchains/llvm/prebuilt
  local candidate
  for candidate in linux-x86_64 linux-arm64 linux-aarch64 linux-x86_64-musl linux-arm64-musl; do
    if [[ -d $base/$candidate ]]; then printf '%s\n' "$base/$candidate"; return 0; fi
  done
  candidate=$(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
  if [[ -n $candidate ]]; then printf '%s\n' "$candidate"; return 0; fi
  return 1
}
# --- end NDK host prebuilt detection ---------------------------------------
# Allow other tooling (for example the Python verification scripts) to reuse the
# same resolution as the shell build steps instead of repeating the list.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  :
elif [[ -n ${1:-} ]]; then
  ndk_prebuilt "$1" || { echo "No NDK host prebuilt under $1" >&2; exit 1; }
fi
