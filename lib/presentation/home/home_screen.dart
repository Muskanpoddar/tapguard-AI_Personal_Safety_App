// lib/presentation/home/home_screen.dart
//
// REAL-TIME features:
//  1. SYSTEM READY badge — checks Location + NFC permissions live
//  2. NFC availability   — polls NfcManager.instance.checkAvailability()
//  3. Trusted Contacts   — Firestore stream on users/{uid}/contacts
//                          each contact has lastSeen timestamp + isActive flag
//  4. Contact status     — updates every time Firestore doc changes

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';

// ── Contact model (local, from Firestore) ─────────────────────────────────
class _Contact {
  final String uid;
  final String name;
  final bool   isActive;
  final DateTime? lastSeen;

  _Contact({
    required this.uid,
    required this.name,
    required this.isActive,
    this.lastSeen,
  });

  factory _Contact.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['lastSeen'] as Timestamp?;
    return _Contact(
      uid:      doc.id,
      name:     d['name']     ?? 'Unknown',
      isActive: d['isActive'] ?? false,
      lastSeen: ts?.toDate(),
    );
  }

  // Human-readable last seen string
  String get statusLabel {
    if (isActive) return 'Active Now';
    if (lastSeen == null) return 'Never seen';
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return 'Last seen: ${diff.inMinutes} min ago';
    if (diff.inHours   < 24)  return 'Last seen: ${diff.inHours}h ago';
    return 'Last seen: ${diff.inDays}d ago';
  }
}

// ── System status model ────────────────────────────────────────────────────
class _SystemStatus {
  final bool locationGranted;
  final bool nfcAvailable;
  final bool nfcEnabled;

  bool get isReady => locationGranted && nfcAvailable && nfcEnabled;

  const _SystemStatus({
    this.locationGranted = false,
    this.nfcAvailable    = false,
    this.nfcEnabled      = false,
  });

  String get label {
    if (isReady)              return 'SYSTEM READY';
    if (!nfcAvailable)        return 'NFC NOT SUPPORTED';
    if (!nfcEnabled)          return 'ENABLE NFC';
    if (!locationGranted)     return 'LOCATION NEEDED';
    return 'SETUP REQUIRED';
  }

  Color get color {
    if (isReady)          return AppColors.success;
    if (!locationGranted) return AppColors.warning;
    return AppColors.warning;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  int _selectedTab = 0;

  // ── System status ─────────────────────────────────────────────────────────
  _SystemStatus _status = const _SystemStatus();
  Timer? _statusTimer;

  // ── Contacts ──────────────────────────────────────────────────────────────
  List<_Contact> _contacts   = [];
  StreamSubscription? _contactsSub;
  bool _contactsLoading = true;

  // ── Enter animation ───────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // watch app lifecycle

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));

    _checkSystemStatus();
    _listenContacts();

    // Re-check status every 5 seconds (NFC can be toggled anytime)
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5), (_) => _checkSystemStatus());
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
    _contactsSub?.cancel();
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
        locationOk = gPerm == LocationPermission.always ||
            gPerm == LocationPermission.whileInUse;
      }
    } catch (_) {}

    // 2. NFC availability
    bool nfcAvailable = false;
    bool nfcEnabled   = false;
    try {
      final avail = await NfcManager.instance.checkAvailability();
      nfcAvailable = avail != NfcAvailability.unsupported;
      nfcEnabled   = avail == NfcAvailability.enabled;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _status = _SystemStatus(
        locationGranted: locationOk,
        nfcAvailable:    nfcAvailable,
        nfcEnabled:      nfcEnabled,
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Enable NFC',
          style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700)),
        content: const Text(
          'Go to Settings → Connections → NFC and turn it on.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
              style: TextStyle(fontFamily: 'Poppins',
                  color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
            child: const Text('Open Settings',
              style: TextStyle(fontFamily: 'Poppins',
                  color: Colors.white))),
        ],
      ),
    );
  }

  // ── Firestore live contacts stream ────────────────────────────────────────
  // Firestore structure:
  //   users/{ownerUid}/contacts/{contactUid}
  //     name:     string
  //     phone:    string
  //     isActive: bool       ← true if they have an active session right now
  //     lastSeen: timestamp  ← last time they were seen in a session
  //     isPaired: bool       ← NFC paired = true
  void _listenContacts() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _contactsLoading = false);
      return;
    }

    _contactsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .orderBy('isActive', descending: true)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _contacts = snap.docs
              .map((d) => _Contact.fromDoc(d))
              .toList();
          _contactsLoading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _contactsLoading = false);
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Stack(children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _topBar()),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _nfcCard(),
                )),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _quickActions(),
                )),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: _contactsHeader(),
                )),
                // Contacts list
                if (_contactsLoading)
                  const SliverToBoxAdapter(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2.5)),
                  ))
                else if (_contacts.isEmpty)
                  SliverToBoxAdapter(child: _emptyContacts())
                else
                  SliverList(delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _contactTile(_contacts[i]),
                    ),
                    childCount: _contacts.length,
                  )),

                SliverToBoxAdapter(child: _encBadge()),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
            Positioned(bottom: 78, right: 16, child: _sosFab()),
            Positioned(bottom: 0, left: 0, right: 0, child: _bottomNav()),
          ]),
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
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('TapGuard',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 20,
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E),
            )),
        ]),

        // Live system ready badge — tappable to fix issues
        GestureDetector(
          onTap: _status.isReady ? null : _requestPermissions,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _status.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Pulsing dot
              _statusDot(_status.color),
              const SizedBox(width: 6),
              Text(_status.label,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _status.color, letterSpacing: 0.5,
                )),
              if (!_status.isReady) ...[
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 10, color: _status.color),
              ],
            ]),
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
      builder: (_, v, __) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: color.withOpacity(v),
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
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Stack(children: [
      Positioned(top: -20, right: -20, child: Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withOpacity(0.05)),
      )),
      Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.crop_square_rounded,
              color: AppColors.primary, size: 30),
        ),
        const SizedBox(height: 14),
        const Text('Start NFC Pairing',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 20,
            fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E),
          )),
        const SizedBox(height: 6),
        Text(
          "Hold your phone near a trusted\nfriend's to instantly share location.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            color: Colors.grey.shade500, height: 1.55,
          )),
        const SizedBox(height: 18),

        // Tap to Pair — disabled if NFC not ready
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _status.nfcEnabled
                ? () => Navigator.of(context).pushNamed(AppRoutes.nfcPairing)
                : _requestPermissions,
            style: ElevatedButton.styleFrom(
              backgroundColor: _status.nfcEnabled
                  ? AppColors.primary : Colors.grey.shade400,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_status.nfcEnabled
                    ? Icons.back_hand_rounded
                    : Icons.wifi_off_rounded, size: 18),
                const SizedBox(width: 10),
                Text(
                  _status.nfcEnabled
                      ? 'Tap to Pair'
                      : 'Enable NFC to Pair',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
              ],
            ),
          ),
        ),
      ]),
    ]),
  );

  // ── Quick actions ─────────────────────────────────────────────────────────
  Widget _quickActions() => Row(children: [
    Expanded(child: _actionCard(
      icon: Icons.map_rounded,
      bg: const Color(0xFFDBEAFE),
      fg: const Color(0xFF2563EB),
      title: 'Safety Map',
      sub: 'Live view',
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.liveMap),
    )),
    const SizedBox(width: 12),
    Expanded(child: _actionCard(
      icon: Icons.timer_rounded,
      bg: const Color(0xFFFEF3C7),
      fg: const Color(0xFFD97706),
      title: 'Safe Timer',
      sub: 'Coming home',
      onTap: () =>
          Navigator.of(context).pushNamed(AppRoutes.activeSession),
    )),
  ]);

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
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: fg, size: 22),
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14,
          fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        Text(sub, style: TextStyle(
          fontFamily: 'Poppins', fontSize: 12,
          color: Colors.grey.shade400)),
      ]),
    ),
  );

  // ── Contacts header ───────────────────────────────────────────────────────
  Widget _contactsHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(children: [
        const Text('Trusted Contacts',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 18,
            fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E),
          )),
        if (_contacts.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text('${_contacts.length}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              )),
          ),
        ],
      ]),
      GestureDetector(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
        child: Text('See All',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 14,
            fontWeight: FontWeight.w600, color: AppColors.primary,
          )),
      ),
    ],
  );

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyContacts() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.15),
            width: 1.5),
      ),
      child: Column(children: [
        Icon(Icons.people_outline_rounded,
            color: AppColors.primary.withOpacity(0.4), size: 40),
        const SizedBox(height: 12),
        const Text('No trusted contacts yet',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 14,
            fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E),
          )),
        const SizedBox(height: 6),
        Text('Pair with a friend via NFC to add\nthem to your safety circle.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12,
            color: Colors.grey.shade400, height: 1.5,
          )),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.nfcPairing),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            backgroundColor: AppColors.primary.withOpacity(0.08),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Pair Someone Now',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
        ),
      ]),
    ),
  );

  // ── Live contact tile ─────────────────────────────────────────────────────
  Widget _contactTile(_Contact c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.03),
        blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Stack(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primary.withOpacity(0.12),
          child: Text(c.name[0].toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            )),
        ),
        if (c.isActive)
          Positioned(bottom: 0, right: 0,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2)),
            )),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 14,
              fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E),
            )),
          const SizedBox(height: 2),
          Row(children: [
            if (c.isActive) Container(
              width: 6, height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle)),
            Text(c.statusLabel,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                color: c.isActive
                    ? AppColors.success : Colors.grey.shade400,
                fontWeight: c.isActive
                    ? FontWeight.w600 : FontWeight.w400,
              )),
          ]),
        ],
      )),
      Icon(Icons.more_horiz_rounded,
          color: Colors.grey.shade300, size: 22),
    ]),
  );

  // ── E2E badge ─────────────────────────────────────────────────────────────
  Widget _encBadge() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.lock_outline_rounded,
          size: 12, color: Colors.grey.shade400),
      const SizedBox(width: 6),
      Text('END-TO-END ENCRYPTED SHARING',
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade400, letterSpacing: 0.8,
        )),
    ]),
  );

  // ── SOS FAB ───────────────────────────────────────────────────────────────
  Widget _sosFab() => GestureDetector(
    onTap: () {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushNamed(AppRoutes.sos);
    },
    child: Container(
      width: 64, height: 64,
      decoration: BoxDecoration(
        color: AppColors.sos, shape: BoxShape.circle,
        boxShadow: [BoxShadow(
          color: AppColors.sos.withOpacity(0.45),
          blurRadius: 16, spreadRadius: 2,
          offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.wifi_rounded, color: Colors.white, size: 20),
          Text('SOS', style: TextStyle(
            fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w800, color: Colors.white,
          )),
        ]),
    ),
  );

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded,     'label': 'Home'},
      {'icon': Icons.map_rounded,      'label': 'Map'},
      {'icon': Icons.people_rounded,   'label': 'Contacts'},
      {'icon': Icons.settings_rounded, 'label': 'Settings'},
    ];
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.07),
          blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(tabs.length, (i) {
          final sel = i == _selectedTab;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedTab = i);
              HapticFeedback.lightImpact();
              switch (i) {
                case 1:
                  Navigator.of(context).pushNamed(AppRoutes.liveMap);
                  break;
                case 2:
                  Navigator.of(context).pushNamed(AppRoutes.profile);
                  break;
                case 3:
                  Navigator.of(context).pushNamed(AppRoutes.settings);
                  break;
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tabs[i]['icon'] as IconData,
                  color: sel
                      ? AppColors.primary : Colors.grey.shade400,
                  size: 24),
                const SizedBox(height: 3),
                Text(tabs[i]['label'] as String,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: sel
                        ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? AppColors.primary : Colors.grey.shade400,
                  )),
              ],
            ),
          );
        }),
      ),
    );
  }
}