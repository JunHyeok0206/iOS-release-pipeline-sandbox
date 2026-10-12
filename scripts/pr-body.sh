#!/usr/bin/env bash
# Makefile 이 여는 PR 의 제목·본문을 생성한다. (README 5절 "PR 제목·본문")
#
#   scripts/pr-body.sh title qa      <release-x.y.z>
#   scripts/pr-body.sh body  qa      <release-x.y.z>
#   scripts/pr-body.sh title release <master|develop>
#   scripts/pr-body.sh body  release <master|develop> [slack-thread-url]
#
# 환경변수: REPO (owner/name, 기본 gh repo view), VERSION_XCCONFIG (기본 Config/Version.xcconfig),
#           FROM (release 범위 시작점 override, 테스트용. 기본은 최신 태그)
set -euo pipefail

MODE="${1:-}"; KIND="${2:-}"; TARGET="${3:-}"; THREAD="${4:-}"
[ -n "$MODE" ] && [ -n "$KIND" ] && [ -n "$TARGET" ] || { sed -n '2,8p' "$0"; exit 1; }

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
VERSION_XCCONFIG="${VERSION_XCCONFIG:-Config/Version.xcconfig}"
git fetch -q origin

xcconfig_value() { git show "origin/release:$VERSION_XCCONFIG" | sed -n "s/^$1 *= *//p"; }
VERSION="$(xcconfig_value MARKETING_VERSION)"
BUILD="$(xcconfig_value CURRENT_PROJECT_VERSION)"

# 범위 결정
case "$KIND" in
  qa)      BASE="origin/release"; TIP="origin/$TARGET" ;;
  release)
    TIP="origin/release"
    if [ -n "${FROM:-}" ]; then BASE="$FROM"
    else
      # 태그는 master 의 머지 커밋(release → master)에 찍힌다. 그 두 번째 부모가 지난 마감 시점의 release.
      # 머지 커밋이 아니면(fast-forward 등) merge-base 로 대신한다
      LAST_TAG="$(git tag --sort=-v:refname | head -1)"
      BASE=""
      if [ -n "$LAST_TAG" ]; then
        BASE="$(git rev-parse -q --verify "$LAST_TAG^2" 2>/dev/null || git merge-base "$LAST_TAG" origin/release)"
      fi
    fi ;;
  *) echo "kind 는 qa | release" >&2; exit 1 ;;
esac

# 변경 목록 수집. first-parent 로 걸어 PR 내부 커밋은 세지 않는다.
#   - "Merge pull request #N from owner/head": head 가 release 면 역병합 PR → 제외. release-* 면 배포 PR → 그 안쪽(release-x.y.z)을 한 단계 더 걸음. 그 외는 PR 항목
#   - "Merge release-x.y.z into release" (Release Start 머지): 두 번째 부모 쪽(develop)을 한 단계 더 걸어 feature PR 수집
#   - 머지가 아닌 커밋: bump·bot 제외하고 직접 커밋 항목
# 출력 형식: "<제목>\t<꼬리>"  꼬리 = "(#N)" 또는 "(`sha`)"
# --first-parent 는 제외 기준(base)도 first-parent 로만 따지므로, base 의 조상인지 is-ancestor 로 따로 거른다
walk() { # $1=base(비어 있을 수 있음) $2=tip
  local base="$1" tip="$2" spec
  if [ -n "$base" ]; then spec="$base..$tip"; else spec="$tip"; fi
  git log --first-parent --format='%H%x09%P%x09%an%x09%s' "$spec" | while IFS=$'\t' read -r sha parents author subject; do
    [ -n "$base" ] && git merge-base --is-ancestor "$sha" "$base" && continue
    case "$subject" in
      "Merge pull request #"*)
        num="$(printf '%s' "$subject" | sed -E 's/^Merge pull request #([0-9]+).*/\1/')"
        head="$(printf '%s' "$subject" | sed -E 's/^Merge pull request #[0-9]+ from [^/]+\/(.*)$/\1/')"
        case "$head" in
          release)   continue ;;                                              # 역병합 PR
          release-*) [ "$DEPTH" = "0" ] && DEPTH=1 walk "${sha}^1" "${sha}^2"; continue ;;   # 배포 PR: release-x.y.z 쪽을 한 단계 더 걸음
        esac
        title="$(gh pr view "$num" -R "$REPO" --json title -q .title 2>/dev/null || echo "PR #$num")"
        printf '%s\t(#%s)\n' "$title" "$num" ;;
      "Merge release-"*" into release")
        [ "$DEPTH" = "0" ] && DEPTH=1 walk "${sha}^1" "${sha}^2" ;;
      "Merge "*|"Bump version to "*) continue ;;
      *)
        [ "$author" = "github-actions[bot]" ] && continue
        case "$parents" in *" "*) continue ;; esac   # 그 밖의 머지 커밋은 건너뜀
        printf '%s\t(`%s`)\n' "$subject" "$(git rev-parse --short "$sha")" ;;
    esac
  done
}
collect() { DEPTH=0 walk "$BASE" "$TIP" | awk -F'\t' '!seen[$2]++'; }

ITEMS="$(collect)"
COUNT="$( [ -n "$ITEMS" ] && printf '%s\n' "$ITEMS" | wc -l | tr -d ' ' || echo 0 )"

if [ "$MODE" = "title" ]; then
  case "$KIND" in
    qa)      echo "deploy: $TARGET (${COUNT}건)" ;;
    release) echo "release: $VERSION ${TARGET}에 반영" ;;
  esac
  exit 0
fi

# ---------- body ----------
if [ "$KIND" = "qa" ]; then
  echo "## 배포 내용"
  echo "\`$TARGET\` 의 변경 ${COUNT}건을 \`release\` 에 머지해 Firebase + TestFlight 를 배포합니다. (현재 \`release\`: $VERSION ($BUILD))"
  echo
  if [ "$COUNT" = "0" ]; then echo "- 변경 없음 (재배포)"; else
    printf '%s\n' "$ITEMS" | while IFS=$'\t' read -r title tail; do echo "- $title $tail"; done
  fi
  exit 0
fi

# release → master | develop
echo "## 🎯 요약"
echo "$VERSION 배포 버전을 \`$TARGET\` 에 반영 (마지막 빌드 $VERSION ($BUILD))"
if [ -n "$THREAD" ]; then echo; echo "- **관련 스레드**: [$VERSION 배포 공지]($THREAD)"; fi
echo
echo "## 📋 작업 배경"
if [ "$TARGET" = "develop" ]; then
  echo "- **현재 상황**: $VERSION 배포 과정에서 \`release\` 에 쌓인 QA 수정과 버전 변경이 \`develop\` 에는 없습니다."
  echo "- **해결할 문제**: \`release\` 를 \`develop\` 에 역병합해 다음 릴리스에서 회귀하지 않도록 합니다."
else
  echo "- **현재 상황**: $VERSION QA 와 배포가 완료됐고, 배포 시점의 코드가 \`release\` 에만 있습니다."
  echo "- **해결할 문제**: \`$TARGET\` 를 최신 배포 버전과 일치시키고 태그 \`$VERSION\` 를 생성합니다."
fi
echo
echo "## 🔧 변경 사항"
if [ "$COUNT" = "0" ]; then echo "- 변경 사항 없음 (버전 변경만)"; exit 0; fi

# type: 접두어로 분류
group() { # $1=type-regex
  printf '%s\n' "$ITEMS" | awk -F'\t' -v re="^($1)(\\([^)]*\\))?:[ ]*" '
    tolower($1) ~ re { t=$1; sub(re, "", t); print "  - " t " " $2 }'
}
others() {
  printf '%s\n' "$ITEMS" | awk -F'\t' '
    tolower($1) !~ /^(feat|fix|refactor|update|chore|docs|test|ci|build|perf|style)(\([^)]*\))?:/ { print "  - " $1 " " $2 }'
}
section() { local label="$1" lines="$2"; if [ -n "$lines" ]; then echo "- **$label**"; printf '%s\n' "$lines"; fi; }
section "Feature"  "$(group feat)"
section "Fix"      "$(group fix)"
section "Refactor" "$(group refactor)"
section "Update"   "$(group update)"
section "Chore"    "$(group 'chore|docs|test|ci|build|perf|style')"
section "기타"     "$(others)"
exit 0
