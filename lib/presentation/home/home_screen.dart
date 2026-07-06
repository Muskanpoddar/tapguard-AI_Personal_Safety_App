// lib/presentation/home/home_screen.dart
//
// REAL-TIME features:
//  1. SYSTEM READY badge — checks Location + NFC permissions live
//  2. NFC availability   — polls NfcManager.instance.checkAvailability()
//  3. Trusted Contacts   — `userContactsProvider` (Riverpod) on
//                          users/{uid}/contacts, same source as Profile.
//  4. Contact status     — updates every time Firestore doc changes

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/contact_extensions.dart';
import '../../core/routes/app_routes.dart';
import '../../data/models/contact_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/session_provider.dart';

// ── System status model ────────────────────────────────────────────────────
class _SystemStatus {
  final bool locationGranted;
  final bool nfcAvailable;
  final bool nfcEnabled;

  bool get isReady => locationGranted && nfcAvailable && nfcEnabled;

  const _SystemStatus({
    this.locationGranted = false,
    this.nfcAvailable = false,
    this.nfcEnabled = false,
  });

  String get label {
    if (isReady) return 'SYSTEM READY';
    if (!nfcAvailable) return 'NFC NOT SUPPORTED';
    if (!nfcEnabled) return 'ENABLE NFC';
    if (!locationGranted) return 'LOCATION NEEDED';
    return 'SETUP REQUIRED';
  }

  Color get color {
    if (isReady) return AppColors.success;
    if (!locationGranted) return AppColors.warning;
    return AppColors.warning;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  // ── System status ─────────────────────────────────────────────────────────
  _SystemStatus _status = const _SystemStatus();
  Timer? _statusTimer;

  // ── Enter animation ───────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // watch app lifecycle

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));

    _checkSystemStatus();

    // Re-check status every 5 seconds (NFC can be toggled anytime)
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkSystemStatus(),
    );
  }

  // Re-check when user returns from Settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSystemStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Check all system permissions + NFC ───────────────────────────────────
  Future<void> _checkSystemStatus() async {
    // 1. Location permission
    bool locationOk = false;
    try {
      final perm = await Permission.locationWhenInUse.status;
      locationOk = perm.isGranted;
      if (!locationOk) {
        // Also check via geolocator
        final gPerm = await Geolocator.checkPermission();
        locationOk =
            gPerm == LocationPermission.always ||
            gPerm == LocationPermission.whileInUse;
      }
    } catch (_) {}

    // 2. NFC availability
    bool nfcAvailable = false;
    bool nfcEnabled = false;
    try {
      final avail = await NfcManager.instance.checkAvailability();
      nfcAvailable = avail != NfcAvailability.unsupported;
      nfcEnabled = avail == NfcAvailability.enabled;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _status = _SystemStatus(
        locationGranted: locationOk,
        nfcAvailable: nfcAvailable,
        nfcEnabled: nfcEnabled,
      );
    });
  }

  // ── Request missing permissions ───────────────────────────────────────────
  Future<void> _requestPermissions() async {
    HapticFeedback.lightImpact();

    if (!_status.locationGranted) {
      await Permission.locationWhenInUse.request();
    }

    if (_status.nfcAvailable && !_status.nfcEnabled) {
      // Can't enable NFC programmatically — send user to Settings
      _showNfcDialog();
      return;
    }

    await _checkSystemStatus();
  }

  void _showNfcDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Enable NFC',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Go to Settings → Connections → NFC and turn it on.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // Watch the shared contacts stream. Same source as Profile screen,
    // so any change there reflects here immediately.
    final uid = ref.watch(currentUidProvider);
    final AsyncValue<List<ContactModel>> contactsAsync = uid.isEmpty
        ? const AsyncValue<List<ContactModel>>.data(<ContactModel>[])
        : ref.watch(userContactsProvider(uid));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
                  SliverToBoxAdapter(child: _sharedSessionBanner()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _nfcCard(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _quickActions(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                      child: _contactsHeader(contactsAsync),
                    ),
                  ),
                  // Contacts list
                  ..._contactsSlivers(contactsAsync),
                  SliverToBoxAdapter(child: _encBadge()),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Contacts slivers (loading / empty / data) ────────────────────────────
  List<Widget> _contactsSlivers(AsyncValue<List<ContactModel>> contactsAsync) {
    return contactsAsync.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ],
      error: (_, _) => [
        SliverToBoxAdapter(child: _emptyContacts()),
      ],
      data: (contacts) {
        if (contacts.isEmpty) {
          return [SliverToBoxAdapter(child: _emptyContacts())];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _contactTile(contacts[i]),
              ),
              childCount: contacts.length,
            ),
          ),
        ];
      },
    );
  }

  // ── "Someone shared a session with you" banner ───────────────────────────
  // Shows when this user is the receiver of an active shared session
  // (someone tapped "Share Live Location" from their contacts). Tap to
  // open the live session — the screen auto-detects the receiver role
  // and starts streaming this phone's GPS back.
  Widget _sharedSessionBanner() {
    final async = ref.watch(sharedSessionsProvider);
    final sessions = async.maybeWhen(
      data: (list) => list,
      orElse: () => const <SharedSession>[],
    );
    if (sessions.isEmpty) return const SizedBox.shrink();
    final s = sessions.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pushNamed(AppRoutes.liveSession);
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.ownerName} shared live location',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to view — you can share your location back',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar with live SYSTEM READY badge ──────────────────────────────────
  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'TapGuard',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),

        // Live system ready badge — tappable to fix issues
        Flexible(
          child: GestureDetector(
            onTap: _status.isReady ? null : _requestPermissions,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _status.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing dot
                  _statusDot(_status.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _status.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _status.color,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (!_status.isReady) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: _status.color,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  // Pulsing dot widget
  Widget _statusDot(Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (_, v, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: v),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  // ── NFC hero card ─────────────────────────────────────────────────────────
  Widget _nfcCard() => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          const Text(
            'Start Pairing',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how you want to connect with a trusted contact.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
 
          const SizedBox(height: 16),
 
          // ── Two side-by-side option cards ────────────────────────────────────
          Row(
            children: [
              // ── NFC Option ────────────────────────────────────────────────
              Expanded(
                child: _PairingOptionCard(
                  icon: Icons.wifi_rounded,
                  label: 'NFC Tap',
                  sublabel: 'Hold phones\ntogether',
                  badgeText: 'INSTANT',
                  badgeColor: AppColors.primary,
                  isEnabled: _status.nfcEnabled,
                  disabledReason: !_status.nfcAvailable
                      ? 'Not supported'
                      : 'NFC is off',
                  onTap: _status.nfcEnabled
                      ? () => Navigator.of(context)
                          .pushNamed(AppRoutes.nfcPairing)
                      : _requestPermissions,
                ),
              ),
 
              const SizedBox(width: 12),
 
              // ── QR Option ─────────────────────────────────────────────────
              Expanded(
                child: _PairingOptionCard(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'QR Code',
                  sublabel: 'Scan to\nconnect',
                  badgeText: 'UNIVERSAL',
                  badgeColor: const Color(0xFF2563EB),
                  isEnabled: true, // QR always works
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.qrPairing),
                ),
              ),
            ],
          ),
 
          const SizedBox(height: 14),
 
          // ── Fallback hint ────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'QR works on all phones including iPhone — no NFC needed.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  // ── Quick actions ─────────────────────────────────────────────────────────
  Widget _quickActions() => Row(
    children: [
      Expanded(
        child: _actionCard(
          icon: Icons.map_rounded,
          bg: const Color(0xFFDBEAFE),
          fg: const Color(0xFF2563EB),
          title: 'Safety Map',
          sub: 'Live view',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.liveMap),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _actionCard(
          icon: Icons.security_rounded,
          bg: const Color(0xFFDCFCE7),
          fg: AppColors.success,
          title: 'Safety Status',
          sub: 'Check in',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.safetyStatus),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _actionCard(
          icon: Icons.timer_rounded,
          bg: const Color(0xFFFEF3C7),
          fg: const Color(0xFFD97706),
          title: 'Safe Timer',
          sub: 'Coming home',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.activeSession),
        ),
      ),
    ],
  );

  Widget _actionCard({
    required IconData icon,
    required Color bg,
    required Color fg,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade400,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );

  // ── Contacts header ───────────────────────────────────────────────────────
  Widget _contactsHeader(AsyncValue<List<ContactModel>> contactsAsync) {
    final count = contactsAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );
    return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          const Text(
            'Trusted Contacts',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      GestureDetector(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.contacts),
        child: Text(
          'See All',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    ],
  );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyContacts() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.people_outline_rounded,
            color: AppColors.primary.withValues(alpha: 0.4),
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'No trusted contacts yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pair with a trusted contact via NFC or QR\nto add them to your safety circle.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.qrPairing),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Add Contact',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Live contact tile ─────────────────────────────────────────────────────
  Widget _contactTile(ContactModel c) => InkWell(
    onTap: () => Navigator.of(context).pushNamed(
      AppRoutes.contactDetail,
      arguments: {'contactUid': c.uid},
    ),
    borderRadius: BorderRadius.circular(14),
    child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            if (c.isActive)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (c.priority > 0 && c.priority <= 3)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor(c.priority)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'P${c.priority}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: priorityColor(c.priority),
                        ),
                      ),
                    ),
                ],
              ),
              if (c.email.isNotEmpty)
                Text(
                  c.email,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (c.isActive)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      c.statusLabel,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: c.isActive
                            ? AppColors.success
                            : Colors.grey.shade400,
                        fontWeight: c.isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Icon(Icons.more_horiz_rounded, color: Colors.grey.shade300, size: 22),
      ],
    ),
    ),
  );

  // ── E2E badge ─────────────────────────────────────────────────────────────
  Widget _encBadge() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(
          'END-TO-END ENCRYPTED SHARING',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade400,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );

}
class _PairingOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final String badgeText;
  final Color badgeColor;
  final bool isEnabled;
  final String? disabledReason;
  final VoidCallback onTap;
 
  const _PairingOptionCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.badgeText,
    required this.badgeColor,
    required this.isEnabled,
    required this.onTap,
    this.disabledReason,
  });
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isEnabled
              ? badgeColor.withValues(alpha: 0.06)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled
                ? badgeColor.withValues(alpha: 0.30)
                : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon + badge row ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? badgeColor.withValues(alpha: 0.12)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isEnabled ? badgeColor : Colors.grey.shade400,
                    size: 22,
                  ),
                ),
                // Flexible + FittedBox lets the badge keep its intrinsic
                // width on wide screens, but scale down (without clipping)
                // when the card is too narrow — fixes "RIGHT OVERFLOWED BY
                // 3.4 PIXELS" on small phones.
                Flexible(
                  fit: FlexFit.loose,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? badgeColor.withValues(alpha: 0.12)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEnabled ? badgeText : 'OFF',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color:
                              isEnabled ? badgeColor : Colors.grey.shade400,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
 
            const SizedBox(height: 10),
 
            // ── Label ────────────────────────────────────────────────────────
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isEnabled
                    ? const Color(0xFF1A1A2E)
                    : Colors.grey.shade400,
              ),
            ),
 
            const SizedBox(height: 2),
 
            // ── Sublabel or disabled reason ───────────────────────────────────
            Text(
              isEnabled ? sublabel : (disabledReason ?? 'Unavailable'),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: isEnabled ? Colors.grey.shade500 : Colors.grey.shade400,
                height: 1.4,
              ),
            ),
 
            const SizedBox(height: 12),
 
            // ── Action button ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              height: 36,
              decoration: BoxDecoration(
                color: isEnabled ? badgeColor : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isEnabled
                          ? Icons.arrow_forward_rounded
                          : Icons.settings_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isEnabled ? 'Start' : 'Fix',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}