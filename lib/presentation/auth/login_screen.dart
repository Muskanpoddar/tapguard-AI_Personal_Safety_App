import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/routes/app_routes.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  LOGIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();

  String _selectedCountryCode = '+1';
  String _selectedFlag = '🇺🇸';
  bool _isLoading = false;
  bool _phoneValid = false;

  // Entrance animation
  late AnimationController _enterController;
  late Animation<double> _enterFade;
  late Animation<double> _enterSlide;

  // Country codes list
  final List<Map<String, String>> _countryCodes = [
    {'flag': '🇺🇸', 'code': '+1', 'name': 'United States'},
    {'flag': '🇬🇧', 'code': '+44', 'name': 'United Kingdom'},
    {'flag': '🇮🇳', 'code': '+91', 'name': 'India'},
    {'flag': '🇦🇺', 'code': '+61', 'name': 'Australia'},
    {'flag': '🇨🇦', 'code': '+1', 'name': 'Canada'},
    {'flag': '🇩🇪', 'code': '+49', 'name': 'Germany'},
    {'flag': '🇫🇷', 'code': '+33', 'name': 'France'},
    {'flag': '🇸🇦', 'code': '+966', 'name': 'Saudi Arabia'},
    {'flag': '🇵🇰', 'code': '+92', 'name': 'Pakistan'},
    {'flag': '🇧🇩', 'code': '+880', 'name': 'Bangladesh'},
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

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _enterFade = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));
    _enterSlide = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 40.0, end: 0.0));

    _enterController.forward();

    _phoneController.addListener(() {
      final isValid = _phoneController.text.trim().length >= 7;
      if (isValid != _phoneValid) {
        setState(() => _phoneValid = isValid);
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocus.dispose();
    _enterController.dispose();
    super.dispose();
  }

  // ── Send OTP ──────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (!_phoneValid) return;

    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    final fullPhone = '$_selectedCountryCode${_phoneController.text.trim()}';

    // TODO: Replace this block with Firebase Phone Auth:
    // await FirebaseAuth.instance.verifyPhoneNumber(
    //   phoneNumber: fullPhone,
    //   verificationCompleted: (PhoneAuthCredential credential) async {
    //     await FirebaseAuth.instance.signInWithCredential(credential);
    //     Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    //   },
    //   verificationFailed: (FirebaseAuthException e) {
    //     setState(() => _isLoading = false);
    //     _showError(e.message ?? 'Verification failed');
    //   },
    //   codeSent: (String verificationId, int? resendToken) {
    //     setState(() => _isLoading = false);
    //     Navigator.of(context).pushNamed(
    //       AppRoutes.otp,
    //       arguments: {'phone': fullPhone, 'verificationId': verificationId},
    //     );
    //   },
    //   codeAutoRetrievalTimeout: (String verificationId) {},
    // );

    // Simulate OTP send for now
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    setState(() => _isLoading = false);
    Navigator.of(context).pushNamed(AppRoutes.otp, arguments: fullPhone);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppColors.sos,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Country picker sheet ──────────────────────────────────────────────────
  void _pickCountry() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Country',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _countryCodes.length,
                itemBuilder: (_, i) {
                  final c = _countryCodes[i];
                  final selected =
                      c['code'] == _selectedCountryCode &&
                      c['flag'] == _selectedFlag;
                  return ListTile(
                    leading: Text(
                      c['flag']!,
                      style: const TextStyle(fontSize: 28),
                    ),
                    title: Text(
                      c['name']!,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Text(
                      c['code']!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    selected: selected,
                    selectedTileColor: AppColors.primary.withOpacity(0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedCountryCode = c['code']!;
                        _selectedFlag = c['flag']!;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
            child: AnimatedBuilder(
              animation: _enterController,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _enterSlide.value),
                child: Opacity(opacity: _enterFade.value, child: child),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 48),

                  // ── Logo ──────────────────────────────────────────────
                  _buildLogo(),

                  const SizedBox(height: 32),

                  // ── Title ─────────────────────────────────────────────
                  const Text(
                    AppStrings.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    AppStrings.welcomeBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Phone input card ──────────────────────────────────
                  _buildPhoneCard(),

                  const SizedBox(height: 52),

                  // ── Footer ────────────────────────────────────────────
                  _buildFooter(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Icon(Icons.shield_rounded, color: AppColors.primary, size: 38),
      ),
    );
  }

  // ── Phone number card ─────────────────────────────────────────────────────
  Widget _buildPhoneCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          const Text(
            AppStrings.phoneNumber,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),

          const SizedBox(height: 12),

          // Country code + phone field
          Row(
            children: [
              // Country picker button
              GestureDetector(
                onTap: _pickCountry,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EFF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_selectedFlag, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 6),
                      Text(
                        _selectedCountryCode,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Phone number text field
              Expanded(
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EFF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _phoneFocus.hasFocus
                          ? AppColors.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A2E),
                    ),
                    decoration: InputDecoration(
                      hintText: AppStrings.phonePlaceholder,
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: Colors.grey.shade400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 15,
                      ),
                    ),
                    onSubmitted: (_) => _sendOtp(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Send OTP button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_phoneValid && !_isLoading) ? _sendOtp : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
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
                      children: [
                        Text(
                          AppStrings.sendOtp,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 14),

          // Privacy note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EFF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.locationEncrypted,
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

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        // Privacy + Terms links
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {},
              child: Text(
                AppStrings.privacyPolicy,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: Text(
                AppStrings.termsOfService,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // NFC badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.crop_square_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                AppStrings.nfcEnabledPrivacy,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
