REPO := JunHyeok0206/iOS-release-pipeline-sandbox
VERSION_XCCONFIG := Config/Version.xcconfig   # scripts/pr-body.sh 가 버전을 읽는 파일

generate:
	mise install
	mise x -- tuist generate

# 릴리스 시작: develop 에서 release-x.y.z 생성 + x.y.z (0) 커밋
release-start:
	@test -n "$(version)" || { echo "usage: make release-start version=x.y.z"; exit 1; }
	gh workflow run "Release Start" -R $(REPO) -f version=$(version)
	$(MAKE) watch workflow="Release Start"

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
	echo "$$URL"; gh pr merge -R $(REPO) "$$URL" --merge
	$(MAKE) watch workflow=Deploy

# 수동 배포 (release 브랜치, both | firebase | test_flight)
deploy: lane ?= both
deploy:
	gh workflow run Deploy -R $(REPO) --ref release -f lane=$(lane)
	$(MAKE) watch workflow=Deploy

deploy-firebase:
	$(MAKE) deploy lane=firebase

deploy-testflight:
	$(MAKE) deploy lane=test_flight

# release → $(base) PR 머지. 머지할 커밋이 없으면 건너뛰어 재실행해도 안전.
# base 에 리뷰 승인 규칙이 있으면 머지가 거부된다 → PR URL 을 안내하고 멈춘다. 승인 후 같은 명령을 다시 실행
merge-release: base ?=
merge-release: thread ?=
merge-release:
	@test -n "$(base)" || { echo "usage: make merge-release base=master|develop"; exit 1; }
	@git fetch -q origin release $(base); \
	if [ "$$(git rev-list --count origin/$(base)..origin/release)" = "0" ]; then \
		echo "release → $(base): 머지할 커밋 없음, 건너뜀"; \
	else \
		URL=$$($(MAKE) -s open-release-pr base=$(base) thread='$(thread)'); \
		if gh pr merge -R $(REPO) "$$URL" --merge; then \
			echo "release → $(base): 머지 완료 $$URL"; \
		else \
			echo ""; echo "release → $(base) 머지가 거부됨. 리뷰 승인이 필요하면 승인 후 같은 명령을 다시 실행: $$URL"; exit 1; \
		fi; \
	fi

# release → $(base) PR 을 열고 URL 만 출력 (이미 열려 있으면 그 URL). 내부용
open-release-pr: base ?=
open-release-pr: thread ?=
open-release-pr:
	@URL=$$(gh pr list -R $(REPO) --base $(base) --head release --state open --json url -q '.[0].url'); \
	if [ -z "$$URL" ]; then \
		URL=$$(gh pr create -R $(REPO) --base $(base) --head release \
			--title "$$(REPO=$(REPO) VERSION_XCCONFIG=$(VERSION_XCCONFIG) scripts/pr-body.sh title release $(base))" \
			--body "$$(REPO=$(REPO) VERSION_XCCONFIG=$(VERSION_XCCONFIG) scripts/pr-body.sh body release $(base) '$(thread)')" 2>/dev/null); \
	fi; \
	echo "$$URL"

# 릴리스 마감: release → master 머지 → 태그·GitHub Release → release → develop 머지 → release-x.y.z 삭제
# master/develop 에 리뷰 승인 규칙이 있으면 두 PR 을 먼저 열고 멈춘다. 승인 후 같은 명령을 다시 실행하면 이어서 진행
# notes="- 항목1\n- 항목2" 를 주면 그 내용이 Release 본문, 생략하면 PR 제목으로 자동 생성
# thread=<slack url> 을 주면 PR 본문 요약에 관련 스레드 링크를 넣는다 (scripts/pr-body.sh)
release-finish: branch ?= $(shell git branch --show-current)
release-finish: notes ?=
release-finish: thread ?=
release-finish:
	@git fetch -q origin release master develop; \
	for b in master develop; do \
		if [ "$$(git rev-list --count origin/$$b..origin/release)" != "0" ]; then echo "release → $$b PR: $$($(MAKE) -s open-release-pr base=$$b thread='$(thread)')"; fi; \
	done
	$(MAKE) merge-release base=master thread='$(thread)'
	$(MAKE) github-release notes='$(notes)'
	$(MAKE) merge-release base=develop thread='$(thread)'
	@case "$(branch)" in \
		release-*) if git ls-remote --exit-code --heads origin "$(branch)" >/dev/null; then git push origin --delete "$(branch)"; else echo "$(branch) 이미 삭제됨, 건너뜀"; fi;; \
		*) echo "release-x.y.z 삭제 건너뜀 (branch=$(branch))";; \
	esac

# master 의 Version.xcconfig 버전으로 태그 + GitHub Release 생성. 이미 있으면 건너뛰어 재실행해도 안전
github-release: notes ?=
github-release:
	@git fetch -q origin master; \
	VERSION=$$(git show origin/master:Config/Version.xcconfig | sed -n 's/^MARKETING_VERSION *= *//p'); \
	test -n "$$VERSION" || { echo "origin/master 의 Config/Version.xcconfig 에서 버전을 읽지 못했습니다"; exit 1; }; \
	if gh release view -R $(REPO) "$$VERSION" >/dev/null 2>&1; then \
		echo "Release $$VERSION 이미 존재, 건너뜀"; \
	else \
		BODY="배포일\n* $$(TZ=Asia/Seoul date '+%Y/%m/%d')\n\n반영사항\n"; \
		if [ -n '$(notes)' ]; then \
			printf '%b' "$$BODY"'$(notes)' | gh release create -R $(REPO) "$$VERSION" --target master --title "$$VERSION" --notes-file -; \
		else \
			gh release create -R $(REPO) "$$VERSION" --target master --title "$$VERSION" --notes "$$(printf '%b' "$$BODY")" --generate-notes; \
		fi; \
	fi

# master 의 Version.xcconfig 버전으로 태그 + GitHub Release 생성. 이미 있으면 건너뛰어 재실행해도 안전
github-release: notes ?=
github-release:
	@git fetch -q origin master; \
	VERSION=$$(git show origin/master:Config/Version.xcconfig | sed -n 's/^MARKETING_VERSION *= *//p'); \
	test -n "$$VERSION" || { echo "origin/master 의 Config/Version.xcconfig 에서 버전을 읽지 못했습니다"; exit 1; }; \
	if gh release view -R $(REPO) "$$VERSION" >/dev/null 2>&1; then \
		echo "Release $$VERSION 이미 존재, 건너뜀"; \
	else \
		BODY="배포일\n* $$(TZ=Asia/Seoul date '+%Y/%m/%d')\n\n반영사항\n"; \
		if [ -n '$(notes)' ]; then \
			printf '%b' "$$BODY"'$(notes)' | gh release create -R $(REPO) "$$VERSION" --target master --title "$$VERSION" --notes-file -; \
		else \
			gh release create -R $(REPO) "$$VERSION" --target master --title "$$VERSION" --notes "$$(printf '%b' "$$BODY")" --generate-notes; \
		fi; \
	fi

# 재시도용: release-finish 가 develop 머지에서 멈췄을 때
release-backmerge:
	$(MAKE) merge-release base=develop

runs:
	gh run list -R $(REPO) --limit 10

watch:
	@sleep 5
	@gh run watch -R $(REPO) --exit-status --compact \
		$$(gh run list -R $(REPO) --workflow "$(workflow)" --limit 1 --json databaseId -q '.[0].databaseId')
