#!/bin/sh
# Tests for engine-ref.sh: a Lume with its sideload workflow (up to 3.0), one without it (3.1 on) read through
# paired-refs.txt by version, and a version not listed yet. Usage: sh ci/test_engine_ref.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
expect() { # name, wanted output, args...
  NAME="$1"; WANT="$2"; shift 2
  GOT=$(sh "$T/ci/engine-ref.sh" "$@" 2>"$T/err"); CODE=$?
  [ "$CODE" -eq 0 ] && [ "$GOT" = "$WANT" ] && ok "$NAME" || no "$NAME (exit $CODE, got '$GOT', $(cat "$T/err"))"
}
mkdir -p "$T/ci" && cp "$CI/engine-ref.sh" "$T/ci/"
cat > "$T/ci/paired-refs.txt" <<'EOF'
# comment
v3.1.0 ENGINE=v0.5.0 RECORDER=v0.1.1 CLOUD=main
v3.2.0 ENGINE=v0.6.0 RECORDER=v0.2.0
EOF

# Lume 3.0: the workflow names them
mkdir -p "$T/old/.github/workflows"
cat > "$T/old/.github/workflows/sideload-release.yml" <<'EOF'
  ENGINE_REF: ${{ github.event.inputs.engine_ref || 'v0.4.0' }}
  RECORDER_REF: ${{ github.event.inputs.recorder_ref || 'v0.1.1' }}
  CLOUD_REF: ${{ github.event.inputs.cloud_ref || 'main' }}
EOF
expect "a Lume with its workflow: the engine from it" v0.4.0 "$T/old"
expect "and the recorder" v0.1.1 "$T/old" RECORDER

# Lume 3.1: no workflow, the version picks the line
mkdir -p "$T/new/Lume.xcodeproj"
printf '\t\t\t\tMARKETING_VERSION = 3.1.0;\n\t\t\t\tMARKETING_VERSION = 3.1.0;\n' > "$T/new/Lume.xcodeproj/project.pbxproj"
expect "no workflow: the engine listed for the version" v0.5.0 "$T/new"
expect "the recorder listed for it" v0.1.1 "$T/new" RECORDER
expect "the cloud ref listed for it" main "$T/new" CLOUD

# a newer version than the list knows: the newest line, with a warning
printf '\t\t\t\tMARKETING_VERSION = 3.3.0;\n' > "$T/new/Lume.xcodeproj/project.pbxproj"
expect "an unlisted version takes the newest line's engine" v0.6.0 "$T/new"
grep -q "warning" "$T/err" && ok "and warns" || no "no warning for an unlisted version"
expect "a ref the line does not name prints nothing" "" "$T/new" CLOUD

# a quoted version with a suffix reads as its number; two different versions stop the build
printf '\t\t\t\tMARKETING_VERSION = "3.1.0-beta";\n' > "$T/new/Lume.xcodeproj/project.pbxproj"
expect "a quoted, suffixed version reads as its number" v0.5.0 "$T/new"
printf '\t\t\t\tMARKETING_VERSION = 3.1.0;\n\t\t\t\tMARKETING_VERSION = 3.10.0;\n' > "$T/new/Lume.xcodeproj/project.pbxproj"
sh "$T/ci/engine-ref.sh" "$T/new" >/dev/null 2>&1 && no "two different versions passed" \
  || ok "two different versions in the project fail"
# a version matches its own line only: 3.1 is not v3.1.0's (it takes the newest line, as unlisted)
printf '\t\t\t\tMARKETING_VERSION = 3.1;\n' > "$T/new/Lume.xcodeproj/project.pbxproj"
expect "3.1 is not read as 3.1.0" v0.6.0 "$T/new"

# a project without a version stops the build
printf 'nothing here\n' > "$T/new/Lume.xcodeproj/project.pbxproj"
sh "$T/ci/engine-ref.sh" "$T/new" >/dev/null 2>&1 && no "a project without a version passed" \
  || ok "a project without a version fails"

[ "$fails" -eq 0 ] && echo "test_engine_ref: all passed" || echo "test_engine_ref: $fails failed"
exit "$fails"
