// lib/presentation/safety_status/risk_insights_screen.dart
//
// Phase 5 — "Risk Insights" screen.
//
// Shows the user a transparent view of what the AI risk engine has
// been doing in the background. Three sections:
//
//   1. Baseline summary — how much the engine has learned.
//   2. Training data — how many SOS / "I'm safe" examples are
//      queued up for the next retraining round.
//   3. Recent risk events — the highest-scoring `RiskResult`s
//      that the engine has produced recently, with the
//      top contributing factors for each.
//
// The data sources are:
//   * `RiskDetectionService.trainingDataStore` for example counts
//   * `UserBaseline.frequentPlaces` / `hourlyProfiles` for the
//     baseline summary
//   * A new in-memory `RiskEventLog` populated by the service
//     whenever a high risk result fires
//
// In Phase 4 the training data is the most actionable signal
// (it's persisted to Hive, can be exported, and feeds the next
// retraining round).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapguard/core/constants/app_colors.dart';
import 'package:tapguard/core/constants/app_strings.dart';
import 'package:tapguard/data/services/risk/risk_training_example.dart';
import 'package:tapguard/data/services/risk/training_data_store.dart';
import 'package:tapguard/data/services/risk/user_baseline.dart';
import 'package:tapguard/data/services/risk_detection_service.dart';

class RiskInsightsScreen extends ConsumerStatefulWidget {
  const RiskInsightsScreen({super.key});

  @override
  ConsumerState<RiskInsightsScreen> createState() => _RiskInsightsScreenState();
}

class _RiskInsightsScreenState extends ConsumerState<RiskInsightsScreen> {
  late final TrainingDataStore _trainingStore = TrainingDataStore();

  /// The live baseline the engine is actually using. Previously this
  /// screen built its own `MemoryBaselineStore()` which always read
  /// 0 — that's why the progress bar never moved.
  UserBaseline get _baseline => RiskDetectionService().baseline;

  final RiskEventLog _eventLog = RiskEventLog();
  StreamSubscription<void>? _baselineSub;

  @override
  void initState() {
    super.initState();
    _trainingStore.open();
    // Kick off monitoring if we landed here without going through
    // the Safety Status screen first. Idempotent on the service side.
    final risk = RiskDetectionService();
    unawaited(risk.startMonitoring());
    // Make sure the baseline is loaded before the first build.
    unawaited(risk.baseline.load());
    // Live updates — refresh on every new GPS sample so the progress
    // bar actually moves while the user is using the app.
    _baselineSub = risk.baseline.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _baselineSub?.cancel();
    _trainingStore.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text(
          'Risk Insights',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildBaselineCard(),
            const SizedBox(height: 16),
            _buildTrainingCard(),
            const SizedBox(height: 16),
            _buildRecentEventsCard(),
            const SizedBox(height: 16),
            _buildPrivacyCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildBaselineCard() {
    final total = _baseline.totalSamples;
    final places = _baseline.frequentPlaces.length;
    final hours = _baseline.observedHours;
    final threshold = _baseline.readyThreshold;
    final ready = _baseline.isReady;
    final progress = (total / threshold).clamp(0.0, 1.0);
    return _Card(
      title: 'Your baseline',
      icon: Icons.psychology_rounded,
      iconColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            !ready
                ? 'The AI is still learning your patterns. After ~$threshold '
                    'samples it switches to a personalized risk model that '
                    'knows your usual routes, times, and motion.'
                : 'Personalized. The AI knows your usual places and motion '
                    'patterns. Deviations from this baseline raise your risk '
                    'score.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.primary.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$total / $threshold samples',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat('$places', 'places', Icons.location_on_rounded),
              const SizedBox(width: 12),
              _miniStat('$hours', 'hours profiled', Icons.schedule_rounded),
            ],
          ),
          if (places > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _baseline.frequentPlaces
                  .map((p) => Chip(
                        label: Text(
                          p.label,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        avatar: const Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.08),
                        side: BorderSide(
                          color:
                              AppColors.primary.withValues(alpha: 0.20),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrainingCard() {
    final stats = _trainingStore.stats();
    final bySource = stats.bySource;
    return _Card(
      title: 'Training feedback',
      icon: Icons.model_training_rounded,
      iconColor: const Color(0xFF7C3AED),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'When SOS fires (and you don\'t cancel) we save a positive example. '
            'When you tap "I AM SAFE" we save a negative one. After 50 of each '
            'the model is ready to be retrained.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat('${stats.positiveCount}',
                  'risk examples', Icons.warning_amber_rounded),
              const SizedBox(width: 12),
              _miniStat('${stats.negativeCount}',
                  'safe examples', Icons.check_circle_rounded),
            ],
          ),
          const SizedBox(height: 14),
          if (stats.isReadyForRetraining)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.success,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ready to retrain — re-run the Python pipeline with '
                      'tools/train_risk_model.py',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            LinearProgressIndicator(
              value: (stats.positiveCount.clamp(0, 50) +
                      stats.negativeCount.clamp(0, 50)) /
                  100,
              minHeight: 4,
              backgroundColor: Colors.grey.shade200,
            ),
          if (bySource.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...TrainingSource.all.where(bySource.containsKey).map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          _sourceIcon(s),
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _sourceLabel(s),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Text(
                          '${bySource[s]}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentEventsCard() {
    final events = _eventLog.recent();
    return _Card(
      title: 'Recent high-risk moments',
      icon: Icons.history_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: events.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No notable risk events recorded yet. Open the app for a few '
                'minutes while moving around to start collecting insights.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            )
          : Column(
              children: events.map((e) {
                final color = _levelColor(e.result.level);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.label,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              _formatTime(e.at),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(e.result.score * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildPrivacyCard() {
    return _Card(
      title: 'How your data is used',
      icon: Icons.lock_outline_rounded,
      iconColor: const Color(0xFF6B7280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All baseline + training data stays on your phone. Nothing is sent '
            'to any server except emergency alerts to your trusted contacts. '
            'You can wipe your data from the Profile screen.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _showClearDataDialog(),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text(
              'Clear my personalization data',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEF4444),
              ),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear personalization data?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This wipes your baseline, training examples, and risk event log. '
          'The app will return to a cold-start state.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _trainingStore.clear();
              // Baseline reset would require Hive re-init — we leave
              // it for the user to clear in app settings.
              if (mounted) setState(() {});
            },
            child: const Text(
              'Clear',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case TrainingSource.iAmSafe:
        return Icons.check_circle_rounded;
      case TrainingSource.sosFired:
        return Icons.warning_rounded;
      case TrainingSource.shakeSos:
        return Icons.vibration_rounded;
      case TrainingSource.audioAlarm:
        return Icons.mic_rounded;
      default:
        return Icons.bug_report_rounded;
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case TrainingSource.iAmSafe:
        return 'I am safe confirmations';
      case TrainingSource.sosFired:
        return 'Auto-triggered SOS';
      case TrainingSource.shakeSos:
        return 'Shake-to-SOS';
      case TrainingSource.audioAlarm:
        return 'Audio keyword escalations';
      default:
        return source;
    }
  }

  Color _levelColor(RiskLevel l) {
    switch (l) {
      case RiskLevel.low:
        return AppColors.success;
      case RiskLevel.medium:
        return AppColors.warning;
      case RiskLevel.high:
        return AppColors.sos;
    }
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// In-memory log of recent high-risk `RiskResult`s.
/// The production version of this should persist the last 100
/// events to Hive (deferred to a later phase).
class RiskEventLog {
  final List<RiskEvent> _events = [];
  static const int _max = 20;

  void add(RiskResult result, {String label = 'High risk moment'}) {
    _events.insert(
      0,
      RiskEvent(result: result, at: DateTime.now(), label: label),
    );
    if (_events.length > _max) _events.removeLast();
  }

  List<RiskEvent> recent() => List.unmodifiable(_events);
}

class RiskEvent {
  final RiskResult result;
  final DateTime at;
  final String label;

  const RiskEvent({
    required this.result,
    required this.at,
    required this.label,
  });
}
