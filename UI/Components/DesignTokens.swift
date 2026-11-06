// UI/Components/DesignTokens.swift
// GhostStream v2.0.5 — 디자인 토큰 (모서리/간격/터치 영역)
// 새 UI 코드는 숫자 대신 이 값을 사용한다. 기존 코드는 손대는 김에 점진적으로 교체.
import SwiftUI

enum DS {
    /// 모서리 반경
    enum Radius {
        /// 리스트 행, 작은 버튼 배경
        static let row: CGFloat = 10
        /// 카드 (탭 카드, 통계 셀, 리포트 테이블)
        static let card: CGFloat = 12
        /// 큰 패널 (대시보드 섹션, 토스트, 스낵바)
        static let panel: CGFloat = 16
    }

    /// 간격 (4pt 그리드)
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// HIG 최소 터치 영역
    static let minTapTarget: CGFloat = 44

    /// 브랜드 색 (AccentColor 에셋과 별개로 코드 전반에서 쓰는 teal)
    static let brand: Color = .teal
}
