#!/bin/sh
# Structure checks for the build workflow: a tests job runs first, every TestFlight leg (iOS and tvOS) waits for it,
# and the tests job never signs or uploads. Needs ruby (YAML). Usage: sh ci/test_workflows.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); WF="$CI/../.github/workflows/lume-gf-build.yml"; fails=0
check() {  # $1 = name, $2 = ruby, $3 = workflow file (default: the build workflow), [$4 = a second file]
  if ruby -ryaml -e "$2" "${3:-$WF}" ${4:+"$4"} >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
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
WT="$CI/../.github/workflows/lume-gf-test.yml"; WC="$CI/../.github/workflows/lume-gf-check.yml"
check "both build jobs patch Lume's packages before building" \
  'y=YAML.load_file(ARGV[0]); exit(%w[tests build].all? { |j| y["jobs"][j]["steps"].any? { |s| s["run"].to_s.include?("apply-dep-patches.sh") } } ? 0 : 1)'
check "the archive uses the patched packages" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["build"]["steps"].map { |s| s["run"].to_s }.find { |r| r.include?("xcodebuild archive") }.to_s; exit(r.include?("-clonedSourcePackagesDirPath") && r.include?("-disableAutomaticPackageResolution") ? 0 : 1)'
check "the test run patches Lume's packages and compiles tvOS with them" \
  'y=YAML.load_file(ARGV[0]); s=y["jobs"]["app"]["steps"]; tv=s.find { |x| x["name"].to_s == "tvOS compiles" }; exit(s.any? { |x| x["run"].to_s.include?("apply-dep-patches.sh") } && tv["run"].to_s.include?("-disableAutomaticPackageResolution") ? 0 : 1)' "$WT"
check "a change to our package patches starts a build" \
  'y=YAML.load_file(ARGV[0]); o=y["on"] || y[true]; exit(Array(o["push"]["paths"]).include?("deps/**") ? 0 : 1)' "$WC"
check "no build includes the screenshot demo" 'exit(File.read(ARGV[0]).include?("GF_DEMO") ? 1 : 0)'
check "pushes to part3 branches run the tests" \
  'y=YAML.load_file(ARGV[0]); o=y["on"] || y[true]; exit(Array(o["push"]["branches"]).include?("part3/**") ? 0 : 1)' "$WT"
check "pushes to part4 branches run the tests" \
  'y=YAML.load_file(ARGV[0]); o=y["on"] || y[true]; exit(Array(o["push"]["branches"]).include?("part4/**") ? 0 : 1)' "$WT"
check "the test run checks the identity and export scripts" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["core"]["steps"].map { |s| s["run"].to_s }.join; exit(r.include?("test_patch_scripts.sh") && r.include?("test_check_export.sh") ? 0 : 1)' "$WT"
check "a screenshots job keeps its pictures" \
  'y=YAML.load_file(ARGV[0]); s=y["jobs"]["screenshots"]["steps"]; exit(s.any? { |x| x["run"].to_s.include?("screenshots.sh") } && s.any? { |x| x["uses"].to_s.start_with?("actions/upload-artifact") } ? 0 : 1)' "$WT"
check "the screenshots job keeps the app's output with the pictures" \
  'y=YAML.load_file(ARGV[0]); u=y["jobs"]["screenshots"]["steps"].find { |x| x["uses"].to_s.start_with?("actions/upload-artifact") }; exit(u["with"]["path"].to_s.end_with?("screenshots") ? 0 : 1)' "$WT"
check "the screenshots are taken with our patched packages" \
  'y=YAML.load_file(ARGV[0]); exit(y["jobs"]["screenshots"]["steps"].any? { |x| x["run"].to_s.include?("apply-dep-patches.sh") } ? 0 : 1)' "$WT"
check "the screenshots job never uses a secret" \
  'y=YAML.load_file(ARGV[0]); exit(y["jobs"]["screenshots"].to_s.include?("secrets.") ? 1 : 0)' "$WT"
check "the test run's script tests run the Python tests as a command of their own" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["core"]["steps"].find { |x| x["name"].to_s == "Script tests" }["run"].to_s; exit(r.lines.any? { |l| l.strip.start_with?("python3 -m unittest") } ? 0 : 1)' "$WT"
# Part 4: the iCloud layout jobs use only the CloudKit token and the team id, never echo the token, and a TestFlight
# build waits for production to have the layout
check "the iCloud layout jobs use only the CloudKit token and the team id" \
  'ok = [[ARGV[0], "icloud-layout"], [ARGV[1], "icloud-gate"]].all? { |f, j| s = YAML.load_file(f)["jobs"][j].to_s.scan(/secrets\.(\w+)/).flatten.uniq.sort; s == %w[CLOUDKIT_MANAGEMENT_TOKEN TEAM_ID] }; exit(ok ? 0 : 1)' "$WT" "$WF"
check "the CloudKit token is never echoed" \
  'exit([ARGV[0], ARGV[1]].any? { |f| File.read(f).lines.any? { |l| l =~ /(echo|printf)[^;|&]*\$\{?CLOUDKIT_MANAGEMENT_TOKEN/ } } ? 1 : 0)' "$WT" "$WF"
check "the tests run never runs on pull requests" \
  'y=YAML.load_file(ARGV[0]); o=y["on"] || y[true]; exit(o.key?("pull_request") || o.key?("pull_request_target") ? 1 : 0)' "$WT"
check "every TestFlight leg waits for production's iCloud layout" \
  'y=YAML.load_file(ARGV[0]); r=y["jobs"]["icloud-gate"]["steps"].map { |s| s["run"].to_s }.join; exit(Array(y["jobs"]["build"]["needs"]).include?("icloud-gate") && r.include?("schema-check.py") ? 0 : 1)'
check "the app tests stop on a Lume setting without a sync group (after our sources, before the tests)" \
  'y=YAML.load_file(ARGV[0]); s=y["jobs"]["app"]["steps"]; f=->(n) { s.index { |x| x["run"].to_s.include?(n) } }; i, t, a = f["add-sources.sh"], f["settings-tripwire.sh gf Lume"], f["run-app-tests.sh"]; exit(i && t && a && i < t && t < a ? 0 : 1)' "$WT"
[ "$fails" -eq 0 ] && echo "test_workflows: all passed" || echo "test_workflows: $fails failed"
exit "$fails"
