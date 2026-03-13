import 'dart:async';
import 'package:flutter/material.dart';

class ProcessingSimulatorDialog extends StatefulWidget {
  final String title;
  final Duration duration;

  const ProcessingSimulatorDialog({
    super.key,
    required this.title,
    required this.duration,
  });

  @override
  State<ProcessingSimulatorDialog> createState() => _ProcessingSimulatorDialogState();
}

class _ProcessingSimulatorDialogState extends State<ProcessingSimulatorDialog> {
  double _progress = 0.0;
  late Timer _timer;
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final elapsed = DateTime.now().difference(_startTime);
      setState(() {
        _progress = (elapsed.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);
      });

      if (_progress >= 1.0) {
        _timer.cancel();
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: Colors.white.withOpacity(0.1),
            color: const Color(0xFFFF9800),
          ),
          const SizedBox(height: 16),
          Text(
            '${(_progress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
