// lib/data/services/qr_service.dart
//
// Mirrors NfcService but uses QR instead of NFC tap.
// Phone A → generates session URL → renders QR code
// Phone B → opens camera → scans QR → joins session
//
// No extra NFC hardware required — works on ALL Android + iPhone devices.

import 'dart:async';

enum QrSessionRole {
  none,       // not started
  generator,  // Phone A — showing QR
  scanner,    // Phone B — scanning QR
}

enum QrStatus {
  idle,
  generating,   // creating Firebase session
  showing,      // QR is visible, waiting for scan
  scanning,     // camera open, waiting for QR
  scanned,      // QR read successfully
  joining,      // joining the session in Firebase
  success,      // both sides ready
  error,
}

class QrService {
  static final QrService _i = QrService._();
  factory QrService() => _i;
  QrService._();

  final _statusCtrl = StreamController<QrStatus>.broadcast();
  final _errorCtrl  = StreamController<String>.broadcast();

  Stream<QrStatus> get statusStream => _statusCtrl.stream;
  Stream<String>   get errorStream  => _errorCtrl.stream;

  QrStatus _status = QrStatus.idle;
  QrSessionRole _role = QrSessionRole.none;

  QrStatus get currentStatus => _status;
  QrSessionRole get currentRole => _role;

  void _emit(QrStatus s) {
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  void _emitError(String msg) {
    if (!_errorCtrl.isClosed) _errorCtrl.add(msg);
  }

  void setRole(QrSessionRole role) {
    _role = role;
  }

  void markGenerating() {
    _role = QrSessionRole.generator;
    _emit(QrStatus.generating);
  }

  void markShowing() {
    _emit(QrStatus.showing);
  }

  void markScanning() {
    _role = QrSessionRole.scanner;
    _emit(QrStatus.scanning);
  }

  void markScanned() {
    _emit(QrStatus.scanned);
  }

  void markJoining() {
    _emit(QrStatus.joining);
  }

  void markSuccess() {
    _emit(QrStatus.success);
  }

  void markError(String message) {
    _emit(QrStatus.error);
    _emitError(message);
  }

  void reset() {
    _role = QrSessionRole.none;
    _emit(QrStatus.idle);
  }

  void dispose() {
    _statusCtrl.close();
    _errorCtrl.close();
  }
}