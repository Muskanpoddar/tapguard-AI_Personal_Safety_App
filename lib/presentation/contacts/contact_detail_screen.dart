// lib/presentation/contacts/contact_detail_screen.dart
//
// Per-contact detail screen opened by tapping a trusted-contact tile
// on Home or Profile. Surfaces:
//   • Last-seen status (live, via userContactsProvider stream)
//   • Primary action: "Share Live Location" — opens a fresh session
//     directly via SessionService.createSessionForContact, no QR/NFC.
//   • Secondary actions: rename, change priority, message, re-pair.
//   • Destructive: remove contact.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../data/models/contact_model.dart';
import '../../data/services/notification_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/session_provider.dart';

class ContactDetailScreen extends ConsumerStatefulWidget {
  /// Pass a contactUid (and optionally a snapshot of the contact).
  /// The screen resolves the contact from the parent
  /// userContactsProvider stream so the "last seen" label stays live.
  const ContactDetailScreen({
    super.key,
    required this.contactUid,
    this.initialContact,
  });

  final String contactUid;
  final ContactModel? initialContact;

  @override
  ConsumerState<ContactDetailScreen> createState() =>
      _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  final _notifService = NotificationService();
  bool _startingSession = false;

  ContactModel? _resolveContact(List<ContactModel> contacts) {
    for (final c in contacts) {
      if (c.uid == widget.contactUid) return c;
    }
    return widget.initialContact;
  }

  Future<void> _startSession(ContactModel c) async {
    if (_startingSession) return;
    setState(() => _startingSession = true);
    HapticFeedback.mediumImpact();

    try {
      final session = await ref.read(sessionActionsProvider).startForContact(c);

      // Push invite to the contact so they can join from the
      // notification — deep-link opens the live session.
      // Fire-and-forget: the OneSignal HTTP POST + Firestore read
      // were running on the UI isolate and pushing total latency
      // past the 6 s ANR threshold. Any failure here is non-fatal;
      // the recipient can still join via QR / NFC.
      unawaited(
        _notifService
            .sendNotificationToUser(
              targetUid: c.uid,
              title: '📍 Live location shared with you',
              body:
                  '${c.name} is sharing their live location. Tap to view in real-time.',
              type: 'session_invite',
              extraData: {
                'contactUid': c.uid,
                'contactName': c.name,
                'sessionId': session.sessionId,  // ← deep-link target
                'shareUrl': session.shareUrl,
              },
            )
            .catchError((Object e) {
              debugPrint('Notification send failed (non-blocking): $e');
              return false;
            }),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.liveSession);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start session: $e'),
          backgroundColor: AppColors.sos,
        ),
      );
    } finally {
      if (mounted) setState(() => _startingSession = false);
    }
  }

  Future<void> _renameContact(ContactModel c) async {
    final controller = TextEditingController(text: c.name);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rename Contact',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'e.g. Mom, Best friend',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed == c.name) return;

    final ok = await ref
        .read(profileServiceProvider)
        .updateContactName(c.uid, trimmed);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to "$trimmed"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not rename. Try again.'),
          backgroundColor: AppColors.sos,
        ),
      );
    }
  }

  Future<void> _changePriority(ContactModel c) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Set Priority',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final p in const [1, 2, 3])
              ListTile(
                leading: Icon(
                  Icons.circle,
                  color: _priorityColor(p),
                  size: 14,
                ),
                title: Text(
                  'P$p — ${_priorityLabel(p)}',
                  style: const TextStyle(fontFamily: 'Poppins'),
                ),
                trailing: c.priority == p
                    ? Icon(Icons.check_rounded, color: _priorityColor(p))
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected == null || selected == c.priority) return;
    final ok = await ref
        .read(profileServiceProvider)
        .updateContactPriority(c.uid, selected);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update priority.'),
          backgroundColor: AppColors.sos,
        ),
      );
    }
  }

  Future<void> _removeContact(ContactModel c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Contact?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${c.name} will no longer appear in your trusted contacts. '
          'You can re-add them later by scanning their QR code.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.sos,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final ok = await ref.read(profileServiceProvider).removeTrustedContact(c.uid);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove contact.'),
          backgroundColor: AppColors.sos,
        ),
      );
    }
  }

  Color _priorityColor(int p) {
    if (p == 1) return const Color(0xFFFF3B30);
    if (p == 2) return const Color(0xFFFF9500);
    return Colors.grey;
  }

  String _priorityLabel(int p) {
    if (p == 1) return 'High';
    if (p == 2) return 'Medium';
    return 'Low';
  }

  String _lastSeenLabel(DateTime? lastSeen) {
    if (lastSeen == null) return 'Never seen';
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$day  $h:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final contactsAsync = ref.watch(userContactsProvider(myUid));
    final contact = contactsAsync.maybeWhen(
      data: _resolveContact,
      orElse: () => widget.initialContact,
    );

    if (contact == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F3F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF4F3F8),
          elevation: 0,
          leading: _backButton(context),
        ),
        body: Center(
          child: Text(
            'Contact not found.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F3F8),
        elevation: 0,
        leading: _backButton(context),
        title: Text(
          contact.name,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(contact),
              const SizedBox(height: 16),
              _buildPrimaryAction(contact),
              const SizedBox(height: 8),
              _buildActionGrid(contact),
              const SizedBox(height: 16),
              _buildInfoCard(contact),
              const SizedBox(height: 16),
              _buildRemoveButton(contact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) => GestureDetector(
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
      );

  Widget _buildHero(ContactModel contact) {
    return Container(
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
          Stack(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  contact.name.isEmpty
                      ? '?'
                      : contact.name[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (contact.isActive)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            contact.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _priorityColor(contact.priority)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'P${contact.priority} • ${_priorityLabel(contact.priority)}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _priorityColor(contact.priority),
                      ),
                    ),
                  ),
                ),
              ),
              if (contact.isEmergencyContact) ...[
                const SizedBox(width: 6),
                Flexible(
                  fit: FlexFit.loose,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.sos.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'EMERGENCY',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.sos,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                contact.isActive ? Icons.circle : Icons.access_time_rounded,
                size: 14,
                color: contact.isActive
                    ? AppColors.success
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  contact.isActive
                      ? 'Active Now'
                      : 'Last seen: ${_lastSeenLabel(contact.lastSeen)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: contact.isActive
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: contact.isActive
                        ? AppColors.success
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction(ContactModel contact) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed:
            _startingSession ? null : () => _startSession(contact),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _startingSession
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.share_location_rounded, size: 22),
        label: Text(
          _startingSession ? 'Starting…' : 'Share Live Location',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid(ContactModel contact) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.4,
      children: [
        _ActionTile(
          icon: Icons.edit_rounded,
          label: 'Rename',
          onTap: () => _renameContact(contact),
        ),
        _ActionTile(
          icon: Icons.flag_rounded,
          label: 'Priority',
          onTap: () => _changePriority(contact),
        ),
        _ActionTile(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Re-pair',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.qrPairing),
        ),
        _ActionTile(
          icon: Icons.share_rounded,
          label: 'Share App',
          onTap: () => _shareAppLink(contact),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ContactModel contact) {
    return Container(
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
        children: [
          _InfoRow(
            icon: Icons.alternate_email_rounded,
            label: 'Email',
            value: contact.email.isEmpty ? '—' : contact.email,
          ),
          const Divider(height: 24),
          _InfoRow(
            icon: Icons.phone_rounded,
            label: 'Phone',
            value:
                contact.phoneNumber.isEmpty ? '—' : contact.phoneNumber,
          ),
          const Divider(height: 24),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Added',
            value: _formatDate(contact.addedAt),
          ),
          if (contact.lastSeen != null) ...[
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: 'Last seen',
              value: _formatDate(contact.lastSeen!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRemoveButton(ContactModel contact) {
    return SizedBox(
      height: 48,
      child: TextButton.icon(
        onPressed: () => _removeContact(contact),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.sos,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: AppColors.sos.withValues(alpha: 0.30),
            ),
          ),
        ),
        icon: const Icon(Icons.person_remove_rounded, size: 18),
        label: const Text(
          'Remove Contact',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _shareAppLink(ContactModel contact) async {
    // Uses share_plus via the platform channel — implemented in
    // the app shell to avoid a dependency in this widget.
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Invite ${contact.name} to download TapGuard from the app store.',
        ),
      ),
    );
  }
}

// ── Tiny reusable bits ────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: disabled ? Colors.grey : AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: disabled ? Colors.grey : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }
}