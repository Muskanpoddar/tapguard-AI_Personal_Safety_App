// lib/presentation/safety_status/safety_status_screen.dart
//
// Safety Status Confirmation Screen (Phase 5 — UI transparency).
// ─────────────────────────────────
// Features:
//   - "I AM SAFE" confirmation button
//   - Current risk level display (from RiskDetectionService)
//   - Top-3 contributing factors ("Why this score?")
//   - AI engine status chip (model / heuristic / personalized / cold-start)
//   - Live location display
//   - Training-data feedback loop status
//   - Safety tips
//
// Flow:
//   User opens → sees risk + factors + engine state + "I AM SAFE" button
//   Taps "I AM SAFE" → sends safety confirmation, captures a negative
//                       training example (Phase 4) → risk level resets
//   Risk detection service records interaction → resets inactivity timer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/risk_detection_service.dart';
import 'widgets/contributing_factors_widget.dart';
import 'widgets/personalization_status_chip.dart';

class SafetyStatusScreen extends StatefulWidget {
  const SafetyStatusScreen({super.key});

  @override
  State<SafetyStatusScreen> createState() => _SafetyStatusScreenState();
}

class _SafetyStatusScreenState extends State<SafetyStatusScreen>
    with SingleTickerProviderStateMixin {
  final _risk = RiskDetectionService();
  StreamSubscription<RiskResult>? _riskSub;

  RiskLevel _riskLevel = RiskLevel.low;
  double _riskScore = 0.0;
  RiskResult? _latest;
  Position? _lastPos;
  bool _confirming = false;
  bool _confirmed = false;
  bool _loading = true;
  int _trainingExamples = 0;
  int _learningSamples = 0;
  int _learningThreshold = 25;
  bool _baselineReady = false;
  bool _usedModel = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseScale = CurvedAnimation(
      parent: _pulseCtrl,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 1.05));
    _risk.startMonitoring();
    _loadLocation();
    _listenRisk();
  }

  Future<void> _loadLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _lastPos = pos;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _listenRisk() {
    _riskSub = _risk.riskStream.listen((result) {
      if (!mounted) return;
      setState(() {
        _riskLevel = result.level;
        _riskScore = result.score;
        _latest = result;
        _trainingExamples = _risk.trainingDataStore.count;
        _learningSamples = _risk.baseline.totalSamples;
        _learningThreshold = _risk.baseline.readyThreshold;
        _baselineReady = result.factors['baseline_ready'] == true;
        _usedModel = result.factors['used_model'] == true;
      });
      if (_confirmed && result.level == RiskLevel.low) {
        setState(() => _confirmed = false);
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _riskSub?.cancel();
    _risk.stopMonitoring();
    super.dispose();
  }

  Future<void> _onSafeConfirm() async {
    if (_confirming || _confirmed) return;
    setState(() => _confirming = true);
    HapticFeedback.heavyImpact();

    await _risk.sendSafetyConfirmation();

    if (!mounted) return;
    setState(() {
      _confirmed = true;
      _confirming = false;
    });
  }

  Color get _riskColor {
    switch (_riskLevel) {
      case RiskLevel.low:
        return AppColors.success;
      case RiskLevel.medium:
        return AppColors.warning;
      case RiskLevel.high:
        return AppColors.sos;
    }
  }

  String get _riskLabel {
    switch (_riskLevel) {
      case RiskLevel.low:
        return 'LOW RISK';
      case RiskLevel.medium:
        return 'MEDIUM RISK';
      case RiskLevel.high:
        return 'HIGH RISK';
    }
  }

  AiEngineStatus get _engineStatus {
    if (_usedModel) return AiEngineStatus.model;
    if (_baselineReady) return AiEngineStatus.personalized;
    return AiEngineStatus.coldStart;
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
          'Safety Status',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        actions: [
          if (_latest != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: PersonalizationStatusChip(
                  status: _engineStatus,
                  trainingExamples: _trainingExamples,
                  learningSamples: _learningSamples,
                  learningThreshold: _learningThreshold,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildRiskCard(),
              const SizedBox(height: 16),
              if (_latest != null) ...[
                ContributingFactorsWidget(result: _latest!),
                const SizedBox(height: 16),
              ],
              _buildLocationCard(),
              const SizedBox(height: 16),
              _buildSafeButton(),
              const SizedBox(height: 12),
              _buildInsightsButton(),
              const SizedBox(height: 12),
              _buildTipsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRiskCard() {
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
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _riskColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.security_rounded,
                  color: _riskColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Risk Level',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _riskLabel,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _riskColor,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, _) => Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _riskColor.withValues(
                      alpha: 0.5 + _pulseCtrl.value * 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _riskScore.clamp(0.0, 1.0),
              backgroundColor: _riskColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(_riskColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Score: ${(_riskScore * 100).toStringAsFixed(0)} / 100  •  '
            'Medium ≥ 40  •  High ≥ 70',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
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
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Location',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _loading
                      ? 'Getting location…'
                      : _lastPos != null
                          ? '${_lastPos!.latitude.toStringAsFixed(5)}, ${_lastPos!.longitude.toStringAsFixed(5)}'
                          : 'Location unavailable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          if (!_loading && _lastPos != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSafeButton() {
    return GestureDetector(
      onTap: _confirmed ? null : _onSafeConfirm,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, child) => Transform.scale(
          scale: _confirmed ? 1.0 : _pulseScale.value,
          child: child,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _confirmed
                  ? [AppColors.success, AppColors.success.withValues(alpha: 0.8)]
                  : [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (_confirmed ? AppColors.success : AppColors.primary)
                    .withValues(alpha: 0.40),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _confirmed
                      ? Icons.check_circle_rounded
                      : Icons.shield_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _confirmed ? '✓ Confirmed — You are Safe!' : 'I AM SAFE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: _confirmed ? 16 : 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.riskInsights),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.insights_rounded,
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
                    'Risk Insights',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    'See recent deviations from your routine',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCCCCCC),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsCard() {
    final tips = [
      {
        'icon': Icons.nightlight_rounded,
        'text': 'Stay in well-lit areas when walking at night'
      },
      {
        'icon': Icons.share_location_rounded,
        'text': 'Keep your location sharing active during travel'
      },
      {
        'icon': Icons.people_rounded,
        'text': 'Keep trusted contacts informed of your ETA'
      },
    ];

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
          const Text(
            'Safety Tips',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          ...tips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(tip['icon'] as IconData,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tip['text'] as String,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
