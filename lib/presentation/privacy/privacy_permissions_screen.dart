// lib/presentation/privacy/privacy_permissions_screen.dart
//
// Full Privacy & Permissions Screen
// ────────────────────────────────
// Features:
//   - Granular permission toggles:
//       • Shake Detection on/off
//       • Background Tracking on/off
//       • NFC Visibility on/off
//       • Microphone Access on/off
//   - Auto session timeout picker
//   - Location accuracy level picker
//   - Privacy policy link
//   - Data is saved to SharedPreferences via RiskDetectionService
//
// All toggles are local-only (SharedPreferences) — not sent to Firestore
// to keep privacy truly local.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/risk_detection_service.dart';

class PrivacyPermissionsScreen extends StatefulWidget {
  const PrivacyPermissionsScreen({super.key});

  @override
  State<PrivacyPermissionsScreen> createState() => _PrivacyPermissionsScreenState();
}

class _PrivacyPermissionsScreenState extends State<PrivacyPermissionsScreen> {
  final _risk = RiskDetectionService();

  bool _shakeDetection  = true;
  bool _backgroundTrack = false;
  bool _nfcVisibility   = true;
  bool _micAccess       = false;
  int  _autoTimeoutMins = 120;
  int  _locationAccuracy = 1; // 0=low, 1=high

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _risk.loadPreferences();
    if (!mounted) return;
    setState(() {
      _shakeDetection   = prefs['shakeDetection']   as bool;
      _autoTimeoutMins  = prefs['autoTimeout']      as int;
      _locationAccuracy = prefs['locationAccuracy'] as int;
      _loading = false;
    });
  }

  Future<void> _savePrefs() async {
    await _risk.savePreferences(
      shakeDetectionEnabled: _shakeDetection,
      autoTimeoutMinutes:      _autoTimeoutMins,
      locationAccuracyLevel:  _locationAccuracy,
    );
  }

  Future<void> _requestPerm(Permission permission, String label) async {
    final status = await permission.request();
    if (!mounted) return;
    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label granted', style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else if (status.isPermanentlyDenied) {
      _showPermDeniedDialog(label);
    }
  }

  void _showPermDeniedDialog(String label) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('$label Permission', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Please enable $label permission in Settings.', style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); openAppSettings(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Open Settings', style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3))
          : _buildBody(),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: const Color(0xFFF4F3F8),
    elevation: 0,
    leading: GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFF1A1A2E)),
      ),
    ),
    title: const Text('Privacy & Permissions', style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
    centerTitle: true,
  );

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16),
          _buildSectionTitle('CORE SAFETY FEATURES'),
          const SizedBox(height: 8),
          _buildToggleCard(
            icon: Icons.vibration_rounded,
            title: 'Shake Detection',
            subtitle: 'Automatically triggers SOS when violent shake detected',
            value: _shakeDetection,
            onChanged: (v) { setState(() => _shakeDetection = v); _savePrefs(); },
          ),
          const SizedBox(height: 8),
          _buildToggleCard(
            icon: Icons.location_on_rounded,
            title: 'Location Sharing',
            subtitle: 'Required for NFC pairing and live session tracking',
            value: true,
            onChanged: (v) { if (!v) _requestPerm(Permission.locationWhenInUse, 'Location'); },
          ),
          const SizedBox(height: 8),
          _buildToggleCard(
            icon: Icons.nfc_rounded,
            title: 'NFC Visibility',
            subtitle: 'Required to pair with wearables and smart jewellery',
            value: _nfcVisibility,
            onChanged: (v) { setState(() => _nfcVisibility = v); _savePrefs(); },
          ),
          const SizedBox(height: 8),
          _buildToggleCard(
            icon: Icons.mic_rounded,
            title: 'Microphone Access',
            subtitle: 'Used only for "Voice Trigger" distress keyword detection',
            value: _micAccess,
            onChanged: (v) async {
              if (v) {
                final status = await Permission.microphone.request();
                if (status.isGranted) {
                  setState(() => _micAccess = true);
                } else if (status.isPermanentlyDenied) {
                  _showPermDeniedDialog('Microphone');
                }
              } else {
                setState(() => _micAccess = false);
              }
            },
          ),

          const SizedBox(height: 20),
          _buildSectionTitle('APP PREFERENCES'),
          const SizedBox(height: 8),
          _buildTimeoutCard(),
          const SizedBox(height: 8),
          _buildAccuracyCard(),
          const SizedBox(height: 8),
          _buildToggleCard(
            icon: Icons.sync_rounded,
            title: 'Background Tracking',
            subtitle: 'Keep updating location even when app is in background',
            value: _backgroundTrack,
            onChanged: (v) => setState(() => _backgroundTrack = v),
          ),

          const SizedBox(height: 20),
          _buildDataPolicyNote(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Safety, Your Privacy', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(
                  'TapGuard only accesses data needed to protect you in an emergency. We never sell your personal information.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 1.0),
      ),
    );
  }

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey.shade500, height: 1.4)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeoutCard() {
    final options = [
      ('30 min', 30),
      ('1 hour', 60),
      ('2 hours', 120),
      ('4 hours', 240),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.timer_rounded, color: AppColors.warning, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Auto Session Timeout', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 2),
                    Text('Sessions auto-expire after this duration', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Text(
                _autoTimeoutMins < 60
                    ? '$_autoTimeoutMins min'
                    : '${(_autoTimeoutMins / 60).toStringAsFixed(0)} hour${_autoTimeoutMins >= 120 ? "s" : ""}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final selected = _autoTimeoutMins == o.$2;
              return GestureDetector(
                onTap: () { setState(() => _autoTimeoutMins = o.$2); _savePrefs(); HapticFeedback.lightImpact(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.warning.withOpacity(0.12) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: selected ? AppColors.warning : Colors.transparent),
                  ),
                  child: Text(
                    o.$1,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.warning : Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracyCard() {
    const options = [
      ('Low', 0),
      ('High', 1),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.info.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.gps_fixed_rounded, color: AppColors.info, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Location Accuracy', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 2),
                    Text('Higher accuracy uses more battery', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: options.map((o) {
              final selected = _locationAccuracy == o.$2;
              return GestureDetector(
                onTap: () { setState(() => _locationAccuracy = o.$2); _savePrefs(); HapticFeedback.lightImpact(); },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.info.withOpacity(0.12) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: selected ? AppColors.info : Colors.transparent),
                  ),
                  child: Text(
                    o.$1,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.info : Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDataPolicyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All data is end-to-end encrypted. We never sell your personal information to third parties.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () { /* TODO: open privacy policy URL */ },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'View Privacy Policy',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
