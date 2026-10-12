# iOS-release-pipeline-sandbox

`release`(배포 전용) + `release-x.y.z`(QA 작업) 브랜치 모델과 GitHub Actions 배포 파이프라인을 검증하는 테스트 레포.
빌드는 시뮬레이터까지만 하고 Firebase / TestFlight 업로드는 stub 이다.

## 1. 구성

| 경로 | 역할 |
|---|---|
| `Project.swift` | Tuist 4.12.1. 앱 `TestApp` + 위젯 `TestWidget` |
| `Config/Version.xcconfig` | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. 두 Info.plist 가 `$(…)` 로 참조. **CI 만 수정** |
| `fastlane/Fastfile` | `bump`, `firebase`(stub), `test_flight`(stub) |
| `Makefile` | 아래 명령어 표. 태그·GitHub Release 도 여기서 만든다 (`github-release`) |
| `.github/workflows/release-start.yml` | 릴리스 시작 (3절) |
| `.github/workflows/deploy.yml` | 배포 (5절) |

## 2. 브랜치와 흐름

![GitHub Actions 흐름](docs/github-actions-flow.png)

```
develop ─┬─ make release-start version=1.0.1
         │     ├─ release-1.0.1 생성 (develop 과 같은 커밋, 버전 커밋 없음)
         │     ├─ release 에 머지
         │     └─ Deploy 실행 → release 에 "1.0.1 (1)" 커밋 → Firebase + TestFlight
         │
         │  QA 수정: fix/* → PR → release-1.0.1
         │  빌드 필요할 때: make qa-deploy branch=release-1.0.1  → "(2)", "(3)" …
         │
         │  마지막 qa-deploy 빌드가 제출 빌드다
         └─ make release-finish branch=release-1.0.1 notes="- 항목1\n- 항목2"
               → release → master 머지 → 태그·GitHub Release 생성 → release → develop 머지 → release-1.0.1 삭제
```

| 브랜치 | 역할 | 누가 커밋하나 |
|---|---|---|
| `develop` | 기능 개발 | 개발자 (PR) |
| `release-x.y.z` | 버전별 QA 작업. 수정 PR 의 base. **Version.xcconfig 를 건드리지 않는다** | 개발자 (PR) |
| `release` | 배포 전용. 여기 push 되면 Deploy 가 돈다 | **머지 커밋과 CI 의 bump 커밋만** |
| `master` | 기본 브랜치, 상용 | `make release-finish` |

## 3. 명령어

레포 루트에서 실행한다. `gh auth login` 이 되어 있어야 한다. GitHub 웹의 Actions → Run workflow 로도 같은 일을 할 수 있다.

| 명령 | 하는 일 |
|---|---|
| `make release-start version=x.y.z` | 릴리스 시작. 브랜치 생성 + `release` 머지 + 첫 배포 `(1)` |
| `make qa-deploy [branch=release-x.y.z]` | QA 수정분 배포. `release-x.y.z → release` PR 머지 → Deploy. branch 생략 시 현재 브랜치 |
| `make deploy [lane=both\|firebase\|test_flight]` | 코드 변경 없이 재배포. 빌드 번호만 +1 |
| `make deploy-firebase` / `make deploy-testflight` | 위의 단축 |
| `make release-finish [branch=release-x.y.z] [notes="…"]` | 마감. `release → master` 머지 → 태그·GitHub Release 생성 → `release → develop` 머지 → `release-x.y.z` 삭제. 재실행해도 안전(이미 머지된 방향·이미 있는 Release 는 건너뜀) |
| `make github-release [notes="…"]` | master 의 `Version.xcconfig` 버전으로 태그 + GitHub Release 만 생성. `release-finish` 가 내부에서 쓴다 |
| `make release-backmerge` | 재시도용. `release → develop` 머지만 |
| `make merge-release base=master\|develop` | `release → base` PR 머지 한 방향. 위 두 타깃이 내부에서 쓴다 |
| `make runs` | 최근 실행 10개 |
| `make watch workflow=Deploy` | 해당 워크플로의 최신 run 을 따라가며 출력 |
| `make generate` | 로컬 Tuist 프로젝트 생성 |

## 4. 릴리스 한 사이클

### 4.1 시작
```bash
make release-start version=1.0.1
```
- `release-1.0.1` 이 develop 의 현재 커밋에서 만들어진다. **버전 커밋은 없다.** 로컬에서 이 브랜치를 빌드하면 이전 버전 번호가 보이는데 정상이다.
- `release` 에 머지되고 Deploy 가 `version=1.0.1` 로 실행되어 `release` 에 `Bump version to iOS 1.0.1 (1)` 커밋이 생기고 Firebase 와 TestFlight 로 나간다.
- `make` 는 Release Start 까지만 기다린다. 이어지는 Deploy 는 `make watch workflow=Deploy` 로 본다.

### 4.2 QA 수정
```bash
git fetch origin
git checkout -b fix/some-bug origin/release-1.0.1
# 수정, 커밋
gh pr create --base release-1.0.1
```
- base 는 반드시 `release-1.0.1`. develop 이 아니다.
- `Config/Version.xcconfig` 는 건드리지 않는다 (6절).

### 4.3 QA 빌드 배포
```bash
make qa-deploy branch=release-1.0.1
```
- 수정 PR 이 몇 개 쌓였든 이 명령 한 번이 빌드 하나다. 필요할 때만 실행해 빌드 수를 조절한다.
- 빌드 번호는 `release` 에서 +1 된다. `release-1.0.1` 의 번호는 바뀌지 않는다.
- 같은 브랜치에서 연속으로 실행하면 앞선 run 은 취소된다 (최신 커밋만 빌드). 앞선 run 의 bump 가 이미 push 됐으면 그 번호는 빌드 없이 건너뛴다.

### 4.4 마감
```bash
make release-finish branch=release-1.0.1 notes="- 항목 1\n- 항목 2"
```
- 마지막 `qa-deploy` 빌드가 제출 빌드다. 마감 전에 별도 빌드를 만들지 않는다.
- `release-finish` 는 master 머지 → 태그 `1.0.1` + GitHub Release 생성 → develop 머지 → `release-1.0.1` 삭제를 순서대로 한다.
- Release 본문은 `배포일` + `반영사항` 형식이다. `notes` 의 `\n` 은 줄바꿈으로 바뀐다. `notes` 를 생략하면 머지된 PR 제목으로 자동 생성한다.
- 버전은 머지 후 master 의 `Config/Version.xcconfig` 에서 읽는다. 태그는 master 의 머지 커밋을 가리킨다.
- 두 머지 모두 merge commit 이다. squash 하지 않는다.
- 중간에 멈추면 그대로 다시 실행한다. 이미 머지된 방향은 "머지할 커밋 없음" 으로 건너뛴다. develop 머지만 다시 하려면 `make release-backmerge`.

### 4.5 hotfix (미구현)
master(태그)에서 `release-x.y.z` 를 분기하는 것만 다르고 나머지 흐름은 같다. 현재 `release-start` 는 develop 에서만 분기하므로, 필요해지면 워크플로에 `base` 입력(기본 develop)을 추가한다.

## 5. CI 가 하는 일

### Release Start (`release-start.yml`, ubuntu)
1. `x.y.z` 형식 검사, 같은 이름의 브랜치가 있으면 중단
2. develop 에서 `release-x.y.z` 생성
3. `release` 에 `--no-ff` 머지 후 push
4. Deploy 를 `lane=both version=x.y.z` 로 실행 (GITHUB_TOKEN push 는 워크플로를 트리거하지 않으므로 직접 dispatch)

### Deploy (`deploy.yml`)
| job | 러너 | 내용 |
|---|---|---|
| `bump` | ubuntu | `release` 가 아니면 중단. 버전 결정(아래) → `Config/Version.xcconfig` 수정 → `release` 에 push |
| `build (firebase)` | macos-26 | bump 커밋 체크아웃 → Xcode 26.6 → Tuist generate → `fastlane ios firebase` |
| `build (test_flight)` | macos-26 | 위와 같고 `fastlane ios test_flight` |

버전 결정 규칙:
1. dispatch 입력 `version` 이 있으면 그 값
2. 없으면 HEAD 커밋 메시지에서 `release-x.y.z` 를 찾는다 (PR 머지 커밋에는 head 브랜치 이름이 들어 있다)
3. 둘 다 없으면 현재 값 유지
4. 결정된 값이 현재 `MARKETING_VERSION` 과 **다르면** `x.y.z (1)`, **같으면** 빌드 번호 +1

bump 커밋은 GITHUB_TOKEN 으로 push 되므로 Deploy 가 다시 돌지 않는다. `concurrency` 로 같은 브랜치의 이전 run 은 취소된다. bump job 은 10초대에 끝나므로 취소는 대개 build job 에서 일어나고, 그때 이미 push 된 빌드 번호는 비게 된다 (단조 증가만 유지되면 문제 없음).

### 태그·GitHub Release (Makefile `github-release`)
워크플로가 아니라 `release-finish` 가 로컬에서 `gh release create` 로 만든다. master 머지 직후 동기로 실행되므로 실패가 바로 보인다. 같은 버전의 Release 가 이미 있으면 건너뛴다.

## 6. 지켜야 할 규칙

1. **`Config/Version.xcconfig` 는 CI 만 수정한다.** 로컬에서 `fastlane ios bump` 를 돌려 push 하지 않는다. 어기면 다음 머지에서 충돌한다.
2. **머지는 전부 merge commit.** `release-x.y.z → release`, `release → master`, `release → develop` 모두. squash·rebase 금지.
3. **`release` 에 직접 push 하지 않는다.** PR 머지와 CI 커밋만 들어간다.
4. **한 번에 한 버전만.** 이전 버전이 master 로 나가기 전에 다음 `release-start` 를 하지 않는다.
5. **QA 수정 브랜치는 `origin/release-x.y.z` 에서 분기**하고 base 도 거기로.
6. back-merge 를 생략해도 충돌은 나지 않지만, develop 이 구버전 번호를 갖게 되므로 사이클마다 한다.

## 7. 검증 시나리오

1. `make release-start version=1.0.1`
   - `release-1.0.1` 브랜치가 develop 과 같은 커밋으로 생성됨 (버전 커밋 없음)
   - `release` 에 merge commit 이 push 되고, 워크플로가 Deploy 를 `version=1.0.1` 로 직접 실행
   - Deploy: `bump` 가 `Bump version to iOS 1.0.1 (1)` 을 `release` 에 push, 그 push 로 Deploy 가 다시 실행되지 않음
   - `build (firebase)` 와 `build (test_flight)` 가 동시에 실행되고 둘 다 `(1)` 을 빌드. `xcodebuild -version` 이 `Xcode 26.6`
2. `release-1.0.1` 에 커밋 1개 push → `make qa-deploy branch=release-1.0.1` → `(2)`
3. 커밋 2개를 push 하고 `make qa-deploy` 를 두 번 연속 실행 → 첫 run 의 `build` job 이 `cancelled`, 두 번째가 `(4)`
   - 첫 run 의 `bump` 는 10초대에 끝나 `(3)` 을 이미 push 한 뒤라 취소되지 않는다. `(3)` 은 빌드되지 않은 채 건너뛴 번호로 남는다
4. `make deploy-testflight` → `(5)`, `build (test_flight)` 만 실행
   - `gh workflow run Deploy -R JunHyeok0206/iOS-release-pipeline-sandbox --ref develop -f lane=both` 는 `bump` 첫 step 에서 실패
5. `make release-finish branch=release-1.0.1 notes="- QA 수정 1\n- QA 수정 2"` → master 머지, 태그 `1.0.1` + GitHub Release(배포일·반영사항), develop back-merge(`Version.xcconfig` 가 `1.0.1`/`5`), `release-1.0.1` 삭제
   - 같은 명령을 다시 실행하면 세 단계 모두 "건너뜀" 으로 끝난다
6. `make release-start version=1.0.2` → 충돌 없이 `release` 에 머지되고 Deploy 가 `1.0.2 (1)`
7. 충돌 내성 확인: `release-1.0.2` 에서 `TestApp/Resources/Info.plist` 의 아무 키나 수정해 push → `make qa-deploy` 가 충돌 없이 머지됨 (버전이 xcconfig 로 분리됐기 때문)
8. 실패 재현: `release-1.0.2` 에서 로컬로 `bundle exec fastlane ios bump` 후 push → PR 에 `Config/Version.xcconfig` 충돌 표시 (규칙 위반 케이스)

## 8. 자주 묻는 것

**왜 `release-1.0.1` 에는 버전 커밋이 없나?**
`release-x.y.z` 와 `release` 가 같은 줄을 서로 다르게 바꾸면 머지가 충돌한다. 버전은 `release` 한 곳에서만 바꾸도록 했다. 그래서 `release-x.y.z` 의 `Version.xcconfig` 는 항상 develop 과 같고, git 이 `release` 쪽 값을 그대로 가져간다.

**왜 버전이 별도 파일인가?**
Info.plist 안에 있으면 QA 수정이 바로 옆 줄을 고쳤을 때 충돌한다. 파일을 분리하면 그 가능성이 사라진다.

**첫 배포가 (1) 인 이유는?**
`release-start` 가 Deploy 를 `version=x.y.z` 로 실행하고, Deploy 는 버전이 바뀌면 (1) 부터 시작한다. 이후 머지마다 +1.

**TestFlight 만 다시 올리고 싶다.**
`make deploy-testflight`. 빌드 번호는 +1 되고 Firebase 는 건너뛴다.

**`develop` 에서 Deploy 를 실행하면?**
첫 step 에서 실패한다. `release` 에서만 돈다.

**Deploy 가 두 번 돌았다.**
`release` 에 사람이 직접 push 했거나 PAT 로 push 한 경우다. 규칙 3 위반.

## 9. 문제 해결

| 증상 | 원인 / 조치 |
|---|---|
| `release-x.y.z 브랜치가 이미 있습니다` | 같은 버전을 두 번 시작. 브랜치를 지우고 다시 하거나 버전을 바꾼다 |
| `gh run watch` 가 run ID 를 요구 | `make watch workflow=…` 를 쓴다 (최신 run 을 찾아 준다) |
| PR 에 `Config/Version.xcconfig` 충돌 | 누군가 `release-x.y.z` 나 develop 에서 버전을 바꿨다. 해당 커밋에서 그 파일 변경만 되돌린다 |
| bump 커밋 push 가 거부됨 | `release` 에 보호 규칙(PR 필수)이 걸려 있다. 이 모델에서는 삭제·force-push 차단만 건다 |
| Actions 탭이 비어 보임 | 실행 이력이 0 개면 그렇게 보인다. `make runs` 또는 워크플로 URL 로 직접 접근 |
| `make release-start` 가 `No rule to make target` | 다른 디렉터리다. 레포 루트에서 실행 |
| `release-finish` 가 중간에 멈춤 | 그대로 다시 실행. 이미 머지된 방향은 "머지할 커밋 없음", 이미 만든 Release 는 "이미 존재" 로 건너뛴다. develop 머지만 다시 하려면 `make release-backmerge` |
| `gh release create` 가 tag already exists | 같은 버전 태그가 있다. 버전이 맞는지 확인하고, 재배포면 태그를 지우거나 버전을 올린다 |
| `gh pr merge` 가 "no pull requests found" | 같은 head 로 열린 PR 이 없다. `make merge-release base=…` 가 PR 생성부터 다시 한다 |

## 10. 로컬

```bash
mise install
mise x -- tuist generate
bundle install
bundle exec fastlane ios bump version:1.0.0 build:0   # 동작 확인용. 결과 커밋은 push 하지 않는다 (Version.xcconfig 는 CI 만 수정)
```
