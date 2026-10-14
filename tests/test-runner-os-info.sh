#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
# Force more output than a pipe can buffer; early-closing readers make producers fail.
{
  printf 'NAME="Test Linux"\n'
  for ((i = 0; i < 10000; i++)); do printf 'EXTRA_RELEASE_DETAIL=%s\n' "$i"; done
} > "$fixture_dir/release"
cat > "$fixture_dir/lsb_release" <<'STUB'
#!/usr/bin/env bash
cat "$TEST_RELEASE_FILE"
STUB
chmod +x "$fixture_dir/lsb_release"
export PATH="$fixture_dir:$PATH"
export TEST_RELEASE_FILE="$fixture_dir/release"
assignment=$(sed -n '/^info_os=/p' "$repo_root/modules/runners/templates/start-runner.sh")
[[ -n "$assignment" ]]
for ((i = 0; i < 20; i++)); do
  result=$(bash -euo pipefail -c "$assignment; printf '%s' \"\$info_os\"")
  [[ "$result" == 'Test Linux' ]]
done
printf 'Runner OS metadata handles multiline output under pipefail.\n'
