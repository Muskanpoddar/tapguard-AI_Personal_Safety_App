// lib/data/services/email_otp_service.dart
//
// Email OTP Service – uses Maileroo SMTP (port 587 / STARTTLS).
// dart:io raw sockets work on Android & iOS; only Flutter Web blocks them.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailOtpService {
  // ─── SMTP CONFIGURATION ───────────────────────────────────────────────────
  static const String _smtpHost = 'smtp.maileroo.com';
  static const int _smtpPort = 587;
  static const String _smtpUsername = 'no-reply@lekhapatra.shop';
  static const String _smtpPassword = 'e45789741666e7db47a24bf8';

  static const String _senderEmail = _smtpUsername;
  static const String _senderName = 'TapGuard';

  // ─── In-memory OTP store: email → (otp, expiry) ───────────────────────────
  static final Map<String, _OtpEntry> _store = {};
  static const int _otpExpiryMinutes = 5;

  // ── Generate a cryptographically random 6-digit OTP ──────────────────────
  static String _generateOtp() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  // ── Send OTP via Maileroo SMTP ────────────────────────────────────────────
  // Returns null on success, or an error message string on failure.
  static Future<String?> sendOtp(String email) async {
    final otp = _generateOtp();
    final expiry = DateTime.now().add(
      const Duration(minutes: _otpExpiryMinutes),
    );
    _store[email.toLowerCase()] = _OtpEntry(otp, expiry);

    final htmlBody =
        '''
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#F4F3F8;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
  <div style="max-width:480px;margin:40px auto;padding:32px;background:#F4F3F8;border-radius:16px;">
    <div style="text-align:center;margin-bottom:24px;">
      <div style="font-size:40px;">&#x1F6E1;&#xFE0F;</div>
      <h2 style="color:#1A1A2E;font-size:22px;margin:8px 0 0;">TapGuard Verification</h2>
    </div>
    <div style="background:#fff;border-radius:12px;padding:28px;text-align:center;">
      <p style="color:#555;font-size:14px;margin-bottom:20px;">
        Use the code below to verify your email address.
      </p>
      <div style="display:inline-block;font-size:38px;font-weight:800;letter-spacing:10px;
                  color:#4F46E5;background:#EEF2FF;border-radius:10px;padding:16px 28px;">
        $otp
      </div>
      <p style="color:#999;font-size:12px;margin-top:20px;">
        This code expires in <strong>$_otpExpiryMinutes minutes</strong>.
        Never share it with anyone.
      </p>
    </div>
    <p style="text-align:center;color:#bbb;font-size:11px;margin-top:20px;">
      If you didn&#x27;t request this, you can safely ignore this email.
    </p>
  </div>
</body>
</html>
''';

    final smtpServer = SmtpServer(
      _smtpHost,
      port: _smtpPort,
      username: _smtpUsername,
      password: _smtpPassword,
      // port 587 uses STARTTLS (allowInsecure: false = require STARTTLS)
      ssl: false,
      allowInsecure: false,
    );

    final message = Message()
      ..from = Address(_senderEmail, _senderName)
      ..recipients.add(email)
      ..subject = 'TapGuard – Your Verification Code'
      ..html = htmlBody;

    try {
      await send(message, smtpServer);
      return null; // success
    } on MailerException catch (e) {
      _store.remove(email.toLowerCase());
      final details = e.problems.map((p) => p.msg).join('; ');
      debugPrint('[EmailOtpService] SMTP error: ${e.message} | $details');
      return 'Failed to send email: ${e.message}';
    } catch (e) {
      _store.remove(email.toLowerCase());
      debugPrint('[EmailOtpService] Unexpected error: $e');
      return 'Failed to send email: $e';
    }
  }

  // ── Verify the OTP entered by the user ────────────────────────────────────
  // Returns true if [otp] matches the stored value and hasn't expired.
  static bool verifyOtp(String email, String otp) {
    final entry = _store[email.toLowerCase()];
    if (entry == null) return false;
    if (DateTime.now().isAfter(entry.expiry)) {
      _store.remove(email.toLowerCase());
      return false;
    }
    final valid = entry.otp == otp;
    if (valid) _store.remove(email.toLowerCase()); // one-time use
    return valid;
  }

  // ── Utility: is OTP still pending (not verified / not expired)? ───────────
  static bool hasPendingOtp(String email) {
    final entry = _store[email.toLowerCase()];
    if (entry == null) return false;
    return DateTime.now().isBefore(entry.expiry);
  }
}

// ─── Private helper ────────────────────────────────────────────────────────
class _OtpEntry {
  final String otp;
  final DateTime expiry;
  _OtpEntry(this.otp, this.expiry);
}
