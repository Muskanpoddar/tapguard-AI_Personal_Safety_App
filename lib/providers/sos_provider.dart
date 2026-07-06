// lib/providers/sos_provider.dart
//
// Reactive state for the SOS flow.
//
// State machine:
//   idle           → nothing happening
//   triggering     → request in flight (SMS dispatching, Firestore write)
//   active         → SOS is live; flashing UI / vibration
//   cancelling     → cancel request in flight
//
// Backed by `SosService` for Firestore + SMS dispatch. The provider also
// exposes the per-contact dispatch stream as a Riverpod StreamProvider
// so the SOS screen can render a live log of "X / Y contacts notified".

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapguard/data/services/sos_service.dart';

enum SosState { idle, triggering, active, cancelling }

class SosController extends Notifier<SosState> {
  late final SosService _service;

  @override
  SosState build() {
    _service = ref.watch(sosServiceProvider);
    ref.onDispose(() {
      // Best-effort: clear the SOS flag if the controller is disposed
      // while an SOS is active.
      if (state == SosState.active) {
        _service.cancelSos();
      }
    });
    return SosState.idle;
  }

  bool get isActive => state == SosState.active;
  bool get isBusy =>
      state == SosState.triggering || state == SosState.cancelling;

  Future<void> trigger({bool fromRisk = false}) async {
    if (state == SosState.triggering || state == SosState.active) return;
    state = SosState.triggering;
    try {
      await _service.triggerSos(fromRisk: fromRisk);
      state = SosState.active;
    } catch (_) {
      state = SosState.idle;
      rethrow;
    }
  }

  Future<void> cancel() async {
    if (state != SosState.active) return;
    state = SosState.cancelling;
    try {
      await _service.cancelSos();
      state = SosState.idle;
    } catch (_) {
      // Even on failure, surface a clean idle state to the UI.
      state = SosState.idle;
      rethrow;
    }
  }

  /// Force-back to idle (e.g. when the screen disposes).
  void reset() {
    state = SosState.idle;
  }
}

/// Singleton-style service provider.
final sosServiceProvider = Provider<SosService>((ref) {
  final svc = SosService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// State controller — `ref.watch(sosControllerProvider)` returns the
/// current `SosState`. Use `ref.read(sosControllerProvider.notifier)`
/// to call `trigger()` / `cancel()`.
final sosControllerProvider =
    NotifierProvider<SosController, SosState>(SosController.new);

/// Convenience boolean — true when the SOS is currently active.
final sosActiveProvider = Provider<bool>((ref) {
  return ref.watch(sosControllerProvider) == SosState.active;
});

/// Live per-contact dispatch events. Watch this in the UI to render a
/// rolling log ("⏳ Sarah — sending…", "✓ Bob — sent", etc).
final sosDispatchStreamProvider = StreamProvider<DispatchEvent>((ref) {
  return ref.watch(sosServiceProvider).dispatchStream;
});

/// Counter incremented by the UI for each terminal dispatch event
/// (sent / failed / skipped). The "X / Y contacts notified" pill reads
/// this + the total contacts count. Riverpod 3.x dropped `StateProvider`,
/// so we wrap the int in a tiny `Notifier`.
class DispatchCounter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
  void reset() => state = 0;
}

final sosDispatchedCountProvider =
    NotifierProvider<DispatchCounter, int>(DispatchCounter.new);