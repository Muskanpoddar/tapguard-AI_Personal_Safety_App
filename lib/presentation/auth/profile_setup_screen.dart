// lib/presentation/auth/profile_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/routes/app_routes.dart';
import '../../providers/profile_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  final String email;
  const ProfileSetupScreen({super.key, required this.email});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen>
    with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  bool _isSaving = false;
  bool _nameValid = false;

  // Stagger
  late List<AnimationController> _stagger;
  late List<Animation<double>> _stFade;
  late List<Animation<double>> _stSlide;

  // Avatar color picker
  int _colorIdx = 0;
  final List<Color> _colors = [
    AppColors.primary,
    const Color(0xFF06B6D4),
    const Color(0xFF10B981),
    const Color(0xFFF59E0B),
    const Color(0xFFEF4444),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _stagger = List.generate(
      5,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 550),
      ),
    );
    _stFade = _stagger
        .map(
          (c) => CurvedAnimation(
            parent: c,
            curve: Curves.easeIn,
          ).drive(Tween(begin: 0.0, end: 1.0)),
        )
        .toList();
    _stSlide = _stagger
        .map(
          (c) => CurvedAnimation(
            parent: c,
            curve: Curves.easeOutCubic,
          ).drive(Tween(begin: 32.0, end: 0.0)),
        )
        .toList();

    for (int i = 0; i < 5; i++) {
      Future.delayed(Duration(milliseconds: i * 90), () {
        if (mounted) _stagger[i].forward();
      });
    }

    _nameController.addListener(() {
      final v = _nameController.text.trim().length >= 2;
      if (v != _nameValid) setState(() => _nameValid = v);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    for (final c in _stagger) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _fade(int i, Widget child) => AnimatedBuilder(
    animation: _stagger[i],
    builder: (_, w) => Transform.translate(
      offset: Offset(0, _stSlide[i].value),
      child: Opacity(opacity: _stFade[i].value, child: w),
    ),
    child: child,
  );

  Future<void> _save() async {
    if (!_nameValid || _isSaving) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    final service = ref.read(profileServiceProvider);
    final success = await service.createUserProfile(
      name: _nameController.text.trim(),
      email: widget.email,
      avatarColor: _colorIdx,
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not save profile. Please try again.',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: AppColors.sos,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                _fade(0, _buildProgress()),
                const SizedBox(height: 28),
                _fade(1, _buildAvatar()),
                const SizedBox(height: 24),
                _fade(2, _buildTitle()),
                const SizedBox(height: 24),
                _fade(3, _buildCard()),
                const SizedBox(height: 20),
                _fade(4, _buildSaveBtn()),
                const SizedBox(height: 12),
                _fade(
                  4,
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context)
                            .pushReplacementNamed(AppRoutes.home),
                    child: Text(
                      AppStrings.skipForNow,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step progress dots ────────────────────────────────────────────────────
  Widget _buildProgress() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == 2;
        final done = i < 2;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 32 : 10,
          height: 4,
          decoration: BoxDecoration(
            color: done || active
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  // ── Avatar with color picker ──────────────────────────────────────────────
  Widget _buildAvatar() {
    final initials = _nameController.text.trim().isEmpty
        ? '?'
        : _nameController.text.trim()[0].toUpperCase();
    final color = _colors[_colorIdx];

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Color chips
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(_colors.length, (i) {
            final sel = i == _colorIdx;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _colorIdx = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: sel ? 28 : 22,
                height: sel ? 28 : 22,
                decoration: BoxDecoration(
                  color: _colors[i],
                  shape: BoxShape.circle,
                  border: sel
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: _colors[i].withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Title ─────────────────────────────────────────────────────────────────
  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          AppStrings.setupProfile,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.setupProfileBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey.shade500,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // ── Form card ─────────────────────────────────────────────────────────────
  Widget _buildCard() {
    return Container(
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
        children: [
          // Signed-in email chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.alternate_email_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.signedInAs,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        widget.email,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_rounded,
                  color: AppColors.success,
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Name field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                AppStrings.yourName,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                keyboardType: TextInputType.name,
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
                decoration: InputDecoration(
                  hintText: AppStrings.yourNameHint,
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                  prefixIcon: Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF0EFF5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info note (phone added later)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.phone_android_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.phoneLaterHint,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Save button ───────────────────────────────────────────────────────────
  Widget _buildSaveBtn() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_nameValid && !_isSaving) ? _save : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    AppStrings.saveProfile,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
      ),
    );
  }
}
