@echo off
REM ============================================
REM  GhostStream - Windows IPA Build Setup
REM  GitHub Actions로 클라우드 macOS에서 IPA 빌드
REM ============================================
echo.
echo  =======================================
echo   GhostStream IPA Build Setup (Windows)
echo  =======================================
echo.

REM Git 확인
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Git이 설치되지 않았습니다.
    echo 다운로드: https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)

echo [1/5] Git 확인 완료
echo.

REM GitHub 리포 생성 안내
echo [2/5] GitHub 리포지토리 설정
echo.
echo  아래 단계를 따라주세요:
echo  1. https://github.com/new 에서 새 리포 생성
echo     - Repository name: ghoststream
echo     - Private 선택
echo     - "Add a README" 체크하지 않기
echo  2. 생성 후 리포 URL 복사
echo.
set /p REPO_URL="GitHub 리포 URL을 입력하세요 (예: https://github.com/username/ghoststream): "
echo.

REM Git 초기화
echo [3/5] Git 초기화 및 커밋...
cd /d "%~dp0"
git init
git add -A
git commit -m "feat: GhostStream v0.1.0 - Privacy Media Browser"
echo.

REM Remote 추가 및 Push
echo [4/5] GitHub에 Push...
git branch -M main
git remote add origin %REPO_URL% 2>nul || git remote set-url origin %REPO_URL%
git push -u origin main
echo.

echo [5/5] 빌드 시작!
echo.
echo  ==========================================
echo   GitHub Actions가 자동으로 IPA를 빌드합니다
echo  ==========================================
echo.
echo  1. %REPO_URL%/actions 에서 빌드 상태 확인
echo  2. 빌드 완료 후 (약 5-10분):
echo     - Actions 탭 클릭
echo     - 최신 빌드 클릭
echo     - "Artifacts" 섹션에서 "GhostStream-IPA" 다운로드
echo  3. GhostStream.ipa를 SideStore/TrollStore로 설치
echo.
echo  릴리스 버전 빌드:
echo     git tag v0.1.0
echo     git push origin v0.1.0
echo  이러면 GitHub Releases에 IPA가 자동 업로드됩니다.
echo.
echo  수동 빌드:
echo     GitHub 리포 → Actions 탭 → "Build GhostStream IPA"
echo     → "Run workflow" 버튼 클릭
echo.
pause
