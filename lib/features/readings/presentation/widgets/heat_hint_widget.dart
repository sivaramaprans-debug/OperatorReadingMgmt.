import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifiers/heat_validation_provider.dart';

/// Standalone widget for real-time heat number validation hint and crucible switchover actions.
class HeatHintWidget extends ConsumerStatefulWidget {
  const HeatHintWidget({
    super.key,
    required this.deviceId,
    required this.heatNumberController,
    this.isCrucibleSwitchover = false,
    this.onEnableSwitchover,
  });

  final String deviceId;
  final TextEditingController heatNumberController;
  final bool isCrucibleSwitchover;
  final VoidCallback? onEnableSwitchover;

  @override
  ConsumerState<HeatHintWidget> createState() => _HeatHintWidgetState();
}

class _HeatHintWidgetState extends ConsumerState<HeatHintWidget> {
  String _lastHeatText = '';

  @override
  void initState() {
    super.initState();
    _lastHeatText = widget.heatNumberController.text.trim();
    widget.heatNumberController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant HeatHintWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heatNumberController != widget.heatNumberController) {
      oldWidget.heatNumberController.removeListener(_onTextChanged);
      widget.heatNumberController.addListener(_onTextChanged);
      _lastHeatText = widget.heatNumberController.text.trim();
    }
  }

  void _onTextChanged() {
    final text = widget.heatNumberController.text.trim();
    if (text != _lastHeatText) {
      setState(() => _lastHeatText = text);
    }
  }

  @override
  void dispose() {
    widget.heatNumberController.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heatText = _lastHeatText;

    final validationAsync = ref.watch(heatValidationProvider((
      deviceId: widget.deviceId,
      heatNumber: heatText,
      isCrucibleSwitchover: widget.isCrucibleSwitchover,
    )));

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12),
      child: validationAsync.when(
        loading: () => const SizedBox(
          height: 2,
          child: LinearProgressIndicator(),
        ),
        error: (_, __) => const SizedBox.shrink(),
        data: (result) {
          if (heatText.isEmpty) {
            final nextNum = result.expectedNext ?? 1;
            return Text(
              widget.isCrucibleSwitchover
                  ? 'Crucible Switchover active: Enter any heat number for the alternate crucible.'
                  : 'Enter heat number. Expected next: Heat #$nextNum (or #1 to start a new cycle).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: widget.isCrucibleSwitchover ? Colors.orange.shade800 : theme.colorScheme.onSurfaceVariant,
                fontWeight: widget.isCrucibleSwitchover ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }

          if (result.isValid) {
            final isRf = heatText.toUpperCase() == 'R/F' || heatText.toUpperCase() == 'RF';
            final validMsg = widget.isCrucibleSwitchover
                ? 'Crucible Switchover: Heat #$heatText accepted ✓'
                : (isRf
                    ? 'Re-furnace (R/F) selected ✓ Next regular heat: Heat #${result.expectedNext ?? 1}'
                    : 'Heat #$heatText is valid ✓');
            return Row(
              children: [
                Icon(
                  widget.isCrucibleSwitchover ? Icons.swap_horiz_rounded : Icons.check_circle_outline,
                  size: 14,
                  color: widget.isCrucibleSwitchover ? Colors.orange.shade800 : theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    validMsg,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.isCrucibleSwitchover ? Colors.orange.shade800 : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 14, color: theme.colorScheme.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      result.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (result.canSwitchover && !widget.isCrucibleSwitchover && widget.onEnableSwitchover != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: widget.onEnableSwitchover,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text(
                          'Crucible breakdown / switch? Tap to accept Heat #$heatText',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
