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
  # fourflusher reads stdout and stderr together, so both are captured and cleaned.
  output=$("$real" "$@" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; exit "$status"; }
  printf '%s' "$output" | ruby -e '
    require "json"
    raw = STDIN.read
    last = raw.rindex(/^\}/)
    # The object is the longest suffix ending at the last line-leading "}" that parses as JSON;
    # noise before it may lack a trailing newline, so try each "{" from the left.
    json = last && raw.enum_for(:scan, "{").map { Regexp.last_match.begin(0) }.lazy
      .map { |first| raw[first..last] }
      .find { |candidate| JSON.parse(candidate) rescue false }
    abort("simctl list returned no JSON object:\n" + raw) unless json
    puts json'
  exit $?
fi
exec "$real" "$@"
