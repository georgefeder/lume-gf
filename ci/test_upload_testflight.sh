#!/bin/sh
# Tests for upload-testflight.sh with a fake xcodebuild that answers from a script of outcomes, one per call.
# Usage: sh ci/test_upload_testflight.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/bin"
cat > "$T/bin/xcodebuild" <<'EOF'
#!/bin/sh
echo "xcodebuild $*" >> "$CALLS"
n=$(wc -l < "$CALLS" | tr -d ' ')
line=$(sed -n "${n}p" "$OUTCOMES")
case "$line" in
  ok) echo "** EXPORT SUCCEEDED **"; exit 0 ;;
  offline) echo "error: exportArchive The Internet connection appears to be offline."; exit 70 ;;
  redundant) echo "error: exportArchive Redundant Binary Upload. You've already uploaded a build with build number '105'."; exit 70 ;;
  format) echo "error: exportArchive The data couldn't be read because it isn't in the correct format."; exit 70 ;;
esac
exit 70
EOF
chmod +x "$T/bin/xcodebuild"
run() { # outcomes...
  : > "$T/calls"; printf '%s\n' "$@" > "$T/outcomes"
  out=$(PATH="$T/bin:$PATH" CALLS="$T/calls" OUTCOMES="$T/outcomes" UPLOAD_PAUSE=0 \
        sh "$CI/upload-testflight.sh" -archivePath a.xcarchive 2>&1); code=$?
  calls=$(wc -l < "$T/calls" | tr -d ' ')
}

run ok
[ "$code" -eq 0 ] && [ "$calls" -eq 1 ] && ok "an upload that works is tried once" || no "plain upload (exit $code, $calls calls)"
grep -q -- "-archivePath a.xcarchive" "$T/calls" && ok "the arguments reach xcodebuild -exportArchive" || no "arguments"

run offline ok
[ "$code" -eq 0 ] && [ "$calls" -eq 2 ] && ok "a dropped network is tried again" || no "retry (exit $code, $calls calls, $out)"

run offline redundant
[ "$code" -eq 0 ] && printf '%s' "$out" | grep -q "uploaded already" \
  && ok "\"already uploaded\" after a dropped try counts as done" || no "redundant after drop (exit $code, $out)"

run redundant
[ "$code" -ne 0 ] && ok "\"already uploaded\" on the first try is a real failure (a build number used twice)" \
  || no "first-try redundant passed"

run format ok
[ "$code" -eq 0 ] && [ "$calls" -eq 2 ] && ok "an unreadable answer (build 105's network trouble) is tried again" \
  || no "format retry (exit $code, $calls calls)"

run offline offline offline offline
[ "$code" -ne 0 ] && [ "$calls" -eq 3 ] && ok "three dropped tries give up" || no "give up (exit $code, $calls calls)"

# last: it replaces the fake xcodebuild
printf '%s\n' '#!/bin/sh' 'echo "error: exportArchive No signing certificate found"' 'exit 70' > "$T/bin/xcodebuild"
run x
[ "$code" -ne 0 ] && [ "$calls" -eq 0 ] && ok "any other error stops at once" || no "other error (exit $code)"

[ "$fails" -eq 0 ] && echo "test_upload_testflight: all passed" || echo "test_upload_testflight: $fails failed"
exit "$fails"
