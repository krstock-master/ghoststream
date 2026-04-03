# GhostStream

**보고 싶은 건 저장하고, 내가 뭘 봤는지는 아무도 모른다.**

iOS 프라이버시 브라우저 | iOS 17.0+ | Sideload 전용

## 기능

- 광고 및 트래커 차단
- 핑거프린팅 방어
- 미디어 다운로드 (영상, 사진, 파일)
- AES-256 암호화 보안 폴더 (Face ID 잠금)
- Reader Mode
- 탭 관리 + 북마크 + 방문 기록
- DNS over HTTPS
- 피싱 사이트 경고
- 프라이버시 대시보드

## 설치

### IPA 다운로드

[최신 릴리즈](https://github.com/krstock-master/ghoststream/releases)에서 `GhostStream.ipa`를 다운로드합니다.

### iPhone에 설치

- **SideStore**: GhostStream.ipa를 SideStore에서 설치
- **TrollStore**: 파일 앱에서 IPA 열기 → TrollStore로 설치

## 프라이버시 원칙

- 모든 데이터는 기기에만 저장
- 자체 서버에 사용자 데이터 전송 없음
- 제3자 SDK 없음 (Firebase, Facebook, Amplitude 등 완전 배제)
- 카메라, 연락처, 위치 권한 요청 없음

## 빌드

```bash
brew install xcodegen
xcodegen generate
open GhostStream.xcodeproj
```

## 라이선스

MIT License
