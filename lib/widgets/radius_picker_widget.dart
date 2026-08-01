import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RadiusPickerWidget extends StatefulWidget {
  final double initialRadius;
  final ValueChanged<double> onChanged;
  final Color activeColor;

  const RadiusPickerWidget({
    super.key,
    this.initialRadius = 150.0,
    required this.onChanged,
    this.activeColor = const Color(0xFF6C63FF),
  });

  @override
  State<RadiusPickerWidget> createState() => _RadiusPickerWidgetState();
}

class _RadiusPickerWidgetState extends State<RadiusPickerWidget> {
  late double _radius;
  late TextEditingController _textController;
  static const double _minRadius = 25.0;
  static const double _maxRadius = 2000.0;
  static const double _step = 25.0;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius.clamp(_minRadius, _maxRadius);
    _textController = TextEditingController(text: _radius.toInt().toString());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _updateRadius(double newValue) {
    final clamped = (newValue / _step).round() * _step;
    final finalValue = clamped.clamp(_minRadius, _maxRadius);
    setState(() {
      _radius = finalValue;
      _textController.text = finalValue.toInt().toString();
    });
    widget.onChanged(finalValue);
  }

  void _onTextSubmitted(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < _minRadius) {
      _textController.text = _minRadius.toInt().toString();
      _updateRadius(_minRadius);
    } else if (parsed > _maxRadius) {
      _textController.text = _maxRadius.toInt().toString();
      _updateRadius(_maxRadius);
    } else {
      _updateRadius(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Geofence Radius',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              width: 100,
              height: 36,
              child: TextField(
                controller: _textController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  color: widget.activeColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  suffixText: 'm',
                  suffixStyle: TextStyle(
                    color: widget.activeColor.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                  fillColor: const Color(0xFF0F0F1A),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF22223C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF22223C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.activeColor),
                  ),
                ),
                onSubmitted: _onTextSubmitted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${_minRadius.toInt()}m',
              style: const TextStyle(color: Color(0xFFA0A0C0), fontSize: 11),
            ),
            Expanded(
              child: Slider(
                value: _radius,
                min: _minRadius,
                max: _maxRadius,
                divisions: ((_maxRadius - _minRadius) / _step).round(),
                activeColor: widget.activeColor,
                inactiveColor: const Color(0xFF22223C),
                onChanged: _updateRadius,
              ),
            ),
            Text(
              '${_maxRadius.toInt()}m',
              style: const TextStyle(color: Color(0xFFA0A0C0), fontSize: 11),
            ),
          ],
        ),
        Center(
          child: Text(
            '${_radius.toInt()} meters',
            style: TextStyle(
              color: widget.activeColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}