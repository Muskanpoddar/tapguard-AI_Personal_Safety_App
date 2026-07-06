// lib/core/utils/contact_extensions.dart
//
// Shared helpers for the ContactModel — moved out of home_screen.dart
// in Phase 9 so the new ContactsScreen (and any future surface) can
// reuse the same "status label" + "priority color" logic.

import 'package:flutter/material.dart';
import '../../data/models/contact_model.dart';

extension ContactStatus on ContactModel {
  /// Human-readable "last seen" label used by the home preview tile,
  /// the contact detail screen, and the contacts list.
  String get statusLabel {
    if (isActive) return 'Active Now';
    if (lastSeen == null) return 'Never seen';
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return 'Last seen: ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last seen: ${diff.inHours}h ago';
    return 'Last seen: ${diff.inDays}d ago';
  }
}

/// Priority badge colour. P1 = red, P2 = orange, anything else = grey.
Color priorityColor(int p) {
  if (p == 1) return const Color(0xFFFF3B30); // high — red
  if (p == 2) return const Color(0xFFFF9500); // medium — orange
  return Colors.grey; // low
}