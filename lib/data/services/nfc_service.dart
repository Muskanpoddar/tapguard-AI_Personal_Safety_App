import 'dart:async';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:ndef_record/ndef_record.dart';

enum NfcWriteStatus {
  idle, scanning, writing, success, error, unavailable,
}

class NfcService {
  static final NfcService _i = NfcService._();
  factory NfcService() => _i;
  NfcService._();

  final _statusCtrl = StreamController<NfcWriteStatus>.broadcast();
  final _errorCtrl  = StreamController<String>.broadcast();

  Stream<NfcWriteStatus> get statusStream => _statusCtrl.stream;
  Stream<String>         get errorStream  => _errorCtrl.stream;

  NfcWriteStatus _status = NfcWriteStatus.idle;
  NfcWriteStatus get currentStatus => _status;

  void _emit(NfcWriteStatus s) {
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  void _emitError(String msg) {
    if (!_errorCtrl.isClosed) _errorCtrl.add(msg);
  }

  Future<bool> isAvailable() async {
    try {
      final a = await NfcManager.instance.checkAvailability();
      return a == NfcAvailability.enabled;
    } catch (_) { return false; }
  }

  Future<void> startWriting(String shareUrl) async {
    final available = await isAvailable();
    if (!available) {
      _emit(NfcWriteStatus.unavailable);
      _emitError('NFC is off. Go to Settings → Connections → NFC and enable it.');
      return;
    }
    _emit(NfcWriteStatus.scanning);
    try {
      NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          _emit(NfcWriteStatus.writing);
          try {
            await _writeUrl(tag, shareUrl);
            _emit(NfcWriteStatus.success);
          } catch (e) {
            _emit(NfcWriteStatus.error);
            _emitError('Write failed: ${_clean(e)}');
          } finally {
            await _stop();
          }
        },
      );
    } catch (e) {
      _emit(NfcWriteStatus.error);
      _emitError('Cannot start NFC: ${_clean(e)}');
    }
  }

  Future<void> _writeUrl(NfcTag tag, String url) async {
    final ndef = NdefAndroid.from(tag);
    if (ndef == null) throw Exception('Device does not support NDEF.');
    if (!ndef.isWritable) throw Exception('NFC target is read-only.');

    final message = NdefMessage(records: [_buildUriRecord(url)]);
    await ndef.writeNdefMessage(message);
  }

  NdefRecord _buildUriRecord(String url) {
    int prefix;
    String rest;
    if (url.startsWith('https://')) {
      prefix = 0x04; rest = url.substring('https://'.length);
    } else if (url.startsWith('http://')) {
      prefix = 0x03; rest = url.substring('http://'.length);
    } else {
      prefix = 0x00; rest = url;
    }
    final restBytes = _toUtf8(rest);
    final payload = Uint8List(1 + restBytes.length);
    payload[0] = prefix;
    payload.setRange(1, payload.length, restBytes);

    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type:           Uint8List.fromList([0x55]),
      identifier:     Uint8List(0),
      payload:        payload,
    );
  }

  Uint8List _toUtf8(String s) {
    final out = <int>[];
    for (final r in s.runes) {
      if (r <= 0x7F) { out.add(r); }
      else if (r <= 0x7FF) { out.add(0xC0|(r>>6)); out.add(0x80|(r&0x3F)); }
      else { out.add(0xE0|(r>>12)); out.add(0x80|((r>>6)&0x3F)); out.add(0x80|(r&0x3F)); }
    }
    return Uint8List.fromList(out);
  }

  Future<void> _stop() async {
    try { await NfcManager.instance.stopSession(); } catch (_) {}
  }

  Future<void> stopSession() async {
    await _stop();
    _emit(NfcWriteStatus.idle);
  }

  String _clean(Object e) => e.toString().replaceAll('Exception: ', '').split('\n').first;

  void dispose() { _statusCtrl.close(); _errorCtrl.close(); }
}