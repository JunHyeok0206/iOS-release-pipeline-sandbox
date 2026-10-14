REPO := JunHyeok0206/iOS-release-pipeline-sandbox
# scripts/pr-body.sh 가 버전을 읽는 파일 (값 뒤에 주석을 붙이면 끝 공백이 값에 포함되므로 윗줄에 둔다)
VERSION_XCCONFIG := Config/Version.xcconfig

generate:
	mise install
	mise x -- tuist generate

# 릴리스 시작: develop 에서 release-x.y.z 생성 + x.y.z (0) 커밋
release-start:
	@test -n "$(version)" || { echo "usage: make release-start version=x.y.z"; exit 1; }
	@SINCE=$$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ); \
	gh workflow run "Release Start" -R $(REPO) -f version=$(version) && \
	$(MAKE) watch workflow="Release Start" since=$$SINCE

# QA 배포: release-x.y.z → release PR 머지 (merge commit) → Deploy (Firebase + TestFlight). PR 제목·본문은 scripts/pr-body.sh
qa-deploy: branch ?= $(shell git branch --show-current)
qa-deploy:
	@case "$(branch)" in release-*) ;; *) echo "release-x.y.z 브랜치여야 합니다 (현재: $(branch))"; exit 1;; esac
	@URL=$$(gh pr list -R $(REPO) --base release --head $(branch) --state open --json url -q '.[0].url'); \
	if [ -z "$$URL" ]; then \
		URL=$$(gh pr create -R $(REPO) --base release --head $(branch) \
			--title "$$(REPO=$(REPO) VERSION_XCCONFIG=$(VERSION_XCCONFIG) scripts/pr-body.sh title qa $(branch))" \
			--body "$$(REPO=$(REPO) VERSION_XCCONFIG=$(VERSION_XCCONFIG) scripts/pr-body.sh body qa $(branch))"); \
	fi; \
	echo "$$URL"; \
	SINCE=$$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ); \
	gh pr merge -R $(REPO) "$$URL" --merge || exit 1; \
	if gh pr view -R $(REPO) "$$URL" --json files -q '.files[].path' | grep -qvE '^docs/|\.md$$'; then \
		$(MAKE) watch workflow=Deploy since=$$SINCE; \
	else \
		echo "문서(.md, docs/)만 변경되어 Deploy 는 실행되지 않습니다 (paths-ignore). 빌드가 필요하면 make deploy"; \
	fi

# 수동 배포 (release 브랜치, both | firebase | test_flight)
deploy: lane ?= both
deploy:
	@SINCE=$$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ); \
	gh workflow run Deploy -R $(REPO) --ref release -f lane=$(lane) && \
	$(MAKE) watch workflow=Deploy since=$$SINCE

deploy-firebase:
	$(MAKE) deploy lane=firebase

deploy-testflight:
	$(MAKE) deploy lane=test_flight

# release → $(base) PR 을 열고 URL 만 출력 (이미 열려 있으면 그 URL). 제목·본문은 scripts/pr-body.sh. 내부용
open-release-pr: base ?=
open-release-pr: thread ?=
open-release-pr:
	@URL=$$(gh pr list -R $(REPO) --base $(base) --head release --state open --json url -q '.[0].url') || exit 1; \
	if [ -z "$$URL" ]; then \
		TITLE=$$(REPO=$(REPO) VERSION_XCCONFIG=$(VERSION_XCCONFIG) scripts/pr-body.sh title release $(base)) || exit 1; \
		BODY=$$(REPO=$(REPO) VERSION_XCCONFIG=$(VERSION_XCCONFIG) scripts/pr-body.sh body release $(base) '$(thread)') || exit 1; \
		URL=$$(gh pr create -R $(REPO) --base $(base) --head release --title "$$TITLE" --body "$$BODY") || exit 1; \
	fi; \
	[ -n "$$URL" ] || { echo "release → $(base) PR URL 을 얻지 못했습니다" >&2; exit 1; }; \
	echo "$$URL"

# 릴리스 마감: release → master, release → develop PR 을 연다. 여기까지가 로컬의 역할.
# 리뷰 승인 후 GitHub 에서 두 PR 을 머지하면, master push 로 Release Finish 워크플로가 태그·GitHub Release 생성과 release-x.y.z 삭제를 한다.
# thread=<slack url> 을 주면 PR 본문 요약에 관련 스레드 링크를 넣는다
release-finish: thread ?=
release-finish:
	@git fetch -q origin release master develop; \
	for b in master develop; do \
		if [ "$$(git rev-list --count origin/$$b..origin/release)" = "0" ]; then \
			echo "release → $$b: 머지할 커밋 없음, 건너뜀"; \
		else \
			URL=$$($(MAKE) -s open-release-pr base=$$b thread='$(thread)') || exit 1; \
			echo "release → $$b PR: $$URL"; \
		fi; \
	done; \
	echo ""; echo "리뷰 승인 후 GitHub 에서 두 PR 을 머지하세요. master 머지 시 Release Finish 워크플로가 태그·GitHub Release 생성과 release-x.y.z 삭제를 합니다."

runs:
	gh run list -R $(REPO) --limit 10

# workflow= 의 run 을 watch. since=<UTC, 2026-01-01T00:00:00Z> 를 주면 그 이후 생성된 run 만 찾는다 (최대 30초 대기). 내부용
watch: since ?=
watch:
	@for i in 1 2 3 4 5 6; do \
		sleep 5; \
		ID=$$(gh run list -R $(REPO) --workflow "$(workflow)" --limit 1 $(if $(since),--created ">=$(since)") --json databaseId -q '.[0].databaseId'); \
		[ -n "$$ID" ] && break; \
	done; \
	[ -n "$$ID" ] || { echo "$(workflow): $(if $(since),$(since) 이후 생성된 run 이 없습니다,run 이 없습니다)" >&2; exit 1; }; \
	gh run watch -R $(REPO) --exit-status --compact "$$ID"
