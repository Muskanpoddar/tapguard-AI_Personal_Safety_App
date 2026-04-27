// lib/presentation/history/session_history_screen.dart
//
// Full Session History Screen
// ────────────────────────────
// Features:
//   - List of all past sessions from Firestore
//   - Each entry shows: date, paired contact, duration, status
//   - Status badges: "Normal" (green) or "SOS Triggered" (red)
//   - Tap to view session details
//   - Pull-to-refresh
//
// Firestore path: users/{uid}/contacts — each contact has session history
// Or sessions collection — sessions are stored at sessions/{sessionId}

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<_SessionEntry> _sessions = [];
  bool _loading = true;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      // Load sessions from Firestore — sorted by createdAt desc
      final snap = await _db
          .collection('sessions')
          .where('ownerUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      if (!mounted) return;
      setState(() {
        _sessions = snap.docs.map((d) => _SessionEntry.fromDoc(d)).toList();
        _loading = false;
        _hasMore = snap.docs.length >= 20;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3))
          : _sessions.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: const Color(0xFFF4F3F8),
    elevation: 0,
    leading: GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFF1A1A2E)),
      ),
    ),
    title: const Text('Session History', style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
    centerTitle: true,
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history_rounded, color: AppColors.primary.withOpacity(0.3), size: 72),
        const SizedBox(height: 16),
        const Text('No sessions yet', style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        Text('Start sharing with a contact to see your history', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey.shade500)),
      ],
    ),
  );

  Widget _buildList() => RefreshIndicator(
    color: AppColors.primary,
    onRefresh: _loadSessions,
    child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _sessions.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
          );
        }
        return _buildSessionTile(_sessions[i]);
      },
    ),
  );

  Widget _buildSessionTile(_SessionEntry s) {
    final statusColor = s.isSos ? AppColors.sos : AppColors.success;
    final statusLabel = s.isSos ? 'SOS Triggered' : 'Normal';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: statusColor.withOpacity(0.10),
            child: Icon(
              s.isSos ? Icons.warning_rounded : Icons.people_rounded,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.contactName,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 2),
                Text(
                  s.formattedDate,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.timer_rounded, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      s.formattedDuration,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Status + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.formattedTime,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Session entry model ────────────────────────────────────────────────────
class _SessionEntry {
  final String sessionId;
  final String contactName;
  final DateTime createdAt;
  final DateTime? endedAt;
  final bool isActive;
  final bool isSos;
  final double? ownerLat;
  final double? ownerLng;

  _SessionEntry({
    required this.sessionId,
    required this.contactName,
    required this.createdAt,
    this.endedAt,
    required this.isActive,
    required this.isSos,
    this.ownerLat,
    this.ownerLng,
  });

  factory _SessionEntry.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _SessionEntry(
      sessionId: doc.id,
      contactName: d['receiverName'] as String? ?? d['ownerName'] as String? ?? 'Contact',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      isActive: d['isActive'] as bool? ?? false,
      isSos: d['sosTriggered'] == true,
      ownerLat: (d['ownerLat'] as num?)?.toDouble(),
      ownerLng: (d['ownerLng'] as num?)?.toDouble(),
    );
  }

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(createdAt);
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  String get formattedTime {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get formattedDuration {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m duration';
    return '${m} min duration';
  }
}
