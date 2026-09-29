#!/bin/sh
# Structure checks for the build workflow: a tests job runs first, every TestFlight leg (iOS and tvOS) waits for it,
# and the tests job never signs or uploads. Needs ruby (YAML). Usage: sh ci/test_workflows.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); WF="$CI/../.github/workflows/lume-gf-build.yml"; fails=0
check() {
  if ruby -ryaml -e "$2" "$WF" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
check "a tests job exists" 'y=YAML.load_file(ARGV[0]); exit(y["jobs"].key?("tests") ? 0 : 1)'
check "every build leg waits for the tests" \
  'y=YAML.load_file(ARGV[0]); exit(Array(y["jobs"]["build"]["needs"]).include?("tests") ? 0 : 1)'
check "the tests job runs swift test and the app tests" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["tests"]["steps"].map { |s| s["run"].to_s }.join("\n"); exit(r.include?("swift test") && r.include?("run-app-tests.sh") ? 0 : 1)'
check "the tests job never signs or uploads" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["tests"]["steps"].map { |s| s["run"].to_s + s["name"].to_s + s["env"].to_s }.join("\n"); exit(r =~ /exportArchive|asc\.p8|ASC_KEY|TEAM_ID/ ? 1 : 0)'
check "the build legs do not run the tests again" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["build"]["steps"].map { |s| s["run"].to_s }.join("\n"); exit(r.include?("run-app-tests.sh") || r.include?("swift test") ? 1 : 0)'
[ "$fails" -eq 0 ] && echo "test_workflows: all passed" || echo "test_workflows: $fails failed"
exit "$fails"
