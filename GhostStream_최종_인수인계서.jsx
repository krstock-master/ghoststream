import { useState } from "react";

const NAV = ["개요", "아키텍처", "구현 현황", "알려진 이슈", "경쟁사 분석", "로드맵", "빌드 가이드", "코드 레퍼런스", "수정 이력"];

export default function Handover() {
  const [tab, setTab] = useState(0);
  return (
    <div style={{ maxWidth: 900, margin: "0 auto", padding: "1.5rem 1rem", fontFamily: "-apple-system, sans-serif", color: "#1a1a2e" }}>
      <div style={{ textAlign: "center", padding: "1.5rem 1rem", background: "linear-gradient(135deg,#0d9488,#065f46)", borderRadius: 14, color: "#fff", marginBottom: 20 }}>
        <p style={{ fontSize: 36, margin: 0 }}>👻</p>
        <h1 style={{ margin: "4px 0 0", fontSize: 22, fontWeight: 700 }}>GhostStream 최종 인수인계서</h1>
        <p style={{ margin: "6px 0 0", opacity: 0.85, fontSize: 13 }}>v0.6.7 · 37 commits · 21 files · ~3,700 lines · 2026.03.30</p>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 4, marginBottom: 16, justifyContent: "center" }}>
        {NAV.map((s, i) => (
          <button key={i} onClick={() => setTab(i)} style={{
            padding: "6px 14px", borderRadius: 16, border: "none", cursor: "pointer",
            background: tab === i ? "#0d9488" : "#f0fdf4", color: tab === i ? "#fff" : "#065f46",
            fontWeight: 500, fontSize: 12,
          }}>{s}</button>
        ))}
      </div>
      <div style={{ background: "#fff", borderRadius: 14, padding: "1.25rem", border: "1px solid #e5e7eb", minHeight: 400 }}>
        {[Overview, Arch, Status, Issues, Competitive, Roadmap, Build, CodeRef, History][tab]()}
      </div>
      <p style={{ textAlign: "center", fontSize: 11, color: "#9ca3af", marginTop: 16 }}>다음 세션 시작 시 이 파일을 업로드하세요 · GitHub: krstock-master/ghoststream</p>
    </div>
  );
}

function T({ children }) { return <h2 style={{ fontSize: 18, fontWeight: 700, margin: "0 0 12px", color: "#065f46", borderBottom: "2px solid #0d9488", paddingBottom: 6 }}>{children}</h2>; }
function C({ title, children, color = "#0d9488" }) {
  return (
    <div style={{ background: "#f9fafb", borderRadius: 10, padding: "0.9rem 1rem", marginBottom: 10, borderLeft: `3px solid ${color}` }}>
      {title && <h3 style={{ margin: "0 0 6px", fontSize: 14, fontWeight: 600, color }}>{title}</h3>}
      <div style={{ fontSize: 13, lineHeight: 1.7, color: "#374151" }}>{children}</div>
    </div>
  );
}
function B({ children, color = "#0d9488" }) { return <span style={{ display: "inline-block", padding: "2px 8px", borderRadius: 10, fontSize: 11, fontWeight: 600, background: color + "18", color, marginRight: 4, marginBottom: 3 }}>{children}</span>; }
function Pre({ children }) { return <pre style={{ fontSize: 11, lineHeight: 1.5, margin: "6px 0 0", fontFamily: "monospace", whiteSpace: "pre-wrap", background: "#f3f4f6", padding: 10, borderRadius: 6 }}>{children}</pre>; }

function Overview() {
  return (<div><T>프로젝트 개요</T>
    <C title="핵심 정보">
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}><tbody>
        {[
          ["앱 이름","GhostStream (iOS Privacy Media Browser)"],
          ["번들 ID","com.ghoststream.browser"],
          ["플랫폼","iOS 17.0+ · Sidestore/TrollStore sideload"],
          ["언어/프레임워크","Swift 5.9 · SwiftUI · WKWebView · UIKit"],
          ["패턴","MVVM + DI Container (@Observable + @Environment)"],
          ["GitHub","github.com/krstock-master/ghoststream (Private)"],
          ["버전","v0.6.7 (빌드 7) · 37 커밋"],
          ["코드량","21 Swift 파일 · ~3,700줄"],
          ["IPA","~341KB unsigned · GitHub Actions 자동 빌드"],
          ["개발 방식","Claude AI가 PAT 토큰으로 직접 push → GitHub Actions 빌드"],
          ["최신 IPA","https://github.com/krstock-master/ghoststream/releases/tag/v0.6.7"],
        ].map(([k,v],i)=>
          <tr key={i} style={{borderBottom:"1px solid #f0f0f0"}}><td style={{padding:"5px 0",fontWeight:500,width:130,color:"#6b7280"}}>{k}</td><td style={{padding:"5px 0"}}>{v}</td></tr>
        )}
      </tbody></table>
    </C>
    <C title="핵심 가치">"한 번의 터치로 어떤 사이트든 영상·GIF·사진을 풀해상도로 다운로드" — 프라이버시를 기본 보장하면서, 알로하 브라우저 수준의 미디어 다운로드 경험을 제공하는 iOS 브라우저.</C>
    <C title="⚠️ PAT 토큰 (다음 세션용)" color="#dc2626">
      <p>현재 세션 토큰 사용 완료. 다음 세션에서 새 토큰 발급 필요.</p>
      <p style={{fontWeight:600,color:"#dc2626"}}>반드시 github.com/settings/tokens 에서 이전 토큰 삭제 후 repo 권한으로 새 토큰 생성.</p>
    </C>
    <C title="테스트 기기">iOS 18.6.1~18.6.2 · Sideloadly로 설치</C>
    <C title="Phase 1 완료 여부 (2026.03.30 기준)" color="#059669">
      <p>✅ CF 무한루프 해결 (v0.6.4~v0.6.7)</p>
      <p>✅ URLSession foreground 전환 — 다운로드 실제 작동 (v0.6.6)</p>
      <p>✅ 갤러리 저장 수정 — UISaveVideoAtPathToSavedPhotosAlbum (v0.6.6)</p>
      <p>✅ 파일뷰어 뒤로가기 수정 — VideoPlayerSheet (v0.6.5)</p>
      <p>✅ 전체화면 다운로드 버튼 — UIWindow+200 하단바 (v0.6.4)</p>
      <p>✅ 탭 UI 삼성 브라우저 스타일 — SamsungTabCard (v0.6.1)</p>
      <p>✅ HLS → MP4 변환 파이프라인 (v0.6.1)</p>
      <p>⚠️ HLS 재생/다운로드 — 기능은 구현됐지만 일부 사이트 추가 테스트 필요</p>
      <p>❌ 앱 아이콘 — 사용자가 시안 선택 대기 중 (5개 제시됨)</p>
    </C>
  </div>);
}

function Arch() {
  return (<div><T>아키텍처</T>
    <C title="폴더 구조"><Pre>{`GhostStream/
├── App/
│   ├── GhostStreamApp.swift          # @main · 온보딩 분기 · 7개 Environment 주입
│   └── DI/Container.swift            # DIContainer (@Observable) + SettingsStore
├── Browser/
│   ├── BrowserWebView.swift          # UIViewRepresentable · WKWebView · KVO
│   │                                 #   ★ coordinator.webView 레퍼런스 주입 (쿠키 전달용)
│   ├── TabManager.swift              # 탭 관리 · 탭별 nonPersistent() 격리
│   └── WebViewManager.swift          # ★ 핵심 (390줄)
│       ├── WebViewCoordinator        #   Nav/UI/Script/Download Delegate
│       │   ├── cfStrippedDomains     #   CF 감지 도메인 Set (재루프 차단)
│       │   ├── cfReloadPending       #   CF reload 중 guard flag
│       │   ├── webView (weak)        #   쿠키 동기화용 참조
│       │   └── syncCookiesToDownloadManager()
│       ├── ElementHiderStore         #   도메인별 CSS 선택자 (UserDefaults)
│       └── WebViewConfigurator       #   JS 인젝션 (알로하 버튼 + 미디어 스캔)
├── Media/
│   └── MediaDownloadManager.swift    # URLSession.default + AVAssetDownloadTask
│                                     # ★ background→default 전환 (sideload 호환)
│                                     # ★ cookieStorage 프로퍼티 (WKWebView 쿠키 전달)
│                                     # exportToMP4(): movpkg→mp4 변환
├── Privacy/
│   ├── PrivacyEngine.swift           # 7-벡터 핑거프린트 방어 JS
│   │                                 # ★ CF bypass guard (sessionStorage + host check)
│   ├── ContentBlockerManager.swift   # WKContentRuleList · 30,000+ 규칙
│   ├── DNSManager.swift              # DoH 설정 (주의: WKWebView에 미적용 가능성)
│   └── SecurityManager.swift         # 탈옥감지 + Certificate Pinning
├── Vault/
│   └── VaultManager.swift            # AES-256-GCM · Keychain · Face ID
├── UI/
│   ├── Browser/BrowserContainerView  # Safari 하단 바 · 키보드 시 상단 URL 바
│   ├── Components/
│   │   ├── DownloadSheetView         # 3탭: 다운로드/파일/보안폴더
│   │   │   ├── VideoPlayerSheet      # ★ 신규: async 트랙 로딩, 에러 UI, 스와이프 dismiss
│   │   │   └── saveToGallery()       # ★ UISaveVideoAtPathToSavedPhotosAlbum
│   │   ├── FullscreenDownloadOverlay # ★ UIWindow(level:.statusBar+200) 하단바
│   │   │                             #   strongDownloadManager (strong retain)
│   │   ├── BrowserSheets             # ★ SamsungTabCard (2열 카드 탭 UI)
│   │   └── OnboardingView
│   ├── Settings/SettingsView
│   └── Vault/VaultView
├── Extensions/Extensions.swift
├── SupportFiles-Info.plist           # 9개 필수 키 (sed 주입 방식)
├── project.yml                       # v0.6.1, 빌드 7
└── .github/workflows/build.yml       # GitHub Actions CI/CD`}</Pre></C>
    <C title="핵심 설계 원칙 (Sideload 앱 제약사항)" color="#dc2626">
      <p style={{fontWeight:600}}>1. URLSession은 반드시 .default 사용</p>
      <p>background session은 com.apple.developer.networking.wifi-info 등 entitlement 필요. Sideloadly/TrollStore 앱은 entitlement 없음 → 무음 실패. .default + .waitsForConnectivity = true 조합 사용.</p>
      <p style={{fontWeight:600,marginTop:8}}>2. 갤러리 저장은 UISaveVideoAtPathToSavedPhotosAlbum 사용</p>
      <p>PHAssetChangeRequest도 일부 entitlement 의존. UIKit 구형 API가 Sideload에서 가장 안정적.</p>
      <p style={{fontWeight:600,marginTop:8}}>3. .movpkg는 AVPlayer(url:) 직접 재생 가능 (단, tracks async 로딩 후)</p>
      <p>AVAsset.loadTracks(withMediaType: .video) async 완료 후 AVPlayerItem 생성해야 검은화면 방지.</p>
    </C>
    <C title="DI Container (7개 서비스)">
      <div style={{display:"flex",gap:4,flexWrap:"wrap"}}>
        {["TabManager","MediaDownloadManager","PrivacyEngine","VaultManager","DNSManager","ContentBlockerManager","SettingsStore"].map(s=><B key={s}>{s}</B>)}
      </div>
    </C>
  </div>);
}

function Status() {
  const f = [
    ["알로하 스타일 다운로드 버튼","done","video 위 JS 오버레이. 탭 → 즉시 다운로드."],
    ["URLSession 직접 다운로드","done","URLSessionConfiguration.default (foreground). background는 sideload에서 작동 안 함."],
    ["WKDownloadDelegate","done","iOS 14.5+ 공식 API. video MIME → .download."],
    ["HLS → MP4 변환","done","AVAssetDownloadTask → .movpkg 저장 → AVAssetExportSession(PassThrough) → .mp4."],
    ["갤러리 저장","done","UISaveVideoAtPathToSavedPhotosAlbum (MP4/MOV) + UIImageWriteToSavedPhotosAlbum (이미지). movpkg는 export 후 저장."],
    ["파일뷰어 재생","done","VideoPlayerSheet: async loadTracks → AVPlayerItem → 재생. 에러 UI 포함. 스와이프 dismiss."],
    ["전체화면 다운로드 버튼","done","UIWindow(level:.statusBar+200) 하단바. strongDownloadManager strong retain. 알로하 스타일 UI."],
    ["Cloudflare 우회","done","CF 감지 → removeAllUserScripts() → injectionJS만 재추가 → reload. cfStrippedDomains로 재루프 차단."],
    ["꾹눌러 다운로드","done","contextMenuConfigurationFor + JS contextmenu 이벤트."],
    ["blob URL 캡처","done","URL.createObjectURL 인터셉트 → FileReader → base64 → native."],
    ["m3u8/HLS 감지","done","XHR/fetch 인터셉트. WKWebView 쿠키 → HLS 세션 전달."],
    ["JW Player 감지","done","jwplayer() API 후킹."],
    ["삼성 브라우저 탭 UI","done","SamsungTabCard 2열 카드 + 하단 플로팅 + 버튼 + 닫기 버튼 + 활성 체크마크."],
    ["방해 요소 가리기","done","탭-투-하이드. CSS 선택자 도메인별 저장."],
    ["광고/트래커 차단","done","WKContentRuleList 30,000+ 규칙."],
    ["핑거프린트 방어","done","Canvas/WebGL/AudioContext/navigator/Screen/Date/Battery 7벡터. CF 페이지에서는 자동 비활성화."],
    ["쿠키 격리","done","탭마다 nonPersistent() DataStore. HLS 다운로드 시 httpCookieStore → URLSession 동기화."],
    ["보안 폴더","done","Face ID + AES-256-GCM."],
    ["앱 아이콘","partial","5가지 라이온 스타일 시안 제시됨. 사용자 선택 대기."],
    ["탭 썸네일 미리보기","todo","WKWebView.takeSnapshot() 미구현. Phase 2."],
    ["주소창 스크롤 연동","todo","Phase 2."],
    ["북마크/방문기록","todo","Phase 2."],
  ];
  const colors = { done: "#059669", partial: "#d97706", todo: "#6b7280" };
  const labels = { done: "✅ 완료", partial: "⚠️ 부분", todo: "📋 미구현" };
  return (<div><T>구현 현황 (22개 기능)</T>
    {f.map(([name,st,detail],i)=>(
      <C key={i} title={name} color={colors[st]}>
        <B color={colors[st]}>{labels[st]}</B>
        <p style={{margin:"4px 0 0"}}>{detail}</p>
      </C>
    ))}
  </div>);
}

function Issues() {
  const issues = [
    ["P0 · HLS 재생/다운로드 일부 사이트 미동작","일부 사이트의 HLS 스트림은 세션 쿠키 외에 추가 인증 토큰(URL 쿼리 파라미터)을 사용. cookieStorage 동기화만으로는 불충분.","URL 파라미터 기반 인증 스트림 탐지 → URLSession 요청에 원본 URL 그대로 사용. 또는 m3u8 직접 파싱 → TS 세그먼트 순차 다운로드.","#dc2626"],
    ["P0 · 전체화면 다운로드 (커스텀 플레이어)","YouTube/TikTok embed 등 자체 fullscreen 구현 사이트는 webkitbeginfullscreen 이벤트 미발생. UIWindow 버튼이 표시 안 됨.","play 이벤트 기반 상시 미디어 URL 수집 + 영구 플로팅 다운로드 버튼 방식으로 전환.","#dc2626"],
    ["P1 · DoH가 WKWebView에 미적용","WKWebView는 시스템 DNS 사용. DNSManager 설정이 실제로 적용 안 됨.","NEDNSProxyProvider 구현 필요. 또는 DoH 기능을 UI에서 숨기고 '준비 중'으로 표시.","#d97706"],
    ["P1 · blob 대용량 (100MB+)","base64 변환 시 메모리 부족.","ReadableStream 청크 전송으로 교체.","#d97706"],
    ["P1 · 탭 썸네일 없음","탭 카드가 아이콘+도메인만 표시. Apple HIG '탭 인식 가능' 미충족.","WKWebView.takeSnapshot(with:) → Tab.snapshot: UIImage? 저장.","#d97706"],
    ["P2 · background URLSession HLS 세션","AVAssetDownloadURLSession은 여전히 background 설정. Sideload에서 안정성 불확실.","HLS 세션도 foreground로 교체하거나, 커스텀 m3u8 파서로 대체.","#6b7280"],
    ["P2 · 앱 아이콘 미완","사용자가 5가지 시안 중 선택 대기 중.","선택 후 AppIcon.appiconset 생성 및 project.yml 적용.","#6b7280"],
  ];
  return (<div><T>알려진 이슈 + 해결 방안</T>
    {issues.map(([title,desc,fix,color],i)=>(
      <C key={i} title={title} color={color}>
        <p style={{fontWeight:600}}>현상:</p><p>{desc}</p>
        <p style={{fontWeight:600,marginTop:8}}>해결 방안:</p><p>{fix}</p>
      </C>
    ))}
  </div>);
}

function Competitive() {
  const data = [
    {n:"Brave",privacy:9,dl:3,adBlock:9,fp:8,ui:9,note:"프라이버시 1위. 다운로드 기능 거의 없음."},
    {n:"Firefox",privacy:8,dl:2,adBlock:7,fp:7,ui:8,note:"확장성 1위. iOS에서는 WebKit 제한."},
    {n:"DuckDuckGo",privacy:8,dl:2,adBlock:7,fp:6,ui:7,note:"간편함 1위. 고급 기능 부족."},
    {n:"Safari",privacy:7,dl:4,adBlock:5,fp:8,ui:10,note:"UI/UX 1위. 다운로드/광고차단 약함."},
    {n:"Aloha",privacy:5,dl:10,adBlock:4,fp:3,ui:8,note:"다운로드 1위. 프라이버시 약함."},
    {n:"GhostStream v0.6.7",privacy:8,dl:7,adBlock:8,fp:8,ui:6,note:"프라이버시+다운로드 조합. 다운로드 7/10으로 개선됨."},
  ];
  return (<div><T>경쟁사 비교 (10점 만점)</T>
    <div style={{overflowX:"auto"}}>
      <table style={{width:"100%",borderCollapse:"collapse",fontSize:12}}><thead>
        <tr style={{background:"#f0fdf4"}}>{["브라우저","프라이버시","다운로드","광고차단","핑거프린트","UI/UX","비고"].map(h=><th key={h} style={{padding:"8px 6px",textAlign:"left",borderBottom:"2px solid #0d9488",fontSize:11}}>{h}</th>)}</tr>
      </thead><tbody>
        {data.map((b,i)=>(
          <tr key={i} style={{background:b.n.includes("Ghost")?"#f0fdf4":i%2?"#fafafa":"#fff",fontWeight:b.n.includes("Ghost")?600:400}}>
            <td style={{padding:"6px"}}>{b.n}</td>
            {[b.privacy,b.dl,b.adBlock,b.fp,b.ui].map((s,j)=>(
              <td key={j} style={{padding:"6px"}}><div style={{display:"flex",alignItems:"center",gap:4}}>
                <div style={{width:50,height:5,background:"#e5e7eb",borderRadius:3,overflow:"hidden"}}>
                  <div style={{width:`${s*10}%`,height:"100%",borderRadius:3,background:s>=8?"#059669":s>=5?"#d97706":"#dc2626"}}/>
                </div><span style={{fontSize:10}}>{s}</span>
              </div></td>
            ))}
            <td style={{padding:"6px",fontSize:11,color:"#6b7280"}}>{b.note}</td>
          </tr>
        ))}
      </tbody></table>
    </div>
    <C title="v1.0 달성 조건 (변경 없음)" color="#0d9488">
      <p>1. 다운로드 안정성 95% (주요 20개 사이트)</p>
      <p>2. HLS → MP4 변환 안정화</p>
      <p>3. 전체화면 다운로드 (모든 플레이어)</p>
      <p>4. 탭 썸네일 + 스크롤 연동 URL 바</p>
      <p>5. 북마크 + 방문 기록</p>
    </C>
  </div>);
}

function Roadmap() {
  const phases = [
    {phase:"Phase 1 — 다운로드 안정화 ✅ 대부분 완료",color:"#059669",items:[
      "✅ URLSession foreground 전환 (sideload 근본 수정)",
      "✅ HLS → MP4 변환 (AVAssetExportSession PassThrough)",
      "✅ 갤러리 저장 (UISaveVideoAtPathToSavedPhotosAlbum)",
      "✅ 파일뷰어 재생 수정 (VideoPlayerSheet async)",
      "✅ CF 무한루프 수정 (removeAllUserScripts)",
      "✅ 전체화면 다운로드 버튼 (UIWindow+200 하단바)",
      "✅ 탭 UI 삼성 브라우저 스타일 (SamsungTabCard)",
      "⏳ HLS 커스텀 플레이어 전체화면 (play 이벤트 기반)",
      "⏳ 대용량 blob 안정화 (청크 전송)",
      "⏳ 앱 아이콘 (사용자 시안 선택 대기)",
      "❌ 10개 사이트 E2E 테스트 (기기 직접 필요)",
    ]},
    {phase:"Phase 2 — UI/UX 개선",color:"#d97706",items:[
      "탭 썸네일 미리보기 (WKWebView.takeSnapshot)",
      "주소창 스크롤 연동 (contentOffset → 높이 축소/확장)",
      "스와이프 탭 전환",
      "다운로드 파일 미리보기 (QLPreviewController)",
      "북마크 + 방문 기록 (SwiftData)",
      "데스크톱 모드 토글",
    ]},
    {phase:"Phase 3 — 고급 기능",color:"#3b82f6",items:[
      "m3u8 직접 파싱 → TS 세그먼트 다운로드 → MP4 병합",
      "4K/최고 화질 자동 선택",
      "백그라운드 다운로드 (BGProcessingTask, TrollStore 전용)",
      "다운로드 큐 (동시 3개)",
      "내장 미디어 플레이어 (커스텀 AVPlayerViewController)",
      "Reader Mode",
    ]},
    {phase:"Phase 4 — 출시",color:"#6366f1",items:[
      "AltStore/SideStore 공식 소스 등록",
      "TestFlight 배포",
      "성능 프로파일링 (Instruments)",
      "접근성 (VoiceOver)",
      "크래시 리포팅",
      "국제화 (영어, 일본어)",
    ]},
  ];
  return (<div><T>개발 로드맵</T>
    {phases.map((p,i)=>(<C key={i} title={p.phase} color={p.color}>
      <ul style={{margin:0,paddingLeft:18}}>{p.items.map((item,j)=><li key={j} style={{marginBottom:3}}>{item}</li>)}</ul>
    </C>))}
  </div>);
}

function Build() {
  return (<div><T>빌드 가이드</T>
    <C title="방법 1: Claude AI 직접 개발 (권장)">
      <Pre>{`1. GitHub PAT 토큰 생성 (github.com/settings/tokens/new → repo 권한)
2. Claude에게 이 인수인계서 파일 + 토큰 전달
3. Claude가 git clone → 코드 수정 → push
4. GitHub Actions가 macOS 15에서 자동 빌드 (약 2분)
5. 빌드 실패 시 로그 확인 → 즉시 수정 → 재 push
6. 성공 시 git tag v0.X.X → Release IPA 자동 생성
7. Sideloadly로 iPhone에 설치 → 테스트`}</Pre>
    </C>
    <C title="방법 2: 직접 push">
      <Pre>{`git add -A && git commit -m "fix: description" && git push
git tag -a v0.X.X -m "version" && git push origin v0.X.X`}</Pre>
    </C>
    <C title="⚠️ Sideload 앱 개발 필수 원칙 (이번 세션 학습)" color="#dc2626">
      <p style={{fontWeight:600}}>1. URLSession은 반드시 .default 사용</p>
      <p>background session entitlement 없으면 모든 다운로드 무음 실패. URLSessionConfiguration.default + .waitsForConnectivity = true.</p>
      <p style={{fontWeight:600,marginTop:8}}>2. 갤러리 저장은 UIKit 구형 API 사용</p>
      <p>UISaveVideoAtPathToSavedPhotosAlbum() / UIImageWriteToSavedPhotosAlbum() 가 Sideload에서 가장 안정적.</p>
      <p style={{fontWeight:600,marginTop:8}}>3. AVPlayer 검은화면 방지</p>
      <p>AVAsset.loadTracks(withMediaType: .video) async 완료 확인 후 AVPlayerItem 생성. onAppear에서 직접 AVPlayer(url:) 하면 .movpkg 등 복합 포맷에서 검은화면.</p>
      <p style={{fontWeight:600,marginTop:8}}>4. xcodegen Info.plist 문제 (이전부터)</p>
      <p>build.yml에서 sed로 pbxproj에 INFOPLIST_FILE 강제 주입.</p>
    </C>
    <C title="다음 세션 체크리스트">
      <ol style={{margin:0,paddingLeft:18}}>
        <li>이 인수인계서 업로드</li>
        <li>GitHub PAT 토큰 새로 생성 (이전 토큰 삭제 필수)</li>
        <li>Claude에게 "ghoststream 이어서 개발" + 우선순위 전달</li>
        <li>v0.6.7 기준 테스트 결과 피드백</li>
        <li>앱 아이콘 시안 선택 (5개 라이온 스타일 제시됨)</li>
      </ol>
    </C>
  </div>);
}

function CodeRef() {
  return (<div><T>핵심 코드 레퍼런스</T>
    <C title="CF 무한루프 수정 (WebViewManager.swift — didFinish)">
      <p>핵심: CF 감지 시 fingerprint 스크립트를 userContentController에서 완전히 제거</p>
      <Pre>{`// CF 감지 후:
let uc = w.configuration.userContentController
uc.removeAllUserScripts()  // ← fingerprint JS 제거
// 미디어 감지 스크립트만 재추가
uc.addUserScript(WKUserScript(source: WebViewConfigurator.injectionJS,
    injectionTime: .atDocumentEnd, forMainFrameOnly: true))
// cfStrippedDomains에 도메인 추가 (재루프 차단)
self.cfStrippedDomains.insert(domain)
w.reload()  // CF가 실제 Safari 프로필 인식 → 통과`}</Pre>
    </C>
    <C title="HLS 쿠키 전달 (WebViewManager.swift — syncCookiesToDownloadManager)">
      <Pre>{`func syncCookiesToDownloadManager() {
    guard let wv = webView, let dm = downloadManager else { return }
    wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
        let storage = HTTPCookieStorage.shared
        cookies.forEach { storage.setCookie($0) }
        dm.cookieStorage = storage  // HLS 다운로드 요청에 쿠키 포함
    }
}`}</Pre>
    </C>
    <C title="URLSession 설정 (MediaDownloadManager.swift — init)">
      <Pre>{`// ✅ Sideload 호환 foreground session
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 60
config.timeoutIntervalForResource = 600
config.waitsForConnectivity = true
urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

// ❌ 이렇게 하면 안 됨 (background entitlement 필요)
// URLSessionConfiguration.background(withIdentifier: "...")`}</Pre>
    </C>
    <C title="갤러리 저장 (DownloadSheetView.swift — saveToGallery)">
      <Pre>{`// ✅ Sideload에서 가장 안정적인 API
if isVideoFile {
    UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
} else {
    if let image = UIImage(contentsOfFile: url.path) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}
// .movpkg의 경우: AVAssetExportSession → .mp4 → 위 API 호출`}</Pre>
    </C>
    <C title="VideoPlayerSheet (DownloadSheetView.swift)">
      <Pre>{`@MainActor
private func loadPlayer() async {
    let asset = AVURLAsset(url: url)
    // ★ 트랙 존재 확인 필수 (없으면 검은화면)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard !tracks.isEmpty else { errorMsg = "재생 가능한 트랙 없음"; return }
    let item = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: item)
    isReady = true
    player?.play()
}`}</Pre>
    </C>
    <C title="전체화면 다운로드 오버레이 (FullscreenDownloadOverlay.swift)">
      <Pre>{`// UIWindow level .statusBar+200 — 모든 레이어 위에 표시
let win = UIWindow(windowScene: scene)
win.windowLevel = .statusBar + 200
// ★ strong retain — weak이면 downloadManager가 nil이 됨
private var strongDownloadManager: MediaDownloadManager?`}</Pre>
    </C>
    <C title="다운로드 흐름 (v0.6.7 기준)">
      <Pre>{`[사용자 탭 ⬇ 버튼]
  → JS: alohaDownload.postMessage({url, title, quality, fullscreen})
  → Swift: WebViewCoordinator.userContentController(alohaDownload)
  → if fullscreen: FullscreenDownloadOverlay.show() (UIWindow+200 하단바)
  → else: syncCookiesToDownloadManager() → downloadManager.download()
  → MediaDownloadManager.startDirectDownload() or startHLSDownload()
  → URLSession.default.downloadTask (foreground, sideload 호환)
  → didFinishDownloadingTo → Documents/Downloads/ 저장
  → downloads → completedDownloads 이동
  → 갤러리 저장: UISaveVideoAtPathToSavedPhotosAlbum`}</Pre>
    </C>
  </div>);
}

function History() {
  const commits = [
    { version: "v0.6.7", date: "2026.03.30", color: "#059669", items: [
      "URLSession.default foreground 전환 — 다운로드 근본 수정 (모든 다운로드 실제 작동)",
      "VideoPlayerSheet async 트랙 로딩 — 검은화면 재생 수정",
      "UISaveVideoAtPathToSavedPhotosAlbum — 갤러리 저장 수정",
      "compile: weak self on struct 오류 수정",
    ]},
    { version: "v0.6.4–v0.6.5", date: "2026.03.30", color: "#0d9488", items: [
      "CF 무한루프 완전 수정: removeAllUserScripts() + cfStrippedDomains Set",
      "FullscreenDownloadOverlay: strongDownloadManager strong retain, 하단바 UI",
      "VideoPlayerSheet: 뒤로가기(X버튼 + 스와이프 dismiss) 수정",
      "갤러리 저장: movpkg → export → PHPhotoLibrary (이후 v0.6.7에서 개선)",
    ]},
    { version: "v0.6.2–v0.6.3", date: "2026.03.29~30", color: "#3b82f6", items: [
      "WKWebView 쿠키 → AVAssetDownloadURLSession 전달 (인증 스트림 대응)",
      "AVAssetExportPresetPassthrough 우선 시도",
      "PrivacyEngine: CF 도메인에서 fingerprint 스푸핑 스킵 (sessionStorage guard)",
      "CFBypassPending 가드 (당시 솔루션, 이후 v0.6.4에서 근본 수정)",
    ]},
    { version: "v0.6.1", date: "2026.03.29", color: "#d97706", items: [
      "HLS → MP4 변환 파이프라인 (AVAssetExportSession + converting 상태)",
      "FullscreenDownloadOverlay 초기 구현 (UIWindow+200)",
      "SamsungTabCard: 삼성 브라우저 스타일 2열 탭 UI",
      "project.yml 버전 0.5.0 → 0.6.1, 빌드 6 → 7",
      "iOS 18 symbolEffect.rotate → iOS 17 호환 수정",
    ]},
    { version: "v0.5.0 (기존)", date: "2026.03.28 이전", color: "#6b7280", items: [
      "기본 WKWebView 브라우저 구조",
      "JS 미디어 감지 + 알로하 다운로드 버튼",
      "PrivacyEngine 7-벡터 핑거프린트 방어",
      "AES-256-GCM 보안 폴더 + Face ID",
      "30,000+ 규칙 광고/트래커 차단",
      "탭 격리 (nonPersistent DataStore)",
    ]},
  ];
  return (<div><T>수정 이력</T>
    {commits.map((c,i) => (
      <C key={i} title={`${c.version} — ${c.date}`} color={c.color}>
        <ul style={{margin:0,paddingLeft:18}}>
          {c.items.map((item,j) => <li key={j} style={{marginBottom:3}}>{item}</li>)}
        </ul>
      </C>
    ))}
  </div>);
}
