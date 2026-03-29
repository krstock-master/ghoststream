// Package.swift
// GhostStream SPM Dependencies
//
// NOTE: These dependencies are added via Xcode:
//   File → Add Package Dependencies...
//
// Required packages for the VPN Network Extension target:

// 1. WireGuardKit (VPN Target only)
//    URL: https://github.com/WireGuard/wireguard-apple
//    Version: from 1.0.15
//    Add to target: GhostStreamVPN
//
// The main app target (GhostStream) uses only Apple frameworks:
//    - WebKit
//    - CryptoKit
//    - LocalAuthentication
//    - NetworkExtension
//    - AVFoundation
//    - SwiftUI / UIKit

// NO third-party SDKs in the main app:
// ❌ Firebase
// ❌ Facebook SDK
// ❌ Amplitude
// ❌ Sentry
// ❌ Any analytics or tracking SDK
//
// This is a core privacy principle of GhostStream.
