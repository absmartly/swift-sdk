#!/usr/bin/env bash
# Opt-in xcrun wrapper for running `pod lib lint` on iOS/tvOS with CocoaPods 1.17.0 (fourflusher
# 2.3.1), which crashes reading the simulator list before building:
#   - `simctl list -j devices` can print non-JSON lines that fourflusher does not strip
#     ("unexpected token at end of stream 'Install'" in JSON.parse);
#   - output not ending in a newline makes fourflusher append the nil $INPUT_RECORD_SEPARATOR
#     ("no implicit conversion of nil into String").
# For `simctl list ... -j` it prints only the JSON object, ending in a newline; every other call is
# passed to the real xcrun unchanged. It changes how the simulator list is read, not what is built.
# Use: mkdir -p /tmp/xcrun-shim && cp scripts/xcrun-simctl-json.sh /tmp/xcrun-shim/xcrun &&
#      PATH="/tmp/xcrun-shim:$PATH" pod lib lint ...
real=${REAL_XCRUN:-/usr/bin/xcrun}
if [ "${1:-}" = simctl ] && [ "${2:-}" = list ] && printf '%s\n' "$@" | grep -qx -- '-j'; then
  output=$("$real" "$@")
  status=$?
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; exit "$status"; }
  printf '%s' "$output" | ruby -e '
    raw = STDIN.read
    first = raw.index(/^\{/)
    last = raw.rindex(/^\}/)
    abort("simctl list returned no JSON object:\n" + raw) unless first && last
    puts raw[first..last]'
  exit $?
fi
exec "$real" "$@"
