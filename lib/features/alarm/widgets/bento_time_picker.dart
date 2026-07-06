import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/bento_theme.dart';

/// Selector de hora inline estilo rueda (12h con AM/PM).
/// No abre diálogos: el usuario desliza hora y minutos directamente.
class BentoTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onChanged;

  const BentoTimePicker({
    super.key,
    required this.initialTime,
    required this.onChanged,
  });

  @override
  State<BentoTimePicker> createState() => _BentoTimePickerState();
}

class _BentoTimePickerState extends State<BentoTimePicker> {
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  late int _hour12; // 1..12
  late int _minute; // 0..59
  late bool _isPm;

  static const double _itemExtent = 56;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTime;
    _hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    _minute = t.minute;
    _isPm = t.period == DayPeriod.pm;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final hour24 = _isPm
        ? (_hour12 == 12 ? 12 : _hour12 + 12)
        : (_hour12 == 12 ? 0 : _hour12);
    widget.onChanged(TimeOfDay(hour: hour24, minute: _minute));
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) labelOf,
    required ValueChanged<int> onSelected,
  }) {
    return SizedBox(
      width: 88,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _itemExtent,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.004,
        diameterRatio: 1.6,
        overAndUnderCenterOpacity: 0.25,
        onSelectedItemChanged: (i) {
          HapticFeedback.selectionClick();
          onSelected(i);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(itemCount, (i) {
            return Center(
              child: Text(
                labelOf(i),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: BentoTheme.textPrimary,
                  letterSpacing: 1,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _amPmButton(String label, bool pm) {
    final active = _isPm == pm;
    return GestureDetector(
      onTap: () {
        if (_isPm != pm) {
          HapticFeedback.selectionClick();
          setState(() => _isPm = pm);
          _notify();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? BentoTheme.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? BentoTheme.primaryDark : BentoTheme.borderMuted,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: active ? Colors.white : BentoTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Banda de selección central
          Container(
            height: _itemExtent,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: BentoTheme.bgLight,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _wheel(
                controller: _hourCtrl,
                itemCount: 12,
                labelOf: (i) => '${i + 1}',
                onSelected: (i) {
                  _hour12 = i + 1;
                  _notify();
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: BentoTheme.textPrimary,
                  ),
                ),
              ),
              _wheel(
                controller: _minuteCtrl,
                itemCount: 60,
                labelOf: (i) => i.toString().padLeft(2, '0'),
                onSelected: (i) {
                  _minute = i;
                  _notify();
                },
              ),
              const SizedBox(width: 20),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _amPmButton('AM', false),
                  const SizedBox(height: 8),
                  _amPmButton('PM', true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
