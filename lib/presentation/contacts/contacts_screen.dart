// lib/presentation/contacts/contacts_screen.dart
//
// Full-screen contacts management surface — promoted from the
// Profile screen's "Trusted Contacts" section in Phase 9. Reached
// via the bottom-navbar Contacts tab OR via the Home "See All" link.
//
// Features:
//   • Live list (userContactsProvider stream) — sorted by priority
//     then recency, inherited from the stream query.
//   • Search bar — matches name / email / phone (case-insensitive).
//   • Filter chips — All / Emergency / P1 / P2 / P3.
//   • Manual Add Contact bottom sheet (moved here from Profile).
//   • Pair CTA — extended FAB → /qr-pairing.
//   • Tap row → ContactDetailScreen (Phase 8).
//   • Empty states — "no contacts yet" vs "no matches".

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../core/utils/contact_extensions.dart';
import '../../data/models/contact_model.dart';
import '../../providers/profile_provider.dart';

// ── Pure filter logic — exported as a top-level function so it can be
// unit-tested without a widget tree.
List<ContactModel> filterContacts(
  List<ContactModel> contacts, {
  String query = '',
  int? priority,
  bool emergencyOnly = false,
}) {
  final q = query.trim().toLowerCase();
  return contacts.where((c) {
    if (emergencyOnly && !c.isEmergencyContact) return false;
    if (priority != null && c.priority != priority) return false;
    if (q.isEmpty) return true;
    if (c.name.toLowerCase().contains(q)) return true;
    if (c.email.toLowerCase().contains(q)) return true;
    if (c.phoneNumber.toLowerCase().contains(q)) return true;
    return false;
  }).toList();
}

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  int? _priority;
  bool _emergencyOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetFilters() {
    setState(() {
      _searchCtrl.clear();
      _query = '';
      _priority = null;
      _emergencyOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final contactsAsync = ref.watch(userContactsProvider(myUid));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F3F8),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        title: contactsAsync.maybeWhen(
          data: (list) => Text(
            'Contacts',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          orElse: () => const Text(
            'Contacts',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          contactsAsync.maybeWhen(
            data: (list) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    '${list.length}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            onPressed: () => _openAddContactSheet(),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            color: AppColors.primary,
            tooltip: 'Add manually',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            _buildFilterChips(),
            Expanded(
              child: contactsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading contacts: $e',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                data: (contacts) => _buildBody(contacts),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pushNamed(AppRoutes.qrPairing);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text(
          'Pair',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search contacts',
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.grey.shade500,
              size: 20,
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade500,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _Chip(
            label: 'All',
            selected: _priority == null && !_emergencyOnly,
            onTap: () => setState(() {
              _priority = null;
              _emergencyOnly = false;
            }),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Emergency',
            icon: Icons.shield_rounded,
            selected: _emergencyOnly,
            color: AppColors.sos,
            onTap: () => setState(() {
              _emergencyOnly = !_emergencyOnly;
              _priority = null;
            }),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'P1 High',
            selected: _priority == 1,
            color: priorityColor(1),
            onTap: () => setState(() {
              _priority = _priority == 1 ? null : 1;
              _emergencyOnly = false;
            }),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'P2 Medium',
            selected: _priority == 2,
            color: priorityColor(2),
            onTap: () => setState(() {
              _priority = _priority == 2 ? null : 2;
              _emergencyOnly = false;
            }),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'P3 Low',
            selected: _priority == 3,
            color: priorityColor(3),
            onTap: () => setState(() {
              _priority = _priority == 3 ? null : 3;
              _emergencyOnly = false;
            }),
          ),
        ],
      ),
    );
  }

  // ── List body ──────────────────────────────────────────────────────────

  Widget _buildBody(List<ContactModel> allContacts) {
    final filtered = filterContacts(
      allContacts,
      query: _query,
      priority: _priority,
      emergencyOnly: _emergencyOnly,
    );

    if (allContacts.isEmpty) {
      return _buildNoContactsEmpty();
    }
    if (filtered.isEmpty) {
      return _buildNoMatchesEmpty();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ContactRow(contact: filtered[i]),
    );
  }

  Widget _buildNoContactsEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No trusted contacts yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pair with someone to start sharing your live location.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.qrPairing),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text(
                'Pair a contact',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No matches',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text(
                'Clear filters',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Manual add sheet ───────────────────────────────────────────────────

  void _openAddContactSheet() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool isEmergency = false;
    int priority = 3;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          return Padding(
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
                      const Expanded(
                        child: Text(
                          'Add Trusted Contact',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(sheetCtx).pop(),
                        child: Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _label('Full Name'),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDeco('Sarah Johnson'),
                  ),
                  const SizedBox(height: 14),
                  _label('Email'),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDeco('sarah@example.com'),
                  ),
                  const SizedBox(height: 14),
                  _label('Phone (for SOS SMS)'),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDeco('+1 555 123 4567'),
                  ),
                  const SizedBox(height: 18),
                  // Emergency toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.sos.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          color: AppColors.sos,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Primary Emergency Contact',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: isEmergency,
                          activeThumbColor: AppColors.sos,
                          onChanged: (v) => setSheet(() => isEmergency = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Priority picker
                  _label('Priority'),
                  Row(
                    children: [
                      for (final p in const [1, 2, 3]) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSheet(() => priority = p),
                            child: Container(
                              margin: EdgeInsets.only(
                                right: p == 3 ? 0 : 8,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: priority == p
                                    ? priorityColor(p).withValues(alpha: 0.15)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: priority == p
                                      ? priorityColor(p)
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'P$p',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: priority == p
                                        ? priorityColor(p)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final email = emailCtrl.text.trim();
                              final phone = phoneCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Name is required.'),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => saving = true);
                              HapticFeedback.lightImpact();
                              final uid = FirebaseAuth.instance.currentUser
                                      ?.uid ??
                                  'local_${DateTime.now().millisecondsSinceEpoch}';
                              final ok = await ref
                                  .read(profileServiceProvider)
                                  .addTrustedContact(
                                    contactUid: uid,
                                    contactName: name,
                                    contactEmail: email,
                                    contactPhone: phone,
                                    isEmergency: isEmergency,
                                    priority: priority,
                                  );
                              if (!mounted) return;
                              setSheet(() => saving = false);
                              if (ok) {
                                if (sheetCtx.mounted) {
                                  Navigator.of(sheetCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$name added')),
                                  );
                                }
                              } else {
                                if (sheetCtx.mounted) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not add contact. Please try again.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Add Contact',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.grey.shade400,
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );
}

// ── Reusable bits ─────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: selected ? c : Colors.grey.shade200,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? c : Colors.grey.shade600),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? c : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});

  final ContactModel contact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(
        AppRoutes.contactDetail,
        arguments: {'contactUid': contact.uid},
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar + active dot
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    contact.name.isEmpty
                        ? '?'
                        : contact.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (contact.isActive)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      if (contact.priority > 0 && contact.priority <= 3)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: priorityColor(contact.priority)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'P${contact.priority}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: priorityColor(contact.priority),
                            ),
                          ),
                        ),
                      if (contact.isEmergencyContact) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.shield_rounded,
                          color: AppColors.sos,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        contact.isActive
                            ? Icons.circle
                            : Icons.access_time_rounded,
                        size: 12,
                        color: contact.isActive
                            ? AppColors.success
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          contact.statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: contact.isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: contact.isActive
                                ? AppColors.success
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                      if (contact.phoneNumber.isNotEmpty) ...[
                        Text(
                          '  •  ',
                          style: TextStyle(
                            color: Colors.grey.shade300,
                            fontSize: 11,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            contact.phoneNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade300,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}