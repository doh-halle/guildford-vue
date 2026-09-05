#!/usr/bin/env bash
# scripts/secret-scan.sh — leaked secret / env var detector
#
# Modes:
#   (default)        — scan staged + unstaged changes on Bash matching
#                      'git commit'|'docker build'|'fly deploy')
#   --full           — scan the entire working tree (used by sprint security audit)
#   --history        — scan the full git history with `git log -p`
#   --pre-build      — scan files about to be COPYed into a Docker image
#   --pre-deploy     — scan files about to be uploaded via fly deploy
#
# Patterns are intentionally aggressive. False positives are managed via
# a `.secretsignore` file (one pattern per line) or inline marker
# `# secrets:allow <reason>` on the same line.
#
# Exit 0 = clean; non-zero = secrets detected (stderr enumerates findings).

set -euo pipefail

MODE="${1:-staged}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# ----------------------------------------------------------------------------
# Pattern library
#
# Each pattern is "label|regex". A line matches if any regex matches AND the
# line does not contain `secrets:allow` AND the file is not in .secretsignore.
# ----------------------------------------------------------------------------
PATTERNS=(
  'AWS Access Key|AKIA[0-9A-Z]{16}'
  'AWS Temporary Access Key|ASIA[0-9A-Z]{16}'
  'AWS Secret Access Key|aws_secret_access_key[[:space:]]*[:=][[:space:]]*['"'"'"]?[A-Za-z0-9/+=]{40}'
  'Mailgun API Key|key-[a-z0-9]{32}'
  'Mailgun Private Key|mailgun[_-]?api[_-]?key[[:space:]]*[:=][[:space:]]*['"'"'"]?[A-Za-z0-9-]{32,}'
  'Sentry DSN|https?://[a-f0-9]{32}@[a-z0-9-]+\.ingest\.sentry\.io/[0-9]+'
  'Fly API Token|fly_[A-Za-z0-9_-]{32,}'
  'Slack Bot Token|xox[abprs]-[A-Za-z0-9-]{10,}'
  'GitHub PAT|gh[pousr]_[A-Za-z0-9]{36,}'
  'Google OAuth Client Secret|GOCSPX-[A-Za-z0-9_-]{28}'
  'Stripe Live Key|sk_live_[A-Za-z0-9]{24,}'
  'Stripe Restricted Key|rk_live_[A-Za-z0-9]{24,}'
  'JWT|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  'RSA Private Key|-----BEGIN[[:space:]](RSA[[:space:]]|EC[[:space:]]|OPENSSH[[:space:]]|DSA[[:space:]]|PGP[[:space:]])?PRIVATE[[:space:]]KEY-----'
  'SSH Private Key|-----BEGIN[[:space:]]OPENSSH[[:space:]]PRIVATE[[:space:]]KEY-----'
  'Hardcoded password assignment|(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*['"'"'"][^'"'"'"]{8,}['"'"'"]'
  'Hardcoded secret assignment|(secret|api[_-]?key|token|credential)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9+/=_-]{16,}['"'"'"]'
  'Database URL with password|postgres(ql)?://[^:]+:[^@/[:space:]]{4,}@'
  'SECRET_KEY_BASE literal|SECRET_KEY_BASE[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9+/=]{30,}['"'"'"]'
  'RELEASE_COOKIE literal|RELEASE_COOKIE[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9]{12,}['"'"'"]'
)

# Files we never want committed even if empty — their presence alone is a leak risk
FORBIDDEN_FILES=(
  '\.env$'
  '\.env\.local$'
  '\.env\.production$'
  '\.env\.development\.local$'
  '\.envrc$'
  '\.pem$'
  '\.key$'
  '\.pfx$'
  'id_rsa$'
  'id_ed25519$'
  'credentials\.json$'
  '\.aws/credentials$'
)

# ----------------------------------------------------------------------------
# File-list selection per mode
# ----------------------------------------------------------------------------
files=()
case "$MODE" in
  staged|"")
    if git rev-parse --git-dir >/dev/null 2>&1; then
      while IFS= read -r f; do [[ -n "$f" && -f "$f" ]] && files+=("$f"); done < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
      while IFS= read -r f; do [[ -n "$f" && -f "$f" ]] && files+=("$f"); done < <(git diff --name-only --diff-filter=ACMR 2>/dev/null)
    fi
    ;;
  --full)
    while IFS= read -r f; do [[ -n "$f" && -f "$f" ]] && files+=("$f"); done < <(git ls-files 2>/dev/null || find . -type f -not -path './.git/*' -not -path './_build/*' -not -path './deps/*' -not -path './node_modules/*' -not -path './cover/*' -not -path './_tmp-design/*')
    ;;
  --history)
    # Scan history separately below
    files=()
    ;;
  --pre-build|--pre-deploy)
    # Same as --full but excludes test/ since those won't be in the image
    while IFS= read -r f; do
      case "$f" in
        test/*|docs/*|_tmp-design/*|cover/*) continue ;;
      esac
      [[ -n "$f" && -f "$f" ]] && files+=("$f")
    done < <(git ls-files 2>/dev/null || find . -type f -not -path './.git/*' -not -path './_build/*' -not -path './deps/*' -not -path './node_modules/*')
    ;;
  *)
    echo "secret-scan: unknown mode '$MODE'" >&2
    exit 2
    ;;
esac

# ----------------------------------------------------------------------------
# Ignore list
# ----------------------------------------------------------------------------
IGNORE_FILE=".secretsignore"
ignore_pattern=""
if [[ -f "$IGNORE_FILE" ]]; then
  ignore_pattern="$(grep -vE '^[[:space:]]*(#|$)' "$IGNORE_FILE" | tr '\n' '|' | sed 's/|$//')"
fi
matches_ignore() {
  local path="$1"
  [[ -z "$ignore_pattern" ]] && return 1
  echo "$path" | grep -qE "$ignore_pattern"
}

# ----------------------------------------------------------------------------
# Scan
# ----------------------------------------------------------------------------
findings=()

# 1) Forbidden filenames
for f in "${files[@]}"; do
  matches_ignore "$f" && continue
  for pat in "${FORBIDDEN_FILES[@]}"; do
    if echo "$f" | grep -qE "$pat"; then
      findings+=("FILE  $f  matches forbidden pattern: $pat")
    fi
  done
done

# 2) Content patterns
for f in "${files[@]}"; do
  matches_ignore "$f" && continue
  # Skip binary files
  if file --mime "$f" 2>/dev/null | grep -q 'charset=binary'; then
    continue
  fi
  # Skip the secret-scan script itself (it contains the patterns)
  case "$f" in
    scripts/secret-scan.sh|.gitleaks*|.secretsignore|.github/workflows/secret-scan.yml) continue ;;
  esac
  for entry in "${PATTERNS[@]}"; do
    label="${entry%%|*}"
    regex="${entry#*|}"
    while IFS=':' read -r line_num line_text; do
      [[ -z "$line_text" ]] && continue
      # Allow inline override
      echo "$line_text" | grep -q 'secrets:allow' && continue
      findings+=("LEAK  $f:$line_num  $label  »  $(echo "$line_text" | head -c 120)")
    done < <(grep -nEI "$regex" "$f" 2>/dev/null || true)
  done
done

# 3) Git-history mode
if [[ "$MODE" == "--history" ]]; then
  if command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks detect --redact --no-banner --no-git=false --report-format=json --report-path=/tmp/gitleaks-history.json >&2; then
      findings+=("HIST  gitleaks found leaks in git history — see /tmp/gitleaks-history.json")
    fi
  else
    echo "secret-scan: gitleaks not installed — falling back to pattern scan of git log -p (slower, less accurate)" >&2
    while IFS= read -r line; do
      for entry in "${PATTERNS[@]}"; do
        regex="${entry#*|}"
        if echo "$line" | grep -qE "$regex" && ! echo "$line" | grep -q 'secrets:allow'; then
          findings+=("HIST  (git history)  $(echo "$line" | head -c 120)")
        fi
      done
    done < <(git log -p --all --no-color 2>/dev/null | head -200000)
  fi
fi

# ----------------------------------------------------------------------------
# Report
# ----------------------------------------------------------------------------
if [[ "${#findings[@]}" -gt 0 ]]; then
  echo "" >&2
  echo "secret-scan: ${#findings[@]} potential leak(s) detected (mode=$MODE)" >&2
  echo "------------------------------------------------------------------" >&2
  for f in "${findings[@]}"; do echo "  $f" >&2; done
  echo "------------------------------------------------------------------" >&2
  echo "If a finding is a false positive, either:" >&2
  echo "  - add the path glob to .secretsignore" >&2
  echo "  - add a trailing comment containing 'secrets:allow <reason>' on the line" >&2
  exit 1
fi

echo "secret-scan: clean (mode=$MODE, scanned ${#files[@]} files)" >&2
exit 0
