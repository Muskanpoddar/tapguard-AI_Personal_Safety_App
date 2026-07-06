// lib/presentation/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapguard/core/constants/app_colors.dart';
import 'package:tapguard/core/constants/app_strings.dart';
import 'package:tapguard/core/routes/app_routes.dart';
import 'package:tapguard/data/models/user_model.dart';
import 'package:tapguard/data/services/auth_session_service.dart';
import 'package:tapguard/providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const List<Color> _avatarColors = [
    AppColors.primary,
    Color(0xFF06B6D4),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
  ];

  // Edit-profile sheet state
  final _editNameCtrl = TextEditingController();
  final _editEmailCtrl = TextEditingController();
  final _editPhoneCtrl = TextEditingController();
  int _editColorIdx = 0;
  bool _editingProfile = false;
  bool _savingProfile = false;

  @override
  void dispose() {
    _editNameCtrl.dispose();
    _editEmailCtrl.dispose();
    _editPhoneCtrl.dispose();
    super.dispose();
  }

  // ── EDIT PROFILE BOTTOM SHEET ──────────────────────────────────────────────
  void _openEditProfile({
    required String name,
    required String email,
    required String phone,
    required int colorIdx,
  }) {
    _editNameCtrl.text = name;
    _editEmailCtrl.text = email;
    _editPhoneCtrl.text = phone;
    _editColorIdx = colorIdx.clamp(0, _avatarColors.length - 1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      AppStrings.editProfile,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(sheetCtx).pop(),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Color picker preview
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color:
                          _avatarColors[_editColorIdx].withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _avatarColors[_editColorIdx],
                        width: 2.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _editNameCtrl.text.trim().isEmpty
                            ? '?'
                            : _editNameCtrl.text.trim()[0].toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _avatarColors[_editColorIdx],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Color chips
                Center(
                  child: Wrap(
                    spacing: 10,
                    children: List.generate(_avatarColors.length, (i) {
                      final sel = i == _editColorIdx;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setSheet(() => _editColorIdx = i);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: sel ? 30 : 22,
                          height: sel ? 30 : 22,
                          decoration: BoxDecoration(
                            color: _avatarColors[i],
                            shape: BoxShape.circle,
                            border: sel
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: sel
                                ? [
                                    BoxShadow(
                                      color: _avatarColors[i]
                                          .withValues(alpha: 0.4),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 20),

                _label(AppStrings.yourName),
                const SizedBox(height: 6),
                _sheetField(
                  controller: _editNameCtrl,
                  hint: AppStrings.yourNameHint,
                  icon: Icons.person_rounded,
                  keyboardType: TextInputType.name,
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: 14),

                _label(AppStrings.emailAddress),
                const SizedBox(height: 6),
                _sheetField(
                  controller: _editEmailCtrl,
                  hint: AppStrings.emailPlaceholder,
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),

                _label(AppStrings.phoneNumber),
                const SizedBox(height: 6),
                _sheetField(
                  controller: _editPhoneCtrl,
                  hint: AppStrings.phonePlaceholder,
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _savingProfile ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _savingProfile
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            AppStrings.saveChanges,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      _editingProfile = false;
    });
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Poppins',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1A1A2E),
    ),
  );

  Widget _sheetField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          color: Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Color(0xFF999999),
          ),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final name = _editNameCtrl.text.trim();
    final email = _editEmailCtrl.text.trim();
    final phone = _editPhoneCtrl.text.trim();
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );

    if (name.isEmpty) {
      _toast(AppStrings.pleaseEnterName, error: true);
      return;
    }
    if (!emailRegex.hasMatch(email)) {
      _toast(AppStrings.pleaseEnterEmail, error: true);
      return;
    }
    if (phone.isEmpty) {
      _toast(AppStrings.pleaseEnterPhone, error: true);
      return;
    }

    setState(() => _savingProfile = true);

    final service = ref.read(profileServiceProvider);
    final ok = await service.updateUserProfile(
      name: name,
      email: email,
      phoneNumber: phone,
      avatarColor: _editColorIdx,
    );

    if (!mounted) return;
    setState(() => _savingProfile = false);

    if (!ok) {
      _toast('Could not save. Please try again.', error: true);
      return;
    }

    Navigator.of(context).pop();
    _toast(AppStrings.profileUpdated, error: false);
  }


  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          AppStrings.logoutConfirmTitle,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          AppStrings.logoutConfirmBody,
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await AuthSessionService.clearSession();
              if (!mounted) return;
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
            },
            child: const Text(
              AppStrings.logout,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFFFF3B30),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: error ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          AppStrings.account,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: userAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(fontFamily: 'Poppins'),
          ),
        ),
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text(
                'No profile found',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
            );
          }

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _buildProfileCard(user),
              const SizedBox(height: 24),
              _buildPersonalizationSection(),
              const SizedBox(height: 24),
              _buildSettingsSection(),
            ],
          );
        },
      ),
    );
  }

  // ── PROFILE CARD ──────────────────────────────────────────────────────────
  Widget _buildProfileCard(UserModel user) {
    final color = _avatarColors[
        user.avatarColor.clamp(0, _avatarColors.length - 1)];
    final hasPhone = user.phoneNumber.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
            ),
            child: Center(
              child: Text(
                user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            user.name.isEmpty ? 'No Name' : user.name,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),

          // Email
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.alternate_email_rounded,
                size: 14,
                color: Color(0xFF999999),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  user.email.isEmpty ? 'No email' : user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF999999),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),

          // Phone (warning if missing)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.phone_iphone_rounded,
                size: 13,
                color: hasPhone ? const Color(0xFF999999) : const Color(0xFFFF9500),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  hasPhone ? user.phoneNumber : 'Add phone for SOS SMS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: hasPhone ? FontWeight.w400 : FontWeight.w600,
                    color: hasPhone
                        ? const Color(0xFF999999)
                        : const Color(0xFFFF9500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Edit profile button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _editingProfile
                  ? null
                  : () {
                      setState(() => _editingProfile = true);
                      _openEditProfile(
                        name: user.name,
                        email: user.email,
                        phone: user.phoneNumber,
                        colorIdx: user.avatarColor,
                      );
                    },
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text(
                AppStrings.editProfile,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PERSONALIZATION SECTION (Phase 5) ─────────────────────────────────
  Widget _buildPersonalizationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Personalization',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'On-device learning. Nothing is uploaded.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'TapGuard learns your usual places, times, and motion patterns '
            'on your phone. The risk engine compares what you\'re doing right '
            'now against your baseline and raises the score on unusual '
            'behaviour.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.riskInsights),
            icon: const Icon(Icons.insights_rounded, size: 16),
            label: const Text(
              'View Risk Insights',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.50),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ],
      ),
    );
  }

  // ── SETTINGS SECTION ──────────────────────────────────────────────────────
  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _settingTile(
            icon: Icons.notifications_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'Notifications',
            onTap: () {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            },
          ),
          const Divider(height: 1, indent: 60),
          _settingTile(
            icon: Icons.privacy_tip_rounded,
            iconColor: AppColors.primary,
            title: 'Privacy & Permissions',
            onTap: () {
              Navigator.of(context).pushNamed(AppRoutes.privacy);
            },
          ),
          const Divider(height: 1, indent: 60),
          _settingTile(
            icon: Icons.settings_rounded,
            iconColor: Colors.grey.shade600,
            title: 'Settings',
            onTap: () {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            },
          ),
          const Divider(height: 1, indent: 60),
          _settingTile(
            icon: Icons.logout_rounded,
            iconColor: const Color(0xFFFF3B30),
            title: AppStrings.logout,
            titleColor: const Color(0xFFFF3B30),
            onTap: _confirmLogout,
          ),
        ],
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: titleColor ?? const Color(0xFF1A1A2E),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFFCCCCCC),
      ),
    );
  }
}
