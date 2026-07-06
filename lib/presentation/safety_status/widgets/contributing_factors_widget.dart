// lib/presentation/safety_status/widgets/contributing_factors_widget.dart
//
// Phase 5 — Shows the user *why* the AI scored their risk the way
// it did. Takes a `RiskResult` and renders the top 3 factors by
// contribution, with a small bar for each.

import 'package:flutter/material.dart';
import 'package:tapguard/core/constants/app_colors.dart';
import 'package:tapguard/data/services/risk/decision_engine.dart';

class ContributingFactorsWidget extends StatelessWidget {
  final RiskResult result;
  const ContributingFactorsWidget({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final factors = _extractFactors();
    if (factors.isEmpty) {
      return const SizedBox.shrink();
    }
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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Why this score?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...factors.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FactorRow(factor: f, maxValue: result.score),
              )),
        ],
      ),
    );
  }

  /// Walk the result's `factors` map and rank contributions.
  /// Returns up to 3 factors sorted by contribution.
  List<_Factor> _extractFactors() {
    final f = result.factors;
    final List<_Factor> factors = [];

    // Top-level scores — multiply by the engine weights to get the
    // actual contribution to the final risk score.
    final weights = (f['weights'] as Map?)?.cast<String, dynamic>() ?? {};
    final modelW = (weights['model'] as num?)?.toDouble() ?? 0.45;
    final anomalyW = (weights['anomaly'] as num?)?.toDouble() ?? 0.30;
    final keywordW = (weights['keyword'] as num?)?.toDouble() ?? 0.15;
    final rulesW = (weights['rules'] as num?)?.toDouble() ?? 0.10;

    final modelS = (f['model'] as num?)?.toDouble() ?? 0.0;
    final anomalyS = (f['anomaly'] as num?)?.toDouble() ?? 0.0;
    final keywordS = (f['keyword'] as num?)?.toDouble() ?? 0.0;
    final rulesS = (f['rules'] as num?)?.toDouble() ?? 0.0;

    if (modelS > 0.05) {
      factors.add(_Factor(
        label: 'Motion AI model',
        value: modelS,
        contribution: modelS * modelW,
        color: AppColors.primary,
        icon: Icons.bolt_rounded,
      ));
    }
    if (anomalyS > 0.1) {
      final personalized = f['anomaly_personalized'] == true;
      factors.add(_Factor(
        label: personalized ? 'Off-baseline (vs your routine)' : 'Anomaly',
        value: anomalyS,
        contribution: anomalyS * anomalyW,
        color: const Color(0xFF06B6D4),
        icon: Icons.psychology_alt_rounded,
      ));
    }
    if (keywordS > 0.05) {
      factors.add(_Factor(
        label: 'Voice keyword',
        value: keywordS,
        contribution: keywordS * keywordW,
        color: const Color(0xFFEF4444),
        icon: Icons.mic_rounded,
      ));
    }
    if (rulesS > 0.05) {
      factors.add(_Factor(
        label: 'Hard rules',
        value: rulesS,
        contribution: rulesS * rulesW,
        color: const Color(0xFFF59E0B),
        icon: Icons.shield_moon_rounded,
      ));
    }

    // Surface specific motion signals when they fire
    final motion = (f['motion'] as Map?)?.cast<String, dynamic>() ?? {};
    final motionEntries = <(String, double, IconData, Color)>[
      if ((motion['violent'] as num? ?? 0) > 0.5)
        ('Violent motion', (motion['violent'] as num).toDouble(),
            Icons.warning_rounded, const Color(0xFFEF4444)),
      if ((motion['fast'] as num? ?? 0) > 0.5)
        ('Running / fast movement', (motion['fast'] as num).toDouble(),
            Icons.directions_run_rounded, const Color(0xFFEF4444)),
      if ((motion['jittery'] as num? ?? 0) > 0.5)
        ('Jittery motion', (motion['jittery'] as num).toDouble(),
            Icons.vibration_rounded, const Color(0xFFF59E0B)),
    ];
    for (final m in motionEntries) {
      factors.add(_Factor(
        label: m.$1,
        value: m.$2,
        contribution: m.$2 * 0.10,
        color: m.$4,
        icon: m.$3,
      ));
    }

    // Surface late-night / location
    final ctx = (f['context'] as Map?)?.cast<String, dynamic>() ?? {};
    if ((ctx['lateNight'] as num? ?? 0) > 0.5) {
      final location = (f['location'] as Map?)?.cast<String, dynamic>() ?? {};
      final far = (location['distanceFromHome'] as num? ?? 0) > 5000;
      factors.add(_Factor(
        label: far ? 'Late night, away from home' : 'Late night',
        value: 0.7,
        contribution: 0.10,
        color: const Color(0xFF7C3AED),
        icon: Icons.nightlight_rounded,
      ));
    }

    // Sort by contribution, take top 3
    factors.sort((a, b) => b.contribution.compareTo(a.contribution));
    return factors.take(3).toList();
  }
}

class _Factor {
  final String label;
  final double value;
  final double contribution;
  final Color color;
  final IconData icon;

  const _Factor({
    required this.label,
    required this.value,
    required this.contribution,
    required this.color,
    required this.icon,
  });
}

class _FactorRow extends StatelessWidget {
  final _Factor factor;
  final double maxValue;
  const _FactorRow({required this.factor, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0
        ? 0.0
        : (factor.contribution / maxValue).clamp(0.0, 1.0);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: factor.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(factor.icon, color: factor.color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      factor.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      '+${(factor.contribution * 100).toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: factor.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                  backgroundColor: factor.color.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(factor.color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
