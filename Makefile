REPO := JunHyeok0206/iOS-release-pipeline-sandbox

generate:
	mise install
	mise x -- tuist generate

# 릴리스 시작: develop 에서 release-x.y.z 생성 + x.y.z (0) 커밋
release-start:
	@test -n "$(version)" || { echo "usage: make release-start version=x.y.z"; exit 1; }
	gh workflow run "Release Start" -R $(REPO) -f version=$(version)
	$(MAKE) watch workflow="Release Start"

# QA 배포: release-x.y.z → release PR 머지 (merge commit) → Deploy (Firebase + TestFlight)
qa-deploy: branch ?= $(shell git branch --show-current)
qa-deploy:
	@case "$(branch)" in release-*) ;; *) echo "release-x.y.z 브랜치여야 합니다 (현재: $(branch))"; exit 1;; esac
	gh pr create -R $(REPO) --base release --head $(branch) --title "QA $(branch)" --body "" || true
	gh pr merge -R $(REPO) $(branch) --merge
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

# release → $(base) PR 머지. 머지할 커밋이 없으면 건너뛰어 재실행해도 안전
merge-release: base ?=
merge-release:
	@test -n "$(base)" || { echo "usage: make merge-release base=master|develop"; exit 1; }
	@git fetch -q origin release $(base); \
	if [ "$$(git rev-list --count origin/$(base)..origin/release)" = "0" ]; then \
		echo "release → $(base): 머지할 커밋 없음, 건너뜀"; \
	else \
		gh pr create -R $(REPO) --base $(base) --head release --title "release → $(base)" --body "" || true; \
		gh pr merge -R $(REPO) release --merge; \
	fi

# 릴리스 마감: release → master (태그·GitHub Release) → release → develop → release-x.y.z 삭제
release-finish: branch ?= $(shell git branch --show-current)
release-finish:
	$(MAKE) merge-release base=master
	$(MAKE) watch workflow="Release Note"
	$(MAKE) merge-release base=develop
	@case "$(branch)" in release-*) git push origin --delete "$(branch)";; *) echo "release-x.y.z 삭제 건너뜀 (branch=$(branch))";; esac

# 재시도용: release-finish 가 develop 머지에서 멈췄을 때
release-backmerge:
	$(MAKE) merge-release base=develop

runs:
	gh run list -R $(REPO) --limit 10

watch:
	@sleep 5
	@gh run watch -R $(REPO) --exit-status --compact \
		$$(gh run list -R $(REPO) --workflow "$(workflow)" --limit 1 --json databaseId -q '.[0].databaseId')
