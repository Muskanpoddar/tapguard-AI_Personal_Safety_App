import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../contacts/contacts_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  static const _tabs = [
    {'icon': Icons.home_rounded, 'label': 'Home'},
    {'icon': Icons.people_alt_rounded, 'label': 'Contacts'},
    {'icon': Icons.sos_rounded, 'label': 'SOS'},
    {'icon': Icons.person_rounded, 'label': 'Profile'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          const ContactsScreen(),
          const _SosPlaceholder(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_tabs.length, (i) {
            final sel = i == _currentIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (i == 2) {
                    Navigator.of(context).pushNamed(AppRoutes.sos);
                    return;
                  }
                  if (i == _currentIndex) return;
                  setState(() => _currentIndex = i);
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _tabs[i]['icon'] as IconData,
                      color: sel ? AppColors.primary : Colors.grey.shade400,
                      size: 24,
                    ),
                    const SizedBox(height: 3),
                    Flexible(
                      child: Text(
                        _tabs[i]['label'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          color: sel ? AppColors.primary : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _SosPlaceholder extends StatelessWidget {
  const _SosPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF4F3F8),
      body: Center(
        child: Text(
          'Tap SOS to trigger emergency',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
