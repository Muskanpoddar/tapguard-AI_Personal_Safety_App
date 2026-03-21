import 'package:flutter/material.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/auth_session_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _locationHintsEnabled = true;
  bool _isLoggingOut = false;

  Future<void> _showComingSoon(String featureName) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$featureName is coming soon',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    final confirmLogout =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text(
                'Log out?',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              content: const Text(
                'You will need to verify again after logging out.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Log Out'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmLogout || !mounted) return;

    setState(() => _isLoggingOut = true);
    try {
      await AuthSessionService.clearSession();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.splash, (route) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to log out. Please try again.',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C4DFF);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: accent,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          _SectionTitle(title: 'General', color: accent),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _notificationsEnabled,
                  activeThumbColor: accent,
                  activeTrackColor: accent.withValues(alpha: 0.35),
                  title: const Text(
                    'Push notifications',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  subtitle: const Text(
                    'Random placeholder toggle for now',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  ),
                  onChanged: (value) {
                    setState(() => _notificationsEnabled = value);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: _locationHintsEnabled,
                  activeThumbColor: accent,
                  activeTrackColor: accent.withValues(alpha: 0.35),
                  title: const Text(
                    'Location hints',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  subtitle: const Text(
                    'Another temporary setting',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  ),
                  onChanged: (value) {
                    setState(() => _locationHintsEnabled = value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tune_rounded, color: accent),
                  title: const Text(
                    'Random setting action',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  subtitle: const Text(
                    'Temporary button for testing',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showComingSoon('Random setting action'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'Security', color: accent),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_rounded, color: accent),
                  title: const Text(
                    'Privacy permissions',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  subtitle: const Text(
                    'Review app permission settings',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.privacy),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isLoggingOut ? null : _handleLogout,
                      icon: _isLoggingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.logout_rounded),
                      label: Text(
                        _isLoggingOut ? 'Logging out...' : 'Log Out',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Logout clears your local session and Firebase auth session.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}
