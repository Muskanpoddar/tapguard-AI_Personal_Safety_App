// lib/presentation/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;

  // TODO: replace with real Firestore stream
  final List<Map<String, dynamic>> _contacts = [
    {'name': 'Sarah Jenkins', 'status': 'Active Now', 'active': true},
    {'name': 'Maya Patel', 'status': 'Last seen: 12 mins ago', 'active': false},
    {'name': 'Emma Wilson', 'status': 'Last seen: 2h ago', 'active': false},
  ];

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Stack(
            children: [
              // ── Scrollable content ────────────────────────────────────────
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
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
                      child: _contactsHeader(),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _contactTile(_contacts[i]),
                      ),
                      childCount: _contacts.length,
                    ),
                  ),
                  SliverToBoxAdapter(child: _encBadge()),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),

              // ── SOS FAB ───────────────────────────────────────────────────
              Positioned(bottom: 78, right: 16, child: _sosFab()),

              // ── Bottom nav ────────────────────────────────────────────────
              Positioned(bottom: 0, left: 0, right: 0, child: _bottomNav()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
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
                color: AppColors.primary.withOpacity(0.12),
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

        // SYSTEM READY badge — matches Image 6
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'SYSTEM READY',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── NFC hero card ─────────────────────────────────────────────────────────
  Widget _nfcCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          top: -20,
          right: -20,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.05),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.crop_square_rounded,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Start NFC Pairing',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Hold your phone near a trusted\nfriend's to instantly share location.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.nfcPairing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.back_hand_rounded, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Tap to Pair',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
            color: Colors.black.withOpacity(0.04),
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
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    ),
  );

  // ── Contacts header ───────────────────────────────────────────────────────
  Widget _contactsHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
      GestureDetector(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
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

  // ── Contact tile ──────────────────────────────────────────────────────────
  Widget _contactTile(Map<String, dynamic> c) {
    final active = c['active'] as bool;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                backgroundColor: AppColors.primary.withOpacity(0.12),
                child: Text(
                  (c['name'] as String)[0],
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (active)
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
                Text(
                  c['name'] as String,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (active)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      c['status'] as String,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: active
                            ? AppColors.success
                            : Colors.grey.shade400,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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
    );
  }

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

  // ── SOS FAB ───────────────────────────────────────────────────────────────
  Widget _sosFab() => GestureDetector(
    onTap: () {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushNamed(AppRoutes.sos);
    },
    child: Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.sos,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.sos.withOpacity(0.45),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.wifi_rounded, color: Colors.white, size: 20),
          Text(
            'SOS',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.map_rounded, 'label': 'Map'},
      {'icon': Icons.people_rounded, 'label': 'Contacts'},
      {'icon': Icons.settings_rounded, 'label': 'Settings'},
    ];
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
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
                Icon(
                  tabs[i]['icon'] as IconData,
                  color: sel ? AppColors.primary : Colors.grey.shade400,
                  size: 24,
                ),
                const SizedBox(height: 3),
                Text(
                  tabs[i]['label'] as String,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? AppColors.primary : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
