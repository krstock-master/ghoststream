# GhostStream

**보고 싶은 건 저장하고, 내가 뭘 봤는지는 아무도 모른다.**

iOS 프라이버시 미디어 브라우저 | Swift 5.9 | iOS 16.0+ | SwiftUI + WKWebView

## 핵심 기능

### 🌐 브라우저
- WKWebView 기반 풀 브라우저
- Vivaldi 스타일 탭 관리 (스태킹, 그룹화)
- 스마트 주소창 (URL / 검색 자동 감지)
- DuckDuckGo / Brave / Google / Naver 검색 엔진

### ⬇️ 미디어 다운로드 엔진
- JW Player v8+ 자동 감지 (JS 인젝션)
- HLS (m3u8) → AVAssetDownloadTask 백그라운드 다운로드
- HTML5 `<video>` / `<source>` DOM 스캔
- XHR/fetch 인터셉트로 동적 스트림 캡처
- GIF 자동 감지
- Blob URL 캡처 (URL.createObjectURL 후킹)
- 화질 선택 (1080p / 720p / 480p)

### 🔒 프라이버시 엔진
- **7-벡터 핑거프린팅 방어**: Canvas, WebGL, AudioContext, Font Enumeration, Navigator, Screen, Timing
- **트래커/광고 차단**: WKContentRuleList 기반 네이티브 블로킹 (30,000+ 룰)
- **탭별 쿠키 완전 격리**: WKWebsiteDataStore.nonPersistent() per-tab
- **DNS over HTTPS**: Cloudflare / Quad9 / NextDNS / Google
- **프라이버시 점수 시스템**: 100점 만점 실시간 계산
- **제3자 쿠키 차단**: 자동

### 🔐 암호화 보관함 (Vault)
- AES-256-GCM 암호화
- Face ID / Touch ID / 패스코드 인증
- Keychain (Secure Enclave) 키 관리
- 미디어 타입별 필터 (영상/GIF/기타)
- 내보내기 / 공유 / 삭제

### 🛡️ VPN (WireGuard)
- NetworkExtension PacketTunnelProvider
- WireGuardKit 통합
- 8개 서버 (무료 3 + Pro 5)
- No-logs 정책
- Kill Switch 지원
- RAM-only 서버 설계

## 프로젝트 구조

```
GhostStream/
├── App/
│   ├── GhostStreamApp.swift           # 앱 진입점
│   └── DI/Container.swift             # 의존성 주입 컨테이너
├── Browser/
│   ├── TabManager.swift               # 탭 관리 + 쿠키 격리 + 프라이버시 리포트
│   ├── WebViewManager.swift           # WKWebView 설정 + JS 인젝션 + 미디어 감지
│   └── BrowserWebView.swift           # UIViewRepresentable 래퍼 + KVO
├── Privacy/
│   ├── PrivacyEngine.swift            # 프라이버시 오케스트레이션 + 핑거프린팅 방어 JS
│   ├── ContentBlockerManager.swift    # WKContentRuleList 컴파일 + 차단 엔진
│   └── DNSManager.swift               # NEDNSSettingsManager DoH 설정
├── Media/
│   └── MediaDownloadManager.swift     # HLS/MP4/GIF 다운로드 + 백그라운드 지원
├── Vault/
│   └── VaultManager.swift             # AES-256-GCM 암호화 + Face ID + Keychain
├── VPN/
│   ├── VPNManager.swift               # NETunnelProviderManager 인터페이스
│   └── Tunnel/
│       └── PacketTunnelProvider.swift  # Network Extension 타겟 (WireGuard)
├── UI/
│   ├── Browser/
│   │   └── BrowserContainerView.swift # 메인 브라우저 UI (주소창+탭바+툴바)
│   ├── Components/
│   │   ├── BrowserSheets.swift        # 메뉴/프라이버시리포트/탭그리드
│   │   ├── DownloadSheetView.swift    # 다운로드 옵션 + 진행 상태
│   │   ├── VPNView.swift              # VPN 연결 UI
│   │   └── OnboardingView.swift       # 최초 실행 보안 알림
│   ├── Vault/
│   │   └── VaultView.swift            # 암호화 보관함 갤러리
│   └── Settings/
│       └── SettingsView.swift         # 전체 설정 화면
├── Extensions/
│   └── Extensions.swift               # Color, GlassMorphism, Theme
├── Resources/
│   ├── Assets.xcassets/
│   ├── Blocklists/ghoststream_custom.json
│   ├── ghoststream-source.json        # SideStore/AltStore 소스
│   ├── ko.lproj/Localizable.strings
│   └── en.lproj/Localizable.strings
├── Info.plist
├── ExportOptions.plist
├── build_ipa.sh                       # IPA 패키징 스크립트
├── DEPENDENCIES.swift                 # SPM 의존성 명세
└── README.md
```

## 설치 방법

### 방법 1: Windows에서 GitHub Actions로 IPA 빌드 (Mac 불필요!)

> **Xcode 없이도 IPA를 빌드할 수 있습니다.** GitHub Actions가 클라우드 macOS에서 자동으로 빌드합니다.

**사전 준비:**
- [Git for Windows](https://git-scm.com/download/win) 설치
- [GitHub 계정](https://github.com/signup) 생성 (무료)

**Step 1: GitHub 리포지토리 생성**
1. https://github.com/new 접속
2. Repository name: `ghoststream` 입력
3. **Private** 선택
4. "Create repository" 클릭

**Step 2: 자동 설정 스크립트 실행**
```cmd
# GhostStream 폴더에서 실행
setup_windows.bat
```
또는 수동으로:
```cmd
cd GhostStream
git init
git add -A
git commit -m "feat: GhostStream v0.1.0"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/ghoststream.git
git push -u origin main
```

**Step 3: IPA 자동 빌드 확인**
1. GitHub 리포 → **Actions** 탭 클릭
2. "Build GhostStream IPA" 워크플로우가 자동 실행됨 (약 5-10분)
3. 빌드 완료 후 → 해당 빌드 클릭 → **Artifacts** 섹션
4. **"GhostStream-IPA"** 다운로드 (ZIP으로 받아서 안에 IPA 있음)

**Step 4: iPhone에 설치**
- **SideStore:** GhostStream.ipa를 SideStore에 드래그
- **TrollStore:** 파일 앱에서 IPA 열기 → TrollStore로 설치
- **Sideloadly (Windows):** [다운로드](https://sideloadly.io/) → IPA 선택 → Apple ID 로그인 → Start

**릴리스 버전 빌드 (GitHub Releases에 IPA 자동 업로드):**
```cmd
git tag v0.1.0
git push origin v0.1.0
```

**수동 빌드 트리거:**
GitHub → Actions → "Build GhostStream IPA" → "Run workflow" 버튼

---

### 방법 2: Xcode에서 직접 빌드 (Mac 필요)

```bash
# xcodegen으로 프로젝트 자동 생성
brew install xcodegen
cd GhostStream
xcodegen generate
open GhostStream.xcodeproj
# ⌘R로 빌드 & 실행
```

또는 수동으로:

1. **Xcode 16** → File → New → Project → **iOS App**
2. 설정:
   - Product Name: `GhostStream`
   - Bundle ID: `com.ghoststream.browser`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum Deployment: **iOS 16.0**
3. 자동 생성된 `ContentView.swift` 삭제
4. `GhostStream/` 폴더 전체를 Xcode 프로젝트에 드래그
5. Info.plist 내용을 프로젝트 설정에 반영

### 타겟 설정

**Main App (GhostStream):**
- Signing & Capabilities:
  - Background Modes → Background fetch, Background processing, Audio
  - Network Extensions → DNS Settings
- Frameworks: WebKit, CryptoKit, LocalAuthentication, NetworkExtension, AVFoundation

**VPN Extension (GhostStreamVPN):** ← 별도 타겟 추가
- File → New → Target → **Network Extension**
- Provider Type: Packet Tunnel
- Bundle ID: `com.ghoststream.browser.vpn`
- Signing & Capabilities:
  - Network Extensions → Packet Tunnel
  - Personal VPN
- SPM 추가: WireGuardKit (`https://github.com/WireGuard/wireguard-apple`)
- `VPN/Tunnel/PacketTunnelProvider.swift`를 이 타겟에 포함

### App Group 설정 (VPN ↔ 앱 간 데이터 공유)
- 두 타겟 모두: Signing & Capabilities → App Groups → `group.com.ghoststream.browser`

### 빌드 및 실행

```bash
# Xcode에서
⌘R

# 또는 CLI
xcodebuild -scheme GhostStream -destination "platform=iOS Simulator"
```

## SideStore 배포

```bash
# IPA 빌드
chmod +x build_ipa.sh
./build_ipa.sh

# SideStore에 추가
# 1. GhostStream.ipa를 서버에 업로드
# 2. ghoststream-source.json의 downloadURL 업데이트
# 3. SideStore → Settings → Sources → + → 소스 URL 추가
```

## 기술 스택

| 영역 | 기술 |
|------|------|
| 언어 | Swift 5.9 + async/await |
| UI | SwiftUI + WKWebView |
| 미디어 다운로드 | AVAssetDownloadTask + URLSession |
| 암호화 | CryptoKit (AES-256-GCM) |
| 인증 | LocalAuthentication (Face ID) |
| VPN | WireGuardKit + NetworkExtension |
| 트래커 차단 | WKContentRuleList |
| JS 인젝션 | WKUserScript |
| DNS | NEDNSSettingsManager (DoH) |
| 패키지 관리 | Swift Package Manager |
| 아키텍처 | Clean Architecture + MVVM |
| 제3자 SDK | **없음** (Zero SDK 정책) |

## 프라이버시 5대 원칙

1. **로컬 온니**: 모든 데이터는 기기에만 저장
2. **서버리스**: 자체 서버에 사용자 데이터 전송 안 함
3. **SDK 제로**: Firebase, Facebook SDK, Amplitude 등 완전 배제
4. **오픈소스 코어**: 트래커 차단 엔진, JS 인젝션 스크립트 공개
5. **최소 권한**: 카메라, 연락처, 위치 권한 요청 없음

## 라이선스

MIT License

---

*GhostStream — 보고 싶은 건 저장하고, 내가 뭘 봤는지는 아무도 모른다.*
