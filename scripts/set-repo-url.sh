#!/usr/bin/env bash
#
# Rewrites the <OWNER>/<REPO> placeholders across the repo to a real GitHub
# slug. Run once before pushing to GitHub for the first time.
#
# Usage:
#   scripts/set-repo-url.sh <owner> <repo>
#
# Example:
#   scripts/set-repo-url.sh liyuanyuan obsidian-clipper-autotrigger

set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: %s <owner> <repo>\n' "$0" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Files that reference the placeholder.
FILES=(
    "README.md"
    "AGENT_INSTALL.md"
    "SKILL.md"
    "bootstrap.sh"
    "bootstrap.ps1"
)

for rel in "${FILES[@]}"; do
    f="$SKILL_DIR/$rel"
    [[ -f "$f" ]] || continue
    # Replace both "<OWNER>/<REPO>" as a unit and standalone "<OWNER>" / "<REPO>".
    python3 - "$f" "$OWNER" "$REPO" <<'PY'
import sys, pathlib
path, owner, repo = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
text = p.read_text(encoding='utf-8')
new = (text
    .replace('<OWNER>/<REPO>', f'{owner}/{repo}')
    .replace('&lt;OWNER&gt;/&lt;REPO&gt;', f'{owner}/{repo}')
    .replace('<OWNER>', owner)
    .replace('<REPO>', repo)
    .replace('&lt;OWNER&gt;', owner)
    .replace('&lt;REPO&gt;', repo)
)
if new != text:
    p.write_text(new, encoding='utf-8')
    print(f'Updated {path}')
else:
    print(f'No placeholders in {path}')
PY
done

printf '\nDone. Verify with:\n'
printf "  grep -R '<OWNER>\\|<REPO>' %s\n" "$SKILL_DIR"
