#!/bin/sh
# Tests for apply-dep-patches.sh with a fake xcodebuild that "resolves" one package (a small git repo) into the given
# folder. Usage: sh ci/test_apply_dep_patches.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
git init -q "$T/template" && printf 'one\n' > "$T/template/a.txt" && git -C "$T/template" add a.txt \
  && git -C "$T/template" -c user.name=t -c user.email=t@t commit -q -m base
REV=$(git -C "$T/template" rev-parse HEAD)
mkdir -p "$T/bin" "$T/Lume/Lume.xcodeproj" "$T/ours/deps/KSPlayer"
cat > "$T/bin/xcodebuild" <<EOF
#!/bin/sh
dir=""; prev=""
for a in "\$@"; do [ "\$prev" = "-clonedSourcePackagesDirPath" ] && dir="\$a"; prev="\$a"; done
[ -n "\$dir" ] || { echo "no -clonedSourcePackagesDirPath" >&2; exit 1; }
mkdir -p "\$dir/checkouts" && rm -rf "\$dir/checkouts/KSPlayer" && cp -R "$T/template" "\$dir/checkouts/KSPlayer"
EOF
chmod +x "$T/bin/xcodebuild"
printf '%s\n' "$REV" > "$T/ours/deps/KSPlayer/REVISION"
printf 'two\n' > "$T/template/a.txt" && git -C "$T/template" diff > "$T/ours/deps/KSPlayer/0001-test.patch" \
  && git -C "$T/template" checkout -q a.txt
run() { PATH="$T/bin:$PATH" sh "$CI/apply-dep-patches.sh" "$T/ours" "$T/Lume" "$T/spm" 2>&1; }
out=$(run) && ok "applies our package patches" || no "applies ($out)"
[ "$(cat "$T/spm/checkouts/KSPlayer/a.txt" 2>/dev/null)" = "two" ] && ok "the package source is patched" || no "source unpatched"
printf '%s' "$out" | grep -q "1 patch(es) applied" && ok "reports the count" || no "count ($out)"
printf '%s\n' 0000000000000000000000000000000000000000 > "$T/ours/deps/KSPlayer/REVISION"
run >/dev/null && no "another package revision must stop the build" || ok "another package revision stops the build"
printf '%s\n' "$REV" > "$T/ours/deps/KSPlayer/REVISION"; printf 'nope\n' > "$T/ours/deps/KSPlayer/0002-bad.patch"
run >/dev/null && no "a patch that does not apply must stop the build" || ok "a patch that does not apply stops the build"
rm "$T/ours/deps/KSPlayer/0002-bad.patch"; mkdir -p "$T/ours/deps/NotAPackage"; printf 'x\n' > "$T/ours/deps/NotAPackage/REVISION"
run >/dev/null && no "a package Lume does not use must stop the build" || ok "a package Lume does not use stops the build"
rm -rf "$T/ours/deps"; out=$(run) && printf '%s' "$out" | grep -q "0 patch(es) applied" && ok "no deps folder, nothing to do" \
  || no "no deps folder ($out)"
[ "$fails" -eq 0 ] && echo "test_apply_dep_patches: all passed" || echo "test_apply_dep_patches: $fails failed"
exit "$fails"
