#!/usr/bin/env bash
# fastlane/.env 의 값을 GitHub Actions Secret 으로 등록한다 (README 11절 "시크릿 운영").
#   sh scripts/ci/set-secrets.sh                                  # 7개 전부
#   sh scripts/ci/set-secrets.sh ASC_KEY_ID                       # 지정한 것만
#   ENV_FILE=~/vault/timespread.env sh scripts/ci/set-secrets.sh  # 다른 위치의 .env 사용 (기본 fastlane/.env)
# - 리포 admin 권한이 필요하다. 재실행하면 덮어쓴다 (등록된 값은 GitHub 에서 다시 읽을 수 없다).
# - 값의 출처는 fastlane/.env.example 주석 참고. 원본은 팀 공유 금고에 보관한다.
set -euo pipefail
cd "$(dirname "$0")/../.."

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
ENV_FILE="${ENV_FILE:-fastlane/.env}"
ALL=(MATCH_PASSWORD TIMESPREAD_SLACK ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_CONTENT FIREBASE_SERVICE_ACCOUNT_JSON GH_PRIVATE_REPOS_TOKEN)
NAMES=("${@:-${ALL[@]}}")
[ $# -gt 0 ] && NAMES=("$@")

[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE 이 없습니다. cp fastlane/.env.example $ENV_FILE 후 값을 채우세요." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ gh 로그인이 필요합니다: gh auth login" >&2; exit 1; }
[ "$(gh api "repos/$REPO" --jq .permissions.admin)" = "true" ] || { echo "❌ $REPO admin 권한이 없습니다 ($(gh api user --jq .login)). Secret 등록은 admin 만 할 수 있습니다." >&2; exit 1; }

set -a; . "$ENV_FILE"; set +a
: "${GH_PRIVATE_REPOS_TOKEN:=${GITHUB_TOKEN:-}}"   # .env 에 없으면 셸의 GITHUB_TOKEN 을 쓴다

missing=()
for n in "${NAMES[@]}"; do [ -n "${!n:-}" ] || missing+=("$n"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "❌ $ENV_FILE 에 값이 없습니다: ${missing[*]}" >&2
  echo "   출처는 fastlane/.env.example 주석을 보세요." >&2
  exit 1
fi

for n in "${NAMES[@]}"; do
  printf '%s' "${!n}" | gh secret set "$n" -R "$REPO" && echo "✅ $n"
done

echo
gh secret list -R "$REPO"
