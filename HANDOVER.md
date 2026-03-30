# GhostStream iOS 브라우저 — 최종 인수인계서

**작성일:** 2025-03-30  
**현재 버전:** v0.9.5 (build 18)  
**GitHub:** github.com/krstock-master/ghoststream (Private)  
**PAT 토큰:** <PRIVATE>  
**번들 ID:** com.ghoststream.browser  
**플랫폼:** iOS 17.0+ / SideStore·TrollStore Sideload  
**코드:** 54 commits, 21 Swift files, ~4,850줄, 20 릴리즈  

---

## 1. 프로젝트 개요

GhostStream은 프라이버시 중심의 iOS 미디어 브라우저로, 알로하(Aloha)·삼성 브라우저와 동일한 영상 다운로드 기능을 갖춘 Sideload 전용 앱입니다. WKWebView 기반으로 광고 차단, 핑거프린팅 방어, AES-256 보안 폴더, HLS/MP4 다운로드를 제공합니다.

---

## 2. 핵심 아키텍처 (반드시 숙지)

### 2.1 다운로드 엔진 — 가장 중요한 부분

**★ WKWebView.startDownload(using:) 가 핵심 다운로드 방법입니다.**

이전 URLSession.downloadTask 방식은 쿠키/인증 누락으로 CDN이 403을 반환하여 HTML이 .mp4로 저장되는 문제가 있었습니다 (13 bytes/s). WKWebView.startDownload는 브라우저 세션(쿠키/토큰/Referer)을 그대로 사용하여 삼성 브라우저/알로하와 동일하게 동작합니다.

```
[다운로드 흐름]
JS 감지 → downloadVideo/alohaDownload 메시지
→ WebViewCoordinator.startWKDownload()
→ WKWebView.startDownload(using: URLRequest)
→ WKDownloadDelegate (HTTP 검증 + 파일 저장)
→ PHPhotoLibrary 자동 갤러리 저장
```

HLS(.m3u8)는 커스텀 m3u8 파서(foreground URLSession)로 처리합니다.  
Sideload 앱은 background entitlement가 없으므로 AVAssetDownloadURLSession(background)은 사용 불가합니다.

### 2.2 JS 인젝션 (2단계)

- **earlyJS** (atDocumentStart, forMainFrameOnly: false): XHR/fetch 인터셉터, Performance API (PerformanceObserver), HTMLMediaElement.src setter 인터셉트, Blob URL 캡처
- **mainJS** (atDocumentEnd, forMainFrameOnly: false): 비디오 버튼 UI, scanAll(), 전체화면 이벤트, 광고 제거 MutationObserver, JW Player API 호출

### 2.3 영상 URL 캡처 — bestSrc() 4단계 폴백

1. video.currentSrc (non-blob)
2. `<source>` 요소 순회
3. 네트워크 인터셉트 URL (__gsVideoURLs 배열, HLS > MP4 우선)
4. Performance API 실시간 재스캔 (performance.getEntriesByType('resource'))

CDN 패턴 매칭: videoplayback, googlevideo, fbcdn, cdninstagram, twimg, akamaized

### 2.4 전체화면 오버레이

UIWindow(.statusBar+200)만이 iOS 네이티브 전체화면 위에 표시 가능합니다. JS fixed position은 시스템 AVPlayerViewController가 인수하면 보이지 않습니다.

- FullscreenDownloadOverlay: UIBlurEffect 배경, 4버튼 (⬇️저장 / 📱PiP / 🔁반복 / ✖닫기)
- CSS fullscreenchange에서 __hide_overlay__ 제거됨 (1초 만에 사라지는 버그 원인이었음)
- hideDebounced(delay: 1.5) 적용

---

## 3. 파일 구조 (주요 파일)

| 파일 | 줄수 | 역할 |
|------|------|------|
| App/GhostStreamApp.swift | 39 | @main, 테마 선택, 온보딩 제거됨 |
| App/DI/Container.swift | 45 | 7개 서비스 DI |
| Browser/WebViewManager.swift | 753 | ★핵심: Coordinator + earlyJS + mainJS + startWKDownload |
| Browser/BrowserWebView.swift | 73 | UIViewRepresentable |
| Browser/TabManager.swift | 197 | Tab 모델 + DetectedMedia |
| Media/MediaDownloadManager.swift | 572 | URLSession 다운로드 + HLS 커스텀 파서 |
| Privacy/ContentBlockerManager.swift | 293 | 75개 WKContentRuleList 규칙 |
| Privacy/PrivacyEngine.swift | 159 | 7벡터 핑거프린트 방어 |
| UI/Browser/BrowserContainerView.swift | 383 | Chrome/Brave 하이브리드 UI |
| UI/Components/DownloadSheetView.swift | 612 | 3탭(다운로드/파일/보안폴더) + URL 직접 입력 |
| UI/Components/FullscreenDownloadOverlay.swift | 140 | UIWindow 알로하 스타일 바 |
| UI/Settings/SettingsView.swift | 139 | 5섹션 설정 |
| Vault/VaultManager.swift | 243 | AES-256-GCM + Face ID |

---

## 4. 해결된 핵심 버그들

| 버그 | 근본 원인 | 해결 |
|------|----------|------|
| 다운로드 13bytes/s | URLSession에 쿠키 없음 → CDN 거부 | WKWebView.startDownload로 통일 |
| "Cannot Open" | HTML이 .mp4로 저장 | HTTP 응답 검증 + MIME 검증 |
| 전체화면 바 1초 | CSS fullscreenchange → __hide_overlay__ | __hide_overlay__ 제거, X 버튼만 숨김 |
| 버전 0.5.0 표시 | SettingsView 하드코딩 | Bundle.main.infoDictionary 동적 |
| 영상 1개만 감지 | forMainFrameOnly: true | false + MutationObserver + Performance API |
| 갤러리 저장 안 됨 | completion handler nil | PHPhotoLibrary.performChanges + 자동 저장 |
| 뒤로가기 안 됨 | .disabled() 터치 차단 | opacity로만 비활성 표시 |
| HLS 다운로드 실패 | background session entitlement 없음 | 커스텀 m3u8 파서 (foreground) |

---

## 5. 3가지 다운로드 방법 (모두 WKDownload 경로)

| 방법 | 경로 |
|------|------|
| ① Long Tap (길게 누르기) | context menu → "비디오 다운로드" → startWKDownload |
| ② 재생 중 다운로드 | 전체화면 UIWindow 바 → ⬇️ 버튼 → .wkDownloadRequested |
| ③ URL 직접 입력 | 다운로드 Sheet → ⊕ 버튼 → 클립보드 자동 붙여넣기 → .wkDownloadRequested |

---

## 6. 경쟁 브라우저 분석 → 흡수 검토

### 6.1 주요 경쟁 브라우저 장단점

| 브라우저 | 장점 | 단점 |
|---------|------|------|
| **Brave** | Shields 차단 카운트 배지, YouTube 백그라운드 재생, BAT 리워드, 내장 VPN, 커스텀 앱 아이콘 30+개 | 크립토 관련 기능 과다, 일부 사이트 호환 문제 |
| **Safari** | 최적 성능/배터리, iCloud 동기화, Passkey, Reading List, Shared Tab Groups | 확장 제한, 다운로드 기능 약함, 커스터마이즈 불가 |
| **Chrome** | Google 생태계 연동, 탭 그룹, 동기화 완벽, 번역 | 프라이버시 약함, 광고 차단 없음 |
| **Firefox** | Reader Mode, Pocket 저장, 확장 프로그램 일부 지원, 강력한 추적 방지 | 속도 다소 느림, iOS 확장 제한 |
| **Opera** | 내장 무료 VPN, 뉴스 피드, Flow(PC↔모바일 연동), 크립토 월렛, AI 어시스턴트 | VPN 속도 느림, UI 복잡 |
| **Edge** | Collections, Copilot AI, 읽기 음성(TTS), 수직 탭, PDF 주석 | Microsoft 생태계 의존 |
| **DuckDuckGo** | Fire Button(즉시 삭제), HTTPS Everywhere, 앱 추적 방지, Email Protection | 기능 단순, 동기화 약함 |
| **Aloha** | 미디어 다운로드 최강, 전체화면 바, 내장 VPN, AdBlock | 유료 프리미엄, 광고 과다 |
| **Arc** | AI 요약, 깔끔한 미니멀 UI, 스페이스/워크스페이스, 자동 탭 정리 | 계정 필수, iOS 기능 제한 |

### 6.2 GhostStream 흡수 가능성 평가

| 기능 | 출처 | 흡수 가능성 | 구현 난이도 | 우선순위 |
|------|------|------------|------------|----------|
| **YouTube 백그라운드 재생** | Brave | ✅ 가능 | 중 (Picture-in-Picture API) | ★★★★★ |
| **Reader Mode** | Firefox/Safari | ✅ 가능 | 중 (Readability.js 포팅) | ★★★★☆ |
| **Fire Button (즉시 삭제)** | DuckDuckGo | ✅ 가능 | 하 (WKWebsiteDataStore.removeData) | ★★★★☆ |
| **차단 카운트 배지** | Brave Shields | ✅ 구현됨 | - | 완료 |
| **주소바 스크롤 연동** | Chrome/Safari | ✅ 가능 | 중 (contentOffset 관찰) | ★★★☆☆ |
| **탭 썸네일 미리보기** | Safari/Chrome | ✅ 가능 | 중 (WKWebView.takeSnapshot) | ★★★☆☆ |
| **북마크 + 방문 기록** | 전체 | ✅ 가능 | 중 (SwiftData) | ★★★☆☆ |
| **데스크톱 모드 토글** | Chrome/Safari | ✅ 가능 | 하 (customUserAgent) | ★★★☆☆ |
| **페이지 내 검색** | Firefox/Chrome | ✅ 가능 | 중 (JS window.find) | ★★★☆☆ |
| **스와이프 뒤로가기/앞으로가기** | Safari | ✅ 구현됨 | - | 완료 |
| **내장 VPN** | Opera/Aloha | ⚠️ 제한적 | 상 (NetworkExtension 필요, Sideload 불가) | ★★☆☆☆ |
| **AI 요약** | Edge/Arc | ⚠️ 제한적 | 상 (API 비용) | ★★☆☆☆ |
| **확장 프로그램** | Firefox/Orion | ❌ 불가 | 최상 (WKWebView 제한) | — |
| **크립토 월렛** | Brave/Opera | ❌ 범위 외 | 최상 | — |
| **iCloud 탭 동기화** | Safari | ❌ 불가 | 비공개 API | — |

### 6.3 Phase별 로드맵 권장

**Phase 1 (v1.0 목표 — 즉시)**
- YouTube 백그라운드 재생 (PiP)
- Fire Button (즉시 데이터 삭제)
- 데스크톱 모드 토글

**Phase 2 (v1.1~1.3)**
- Reader Mode (Readability.js)
- 북마크 + 방문 기록 (SwiftData)
- 탭 썸네일 미리보기
- 주소바 스크롤 연동

**Phase 3 (v2.0+)**
- 페이지 내 검색 (Find in Page)
- 다운로드 큐 (동시 3개 제한)
- 내장 미디어 플레이어
- 국제화 (영어, 일본어)

---

## 7. 빌드 & 배포

### GitHub Actions CI/CD

```
push → xcodegen → Simulator Build → Archive → IPA 패키징
태그 push (v*) → Release 자동 생성 + IPA 첨부
```

- macOS 15, Xcode 16
- build.yml: sed로 INFOPLIST_FILE 강제 주입
- 최신 IPA: https://github.com/krstock-master/ghoststream/releases/tag/v0.9.5

### 로컬 빌드 방법

```bash
brew install xcodegen
cd ghoststream && xcodegen generate
open GhostStream.xcodeproj
# Xcode → Product → Archive → Distribute (Ad Hoc)
```

---

## 8. 다음 세션 체크리스트

1. 이 인수인계서 업로드
2. GitHub PAT 토큰 제공: <PRIVATE>
3. 우선순위 피드백 전달
4. 테스트 기기 OS 버전 확인 (iOS 18.x)
5. 원하는 Phase 1/2/3 기능 선택

---

## 9. 버전 히스토리 (핵심만)

| 버전 | 주요 변경 |
|------|----------|
| v0.5.0 | 초기 릴리즈 — JW Player 감지, 기본 다운로드 |
| v0.6.x | 광고 차단 75규칙, HLS 파서, 보안 폴더 |
| v0.7.x | Privacy DNS, 핑거프린팅 방어, UI 개선 |
| v0.8.0 | JS 2단계 분리 (earlyJS + mainJS), Performance API |
| v0.8.1 | Chrome/Brave 스타일 UI 재설계 |
| v0.9.0 | 설계 근본 재검토 — UIWindow 전체화면 복원 |
| v0.9.1 | ★ WKWebView.startDownload 도입 (다운로드 핵심 해결) |
| v0.9.2 | 모든 다운로드 경로 WKDownload 통일, CSS __hide_overlay__ 제거 |
| v0.9.3 | 갤러리 자동 저장, FAB→하단바 배지, 뒤로가기 수정, 설정 확장 |
| v0.9.4 | 보안폴더 피드백 토스트, 테마 선택, 온보딩 제거 |
| v0.9.5 | 앱 아이콘 리디자인, New Tab Page 검색바 |
