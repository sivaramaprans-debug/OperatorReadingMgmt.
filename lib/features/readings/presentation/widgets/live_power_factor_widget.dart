import 'package:flutter/material.dart';

/// Shared widget for live Power Factor (PF) appearance box & validation alert.
class LivePowerFactorWidget extends StatelessWidget {
  const LivePowerFactorWidget({
    super.key,
    required this.unitControllers,
    required this.prevValues,
    required this.currentFactors,
  });

  final Map<String, TextEditingController> unitControllers;
  final Map<String, double> prevValues;
  final Map<String, double> currentFactors;

  @override
  Widget build(BuildContext context) {
    final kwhKey = unitControllers.keys.firstWhere(
      (k) => k.toUpperCase() == 'KWH',
      orElse: () => '',
    );
    final kvahKey = unitControllers.keys.firstWhere(
      (k) => k.toUpperCase() == 'KVAH',
      orElse: () => '',
    );
    final pfKey = unitControllers.keys.firstWhere(
      (k) => k.toUpperCase() == 'PF',
      orElse: () => '',
    );

    final kwhCtrl = kwhKey.isNotEmpty ? unitControllers[kwhKey] : null;
    final kvahCtrl = kvahKey.isNotEmpty ? unitControllers[kvahKey] : null;
    final pfCtrl = pfKey.isNotEmpty ? unitControllers[pfKey] : null;

    final Listenable listenable = Listenable.merge([
      if (kwhCtrl != null) kwhCtrl,
      if (kvahCtrl != null) kvahCtrl,
      if (pfCtrl != null) pfCtrl,
    ]);

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        double? calculatedPf;
        double? kwhCons;
        double? kvahCons;

        if (kwhCtrl != null && kvahCtrl != null) {
          final currentKwh = double.tryParse(kwhCtrl.text.trim());
          final currentKvah = double.tryParse(kvahCtrl.text.trim());
          final prevKwh = prevValues[kwhKey];
          final prevKvah = prevValues[kvahKey];

          if (currentKwh != null && currentKvah != null && prevKwh != null && prevKvah != null) {
            final kwhFactor = currentFactors[kwhKey] ?? 1.0;
            final kvahFactor = currentFactors[kvahKey] ?? 1.0;
            final kwhDiff = currentKwh - prevKwh;
            final kvahDiff = currentKvah - prevKvah;
            kwhCons = kwhDiff * kwhFactor;
            kvahCons = kvahDiff * kvahFactor;

            if (kvahCons > 0) {
              calculatedPf = kwhCons / kvahCons;
            }
          }
        }

        double? directPf;
        if (pfCtrl != null) {
          directPf = double.tryParse(pfCtrl.text.trim());
        }

        final activePf = calculatedPf ?? directPf;
        if (activePf == null) return const SizedBox.shrink();

        final isInvalid = activePf > 1.0;

        final bgColor = isInvalid
            ? Colors.red.shade50
            : const Color(0xFFE8F5E9);
        final borderColor = isInvalid ? Colors.red.shade400 : Colors.teal.shade400;
        final textColor = isInvalid ? Colors.red.shade900 : Colors.teal.shade900;
        final icon = isInvalid ? Icons.warning_amber_rounded : Icons.check_circle_rounded;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: isInvalid ? Colors.red.withOpacity(0.1) : Colors.teal.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: textColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Power Factor (PF): ${activePf.toStringAsFixed(3)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isInvalid ? Colors.red.shade200 : Colors.teal.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isInvalid ? 'INVALID (PF > 1.0)' : 'VALID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isInvalid
                    ? '⚠️ Warning: Auto-calculated Power Factor from consumption (${kwhCons?.toStringAsFixed(2)} KWH / ${kvahCons?.toStringAsFixed(2)} KVAH) is greater than 1.0! Power Factor must be ≤ 1.0. Please verify your readings.'
                    : '✓ Calculated from consumption (${kwhCons?.toStringAsFixed(2)} KWH / ${kvahCons?.toStringAsFixed(2)} KVAH). Readings are within normal limits.',
                style: TextStyle(
                  fontSize: 12,
                  color: textColor.withOpacity(0.9),
                  height: 1.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
