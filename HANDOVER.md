# GhostStream iOS 브라우저 — 최종 인수인계서 v1.1.1

**작성일:** 2026-03-30  
**버전:** v1.1.1 (build 20)  
**GitHub:** github.com/krstock-master/ghoststream (Private)  
**PAT 토큰:** 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  
**번들 ID:** com.ghoststream.browser  
**플랫폼:** iOS 17.0+ / SideStore·TrollStore Sideload  
**코드:** 61 commits, 25 Swift files, 6,049줄, 23 릴리즈  
**최신 IPA:** https://github.com/krstock-master/ghoststream/releases/download/v1.1.1/GhostStream.ipa (595KB)

---

## 1. 프로젝트 개요

GhostStream은 프라이버시 중심의 iOS 미디어 브라우저로, 알로하(Aloha)·삼성 브라우저와 동일한 영상 다운로드 기능을 갖춘 Sideload 전용 앱입니다. WKWebView 기반으로 광고 차단, 11-벡터 핑거프린팅 방어, AES-256 보안 폴더, HLS/MP4 다운로드를 제공합니다.

---

## 2. 이번 세션 완료 작업 전체 목록

### 사전 작업
| # | 작업 | 산출물 |
|---|------|--------|
| 0-1 | 인기 브라우저 UI/UX 구글링 + 장점 흡수 검토 | 분석보고서 파트 A |
| 0-2 | 핑거프린팅 방어 강화 적용 가능성 검토 | 분석보고서 파트 B-1 |
| 0-3 | On-device ML 피싱 필터링 적용 가능성 검토 | 분석보고서 파트 B-2 |
| 0-4 | Fake UA 스위칭 적용 가능성 검토 | 분석보고서 파트 B-3 |

### 즉시 수정 (v0.9.6 패치, 4건)
| # | 작업 | 상태 | 파일 |
|---|------|:---:|------|
| 1 | 보안폴더 저장 시 원본 파일 삭제 | ✅ | DownloadSheetView.swift |
| 2 | 보안폴더 저장 시 갤러리(PHAsset) 삭제 | ✅ | DownloadSheetView.swift |
| 3 | OnboardingView/VPNView 미사용 파일 삭제 | ✅ | 삭제 (PrivacyDashboardView 분리 복구) |
| 4 | Pull-to-Refresh (Safari/Chrome 스타일) | ✅ | BrowserWebView.swift, WebViewManager.swift |

### Phase 1 — v1.0.0 (10건)
| # | 작업 | 상태 | 파일 |
|---|------|:---:|------|
| 5 | Fake UA 스위칭 (세션별 랜덤 iPhone 프로필) | ✅ | DeviceProfile.swift, BrowserWebView.swift |
| 6 | 핑거프린팅 방어 7→11 벡터 강화 | ✅ | PrivacyEngine.swift |
| 7 | Fire Button (DuckDuckGo 스타일 즉시 삭제) | ✅ | BrowserContainerView.swift |
| 8 | 데스크톱 모드 토글 | ✅ | BrowserContainerView.swift |
| 9 | YouTube PiP 백그라운드 재생 | ✅ | BrowserContainerView.swift |
| 10 | 페이지 내 검색 (Find in Page) | ✅ | BrowserContainerView.swift |
| 12 | 새 탭 프라이버시 통계 카드 | ✅ | BrowserContainerView.swift (NewTabPage) |
| 13 | 피싱 URL 규칙 기반 필터 (10-벡터) | ✅ | PhishingDetector.swift |
| 14 | 쿠키 배너 자동 거부 | ✅ | WebViewManager.swift (mainJS) |
| — | 설정 확장 (주소바 위치, 쿠키, 프로필) | ✅ | SettingsView.swift |

### Phase 2 — v1.1.0 (5건)
| # | 작업 | 상태 | 파일 |
|---|------|:---:|------|
| 16 | 북마크 + 방문 기록 | ✅ | BookmarkManager.swift, BookmarkHistoryView.swift |
| 17 | 탭 썸네일 미리보기 | ✅ | BrowserSheets.swift, TabManager.swift |
| 18 | Reader Mode (리더 모드) | ✅ | ReaderModeView.swift |
| 19 | 주소바 스크롤 연동 (축소/확장) | ✅ | BrowserWebView.swift |
| 20 | 다운로드 큐 (동시 3개 제한) | ✅ | MediaDownloadManager.swift |

### 사용자 피드백 수정 — v1.1.1 (2건)
| # | 작업 | 상태 | 파일 |
|---|------|:---:|------|
| F1 | 보안폴더 저장 시 갤러리 삭제 안 되는 문제 | ✅ | DownloadSheetView.swift |
| F1+ | 보안폴더 "갤러리로 내보내기" 버튼 직접 노출 | ✅ | DownloadSheetView.swift |
| F2 | 앱 아이콘 불일치 (iOS 캐시) | ✅ 진단 | 앱 삭제 후 재설치로 해결 |

### CI/CD 수정 (3건)
| # | 작업 | 상태 |
|---|------|:---:|
| CI-1 | PrivacyDashboardView 빌드 에러 복구 | ✅ |
| CI-2 | macos-15 → macos-14 러너 변경 | ✅ |
| CI-3 | push 빌드 제거 → 태그만 빌드 (분 절약) | ✅ |

---

## 3. 핵심 아키텍처

### 3.1 다운로드 엔진

```
[다운로드 흐름]
JS 감지 → downloadVideo/alohaDownload 메시지
→ WebViewCoordinator.startWKDownload()
→ WKWebView.startDownload(using: URLRequest)
→ WKDownloadDelegate (HTTP 검증 + MIME 검증)
→ PHPhotoLibrary 자동 갤러리 저장

[다운로드 큐 — v1.1.0]
요청 → activeCount < 3 ? 즉시 시작 : pendingQueue 대기
완료 시 → processQueue() → 대기 다운로드 자동 시작
```

### 3.2 DeviceProfile 시스템

```
[앱 시작]
DeviceProfileManager.shared → 랜덤 iPhone 프로필 선택
  ├── userAgent → WKWebView.customUserAgent
  ├── screenWidth/Height → PrivacyEngine JS (screen.width/height)
  ├── pixelRatio → PrivacyEngine JS (devicePixelRatio)
  ├── hardwareConcurrency → PrivacyEngine JS (navigator.hardwareConcurrency)
  └── maxTouchPoints → PrivacyEngine JS (navigator.maxTouchPoints)

[세션 동안 동일 프로필 유지]
[Fire Button 시 → refreshProfile() → 새 프로필]
[데스크톱 모드 → DeviceProfile.desktop 사용]

프로필 풀: iPhone 16 Pro, 15, 14, SE 3, 13 mini
```

### 3.3 핑거프린팅 방어 11-벡터

| # | 벡터 | v0.9.5 | v1.1.1 |
|---|------|:---:|:---:|
| 1 | Canvas 노이즈 | ✅ 랜덤 | ✅ 세션 고정 시드 |
| 2 | WebGL 스푸핑 | ✅ | ✅ |
| 3 | AudioContext 노이즈 | ✅ | ✅ 세션 시드 |
| 4 | Font Enumeration 방어 | ✅ | ✅ |
| 5 | Navigator 속성 | ✅ 하드코딩 | ✅ 프로필 기반 |
| 6 | Screen 속성 | ✅ 하드코딩 | ✅ 프로필 기반 |
| 7 | 고정밀 타이머 | ✅ | ✅ |
| 8 | Battery API | ✅ | ✅ |
| 9 | **WebRTC IP 누출** | ❌ | ✅ STUN 서버 제거 |
| 10 | **NetworkInformation** | ❌ | ✅ 4g/10Mbps 고정 |
| 11 | **Speech Synthesis** | ❌ | ✅ 빈 배열 |

### 3.4 피싱 URL 탐지 (10-벡터 규칙 기반)

서버 통신 없음. URL 문자열만 분석:
화이트리스트 → 의심TLD(24종) → IP주소 → 서브도메인 → 키워드(20종) → URL길이 → @기호 → 브랜드사칭(10종) → 특수문자 → 엔트로피
→ safe / suspicious / phishing → 주소바 아이콘 + 경고 오버레이

### 3.5 Cloudflare 바이패스 (3중 보호)

```
1. sessionStorage.__gs_cf_bypass 플래그 → JS 스킵
2. cfStrippedDomains 세트 → 도메인별 1회만 스트립
3. cfReloadPending → 무한 리로드 방지
```

### 3.6 JS 인젝션 (2단계)

- **earlyJS** (atDocumentStart, forMainFrameOnly: false): XHR/fetch 인터셉터, Performance API, HTMLMediaElement.src setter, Blob URL 캡처
- **mainJS** (atDocumentEnd, forMainFrameOnly: false): 비디오 버튼 UI, scanAll(), 전체화면 이벤트, 광고 제거 MutationObserver, JW Player, **쿠키 배너 자동 거부**

### 3.7 보안폴더 갤러리 삭제 (v1.1.1 수정)

```
보안폴더 저장 → 원본 파일 삭제 (FileManager)
→ 갤러리 삭제: readWrite 권한 요청
→ 1차: 최근 10분 내 + 같은 미디어타입에서 파일명 매칭
→ 2차: 실패 시 가장 최근 에셋 삭제 (방금 다운로드한 것)
→ iOS 삭제 확인 팝업 표시
```

---

## 4. 파일 구조 (v1.1.1 — 25 files, 6,049줄)

| 파일 | 줄수 | 역할 | 신규 |
|------|------|------|:---:|
| App/GhostStreamApp.swift | 41 | @main, 테마, Environment | |
| App/DI/Container.swift | 47 | 8개 서비스 DI | |
| Browser/WebViewManager.swift | 824 | ★핵심: Coordinator + JS + WKDownload | |
| Browser/BrowserWebView.swift | 112 | UIViewRepresentable + ScrollDelegate | |
| Browser/TabManager.swift | 198 | Tab + 썸네일 + DetectedMedia | |
| Browser/BookmarkManager.swift | 194 | 북마크+방문기록 | ★ |
| Media/MediaDownloadManager.swift | 612 | URLSession + HLS + 큐(3개) | |
| Privacy/DeviceProfile.swift | 80 | UA+Screen 일관성 프로필 | ★ |
| Privacy/PhishingDetector.swift | 111 | 10-벡터 피싱 탐지 | ★ |
| Privacy/PrivacyEngine.swift | 210 | 11-벡터 핑거프린트 방어 | |
| Privacy/ContentBlockerManager.swift | 293 | 75개 WKContentRuleList | |
| Privacy/DNSManager.swift | 87 | DoH | |
| Privacy/SecurityManager.swift | 130 | 탈옥 감지 + 인증서 핀닝 | |
| UI/Browser/BrowserContainerView.swift | 645 | ★메인 UI (전 기능 통합) | |
| UI/Components/DownloadSheetView.swift | 794 | 3탭 + 보안폴더 액션 버튼 | |
| UI/Components/BrowserSheets.swift | 305 | Privacy리포트 + 탭그리드(썸네일) | |
| UI/Components/BookmarkHistoryView.swift | 189 | 북마크/기록 시트 | ★ |
| UI/Components/ReaderModeView.swift | 143 | Reader Mode + JS 추출 | ★ |
| UI/Components/FullscreenDownloadOverlay.swift | 140 | UIWindow 전체화면 바 | |
| UI/Components/PrivacyDashboardView.swift | 128 | 프라이버시 대시보드 | |
| UI/Settings/SettingsView.swift | 168 | 설정 (프로필, 쿠키 등) | |
| UI/Vault/VaultView.swift | 145 | Vault UI | |
| Vault/VaultManager.swift | 243 | AES-256-GCM + Face ID | |
| Extensions/Extensions.swift | 69 | glass() modifier 등 | |
| Tests/GhostStreamTests.swift | 141 | 테스트 | |

---

## 5. 해결된 핵심 버그들 (전 버전 포함)

| 버전 | 버그 | 근본 원인 | 해결 |
|------|------|----------|------|
| v0.9.1 | 다운로드 13bytes/s | URLSession에 쿠키 없음 → CDN 거부 | WKWebView.startDownload 통일 |
| v0.9.1 | "Cannot Open" | HTML이 .mp4로 저장 | HTTP 응답 + MIME 검증 |
| v0.9.2 | 전체화면 바 1초 | CSS fullscreenchange → __hide_overlay__ | __hide_overlay__ 제거 |
| v0.9.3 | 영상 1개만 감지 | forMainFrameOnly: true | false + MutationObserver |
| v0.9.3 | 갤러리 저장 안 됨 | completion handler nil | PHPhotoLibrary.performChanges |
| v0.9.3 | 뒤로가기 안 됨 | .disabled() 터치 차단 | opacity만 비활성 표시 |
| v1.0.0 | PrivacyDashboardView 누락 | VPNView.swift에 정의 → 삭제됨 | 별도 파일로 분리 복구 |
| v1.1.1 | 보안폴더 갤러리 삭제 안 됨 | iOS가 파일명 변경 → 매칭 실패 | 날짜+미디어타입 매칭 |

---

## 6. 빌드 & 배포

### GitHub Actions CI/CD

```
태그 push (v*) → xcodegen → Simulator Build → Archive → IPA → Release 자동
macOS-14 러너 사용 (push 빌드 제거 — 분 절약)
```

**GitHub Pro 결제됨** — 3,000분/월 (macOS 10x = 빌드 약 100회)

### 로컬 빌드

```bash
brew install xcodegen
cd ghoststream && xcodegen generate
open GhostStream.xcodeproj
# Xcode → Product → Archive → Distribute (Ad Hoc)
```

---

## 7. 다음 세션 — 앞으로 할 작업

### Phase 3 — v2.0+ (차별화)

| # | 작업 | 난이도 | 시간 | 비고 |
|---|------|--------|------|------|
| 15 | Core ML 피싱 모델 통합 | 상 | 4~6시간 | PhishTank 학습 → .mlmodel |
| 21 | 내장 미디어 플레이어 (커스텀 AVPlayerVC) | 상 | 3~4시간 | 재생 속도, 구간 반복, 자막 |
| 22 | 국제화 (영어, 일본어) | 중 | 2시간 | Localizable.strings 확장 |
| 23 | AltStore/SideStore 소스 JSON 업데이트 | 하 | 30분 | v0.7.1 → v1.1.1 |
| 24 | 접근성 (VoiceOver) | 중 | 2시간 | accessibilityLabel |
| 25 | 탭 그룹 (Vivaldi 스타일) | 중 | 1~2시간 | TabManager 확장 |
| 26 | Haptic 피드백 강화 | 하 | 20분 | UIImpactFeedbackGenerator |
| 27 | Quick Link 편집 기능 | 하 | 30분 | NewTabPage 커스텀 |
| 28 | 다운로드 일시정지/재개 UI 개선 | 중 | 1시간 | |
| 29 | Public/Private 레포 구조 분리 | 중 | 3~4시간 | Swift Package 분리 |

### 버그/개선 백로그

| # | 작업 | 우선순위 |
|---|------|:---:|
| B1 | ghoststream-source.json v0.7.1 → v1.1.1 업데이트 | ★★★★★ |
| B2 | source.json downloadURL placeholder 수정 | ★★★★★ |
| B3 | @Observable + didSet 조합 Swift 6 경고 대응 | ★★★☆☆ |
| B4 | SecTrustEvaluate deprecated 경고 수정 | ★★☆☆☆ |

---

## 8. 다음 세션 체크리스트

1. 이 인수인계서 업로드
2. GitHub PAT 토큰: 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
3. 테스트 기기 iOS 버전 확인
4. Phase 3 우선순위 피드백
5. 사용자 피드백 전달 (있으면)

---

## 9. 버전 히스토리

| 버전 | 주요 변경 |
|------|----------|
| v0.5.0 | 초기 릴리즈 — JW Player 감지, 기본 다운로드 |
| v0.6.x | 광고 차단 75규칙, HLS 파서, 보안 폴더 |
| v0.7.x | Privacy DNS, 핑거프린팅 방어, UI 개선 |
| v0.8.0 | JS 2단계 분리 (earlyJS + mainJS), Performance API |
| v0.8.1 | Chrome/Brave 스타일 UI 재설계 |
| v0.9.0 | UIWindow 전체화면 복원 |
| v0.9.1 | ★ WKWebView.startDownload 도입 (다운로드 핵심 해결) |
| v0.9.2 | 모든 다운로드 WKDownload 통일, CSS __hide_overlay__ 제거 |
| v0.9.3 | 갤러리 자동 저장, FAB→하단바, 뒤로가기 수정 |
| v0.9.4 | 보안폴더 피드백 토스트, 테마 선택 |
| v0.9.5 | 앱 아이콘 리디자인, New Tab Page 검색바 |
| **v1.0.0** | **Phase 1: UA스위칭, 핑거프린트11벡터, Fire, PiP, Find, 피싱필터, 쿠키배너** |
| **v1.1.0** | **Phase 2: 북마크, 썸네일, Reader Mode, 스크롤연동, 다운로드큐** |
| **v1.1.1** | **피드백 수정: 갤러리삭제 매칭, 보안폴더 내보내기 버튼, CI 안정화** |
