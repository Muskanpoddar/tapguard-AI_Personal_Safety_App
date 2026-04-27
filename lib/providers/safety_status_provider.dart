// lib/providers/safety_status_provider.dart
//
// SafetyStatusProvider — Riverpod provider for continuous risk monitoring
// ──────────────────────────────────────────────────────────────────────────
// Wraps RiskDetectionService as a Riverpod-compatible stream provider.
// Allows UI screens to subscribe to risk level changes reactively.
//
// USAGE in a widget:
//   final riskResult = ref.watch(safetyStatusProvider);
//   if (riskResult.riskLevel == RiskLevel.high) { ... }
//
// Auto-starts monitoring on app start, stops on dispose.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/risk_detection_service.dart';

/// Provider that exposes the live RiskResult stream.
/// Components can watch this to react to changing risk levels in real-time.
final safetyStatusProvider = StreamProvider<RiskResult>((ref) {
  final risk = RiskDetectionService();
  risk.startMonitoring();

  ref.onDispose(() {
    risk.stopMonitoring();
    risk.dispose();
  });

  return risk.riskStream;
});

/// Provider for the last computed RiskResult (synchronous read).
/// Use this when you need the current risk level without subscribing to changes.
final lastRiskResultProvider = Provider<RiskResult?>((ref) {
  final risk = RiskDetectionService();
  return risk.lastResult;
});

/// Provider for whether SOS is currently triggered.
final sosTriggeredProvider = Provider<bool>((ref) {
  final risk = RiskDetectionService();
  return risk.sosTriggered;
});

/// Provider that allows triggering SOS manually from any screen.
final sosTriggerProvider = Provider((ref) {
  final risk = RiskDetectionService();
  return risk;
});

/// Provider for "I am safe" confirmation.
/// Calling this resets inactivity timer + cancels SOS + notifies contacts.
final safetyConfirmProvider = Provider((ref) {
  final risk = RiskDetectionService();
  return risk.sendSafetyConfirmation;
});
