// lib/presentation/safety_status/widgets/personalization_status_chip.dart
//
// Phase 5 — Small status chip that summarises the AI engine state.
// Used in the Safety Status screen header and the Profile screen
// personalization section.

import 'package:flutter/material.dart';
import 'package:tapguard/core/constants/app_colors.dart';

enum AiEngineStatus {
  /// Model is loaded and used.
  model,

  /// Model is not loaded (no TFLite file), falling back to the
  /// hand-tuned heuristic. Risk is still scored, just less accurate.
  heuristic,

  /// Personalised — the user baseline is built and the engine
  /// uses the user's own motion/location patterns.
  personalized,

  /// Cold start — the user baseline is still building (fewer than
  /// the ready threshold samples have been observed).
  coldStart,
}

class PersonalizationStatusChip extends StatelessWidget {
  final AiEngineStatus status;

  /// Number of feedback examples (I-am-safe / SOS-fired events)
  /// queued for the next model retraining round.
  final int trainingExamples;

  /// Number of baseline learning samples (GPS observations) collected
  /// so far. When this crosses [learningThreshold] the engine
  /// transitions out of [AiEngineStatus.coldStart].
  final int learningSamples;

  /// Total samples required for the baseline to be considered ready.
  /// Defaults to 25 to keep in sync with `UserBaseline.kReadyThreshold`.
  final int learningThreshold;

  const PersonalizationStatusChip({
    super.key,
    required this.status,
    this.trainingExamples = 0,
    this.learningSamples = 0,
    this.learningThreshold = 25,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _spec(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: spec.color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, color: spec.color, size: 12),
          const SizedBox(width: 6),
          Text(
            spec.label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: spec.color,
              letterSpacing: 0.4,
            ),
          ),
          // Live learning progress: "12 / 25" pill while the cold-start
          // baseline is still being seeded. Hidden once personalized.
          if (status == AiEngineStatus.coldStart &&
              learningThreshold > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: spec.color.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$learningSamples/$learningThreshold',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: spec.color,
                ),
              ),
            ),
          ] else if (trainingExamples > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: spec.color.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$trainingExamples',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: spec.color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _StatusSpec _spec(AiEngineStatus s) {
    switch (s) {
      case AiEngineStatus.model:
        return const _StatusSpec(
          label: 'AI MODEL',
          color: AppColors.primary,
          icon: Icons.bolt_rounded,
        );
      case AiEngineStatus.heuristic:
        return const _StatusSpec(
          label: 'HEURISTIC',
          color: Color(0xFF6B7280),
          icon: Icons.tune_rounded,
        );
      case AiEngineStatus.personalized:
        return const _StatusSpec(
          label: 'PERSONALIZED',
          color: AppColors.success,
          icon: Icons.psychology_rounded,
        );
      case AiEngineStatus.coldStart:
        return const _StatusSpec(
          label: 'LEARNING',
          color: Color(0xFFF59E0B),
          icon: Icons.hourglass_top_rounded,
        );
    }
  }
}

class _StatusSpec {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusSpec({
    required this.label,
    required this.color,
    required this.icon,
  });
}
