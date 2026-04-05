# AGENTS.md — 에이전트 실수 방지 규칙

> 이 파일은 AI 에이전트가 과거에 저질렀던 실수를 규칙으로 축적하여
> 구조적으로 재발을 방지합니다. (Mitchell Hashimoto 하네스 패턴)

## 빌드 규칙

### B-001: Swift Dictionary 초기화
```
❌ var dict: [Key: Value] = []    // Array literal, 컴파일 에러
✅ var dict: [Key: Value] = [:]   // Dictionary literal
```
빈 딕셔너리는 반드시 `[:]`를 사용한다. `[]`는 Array literal이다.

### B-002: Swift Package public 접근제어자
Private Package의 모든 exported 심볼에 `public`을 붙여야 한다.
특히 **프로토콜 준수 메서드** (URLSessionDelegate, WKNavigationDelegate 등)를
구현할 때 `public func`을 빠뜨리기 쉽다.

### B-003: project.yml 중복 방지
`packages:`, `dependencies:`, `targets:` 블록을 추가할 때
기존에 같은 키가 있는지 반드시 확인한다. YAML에서 같은 키가 2번 나오면
마지막 것만 적용되거나 xcodegen이 오류를 낸다.

## 크래시 방지 규칙

### C-001: SwiftUI ForEach + 배열 수정
`@Observable` 배열을 ForEach로 렌더링 중에 `DispatchQueue.main.asyncAfter`로
비동기 삭제하면 ForEach가 이미 사라진 인덱스를 참조하여 크래시한다.
```
❌ DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
       self.tabs.removeAll { $0.id == tabID }
   }
✅ tabs.remove(at: idx)               // 동기 삭제
✅ tabs[idx] = newTab                  // 교체 (마지막 탭일 때)
```

### C-002: 공유 상태 변수 금지
다운로드, 네트워크 요청 등 동시에 여러 개 실행될 수 있는 작업에서
단일 변수를 공유하면 덮어쓰기/참조 실패가 발생한다.
```
❌ private var pendingFilename: String?           // 모든 다운로드가 공유
✅ private var pendingFilenames: [WKDownload: String] = [:]  // per-task
```

### C-003: force unwrap (!) 금지
```
❌ let data = try await urlSession!.data(for: req)
✅ guard let session = urlSession else { throw URLError(.cancelled) }
   let data = try await session.data(for: req)
```

## 보안 규칙

### S-001: PAT 토큰 git remote URL 삽입 금지
```
❌ git remote set-url origin "https://TOKEN@github.com/..."
   → .git/config에 토큰 저장 → push 시 GitHub Secret Scanning이 감지 → 자동 revoke

✅ GIT_ASKPASS 방식:
   GIT_ASKPASS=$(mktemp) && chmod +x "$GIT_ASKPASS"
   echo '#!/bin/sh' > "$GIT_ASKPASS"
   echo 'echo "TOKEN"' >> "$GIT_ASKPASS"
   GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$GIT_ASKPASS" git push origin main
   rm -f "$GIT_ASKPASS"

✅ 태그는 API로 생성:
   curl -X POST -H "Authorization: token TOKEN" \
     "https://api.github.com/repos/OWNER/REPO/git/refs" \
     -d '{"ref":"refs/tags/vX.Y.Z","sha":"COMMIT_SHA"}'
```

### S-002: Public 레포 커밋 전 민감 정보 검사
커밋하기 전에 반드시 다음을 확인한다:
```bash
# PAT / 토큰
grep -rn "ghp_\|github_pat_" --include="*.swift" --include="*.md" --include="*.yml" --include="*.json" .
# 핑거프린팅 방어 상세 (Private에만 있어야 함)
grep -rn "Canvas.*WebGL\|seededRand\|RTCPeerConnection\|UNMASKED_VENDOR" --include="*.swift" .
# CDN 패턴 (Private에만 있어야 함)
grep -rn "videoplayback\|googlevideo\|fbcdn" --include="*.swift" .
```
하나라도 Public 코드에 있으면 커밋하지 않는다.

### S-003: README/문서에 구현 상세 금지
Public 레포 문서에 다음을 절대 포함하지 않는다:
- 핑거프린팅 방어 벡터 목록 (Canvas, WebGL, AudioContext 등)
- 다운로드 기법 상세 (XHR 인터셉트, Blob 후킹, CDN 패턴)
- 피싱 탐지 규칙/키워드
- 파일 구조 전체 트리
- 미구현 기능 (VPN 등)

### S-004: git filter-branch 후 반드시 refs/original 정리
```bash
git for-each-ref --format='%(refname)' refs/original/ | while read ref; do
  git update-ref -d "$ref"
done
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```
정리하지 않으면 GitHub 서버에 dangling objects가 남아 Secret Scanning에 감지된다.

## 로직 규칙

### L-001: iOS 갤러리 파일명 매칭 금지
iOS는 PHPhotoLibrary에 저장할 때 파일명을 자체적으로 변경한다.
파일명으로 PHAsset을 찾으면 매칭 실패한다.
```
❌ 파일명 매칭: originalFilename == downloadedFilename
✅ PHAsset ID 추적: PHObjectPlaceholder.localIdentifier 저장 후
   PHAsset.fetchAssets(withLocalIdentifiers:)로 정확 삭제
```

### L-002: 중복 다운로드 방지
같은 URL이 navigationResponse(.download)와 startWKDownload() 양쪽에서
트리거되면 갤러리에 2개씩 저장된다.
```
✅ recentlyDownloadedURLs: Set<String>으로 5분 내 동일 URL 차단
```

### L-003: ElementHider 페이지 격리
CSS 셀렉터(`.ad-banner` 등)는 같은 host의 다른 페이지에서도 매칭될 수 있다.
```
❌ host 전체 매칭 + host+path 매칭 합산
✅ host+path 정확 매칭만 (해당 페이지에서만 적용)
```

## CI/CD 규칙

### CI-001: macOS 빌드 분 관리
macOS 러너는 10x 과금. Private 레포 Free 2,000분 = 실제 200분.
```
✅ Public 레포 사용 (무제한 무료)
✅ 태그 push 시에만 빌드 (push 시마다 빌드 X)
✅ workflow_dispatch 수동 빌드 유지
```

### CI-002: Private Package 접근
```
✅ CORE_PAT를 GitHub Secrets에 저장
✅ CI에서 git config --global url 오버라이드
❌ Package.swift URL에 토큰 직접 삽입
```
