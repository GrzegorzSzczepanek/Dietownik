import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/theme.dart';
import '../speech_helper.dart';

/// Small "speak now" sheet that returns the recognised sentence (or null).
Future<String?> showDictation(BuildContext context, {String hint = 'Słucham…'}) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _Dictation(hint),
    );

class _Dictation extends StatefulWidget {
  const _Dictation(this.hint);
  final String hint;
  @override
  State<_Dictation> createState() => _DictationState();
}

class _DictationState extends State<_Dictation> {
  final _stt = SpeechToText();
  String _heard = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _error = null; _heard = ''; });
    final ok = await _stt.initialize(onError: (e) {
      if (!mounted) return;
      if (_heard.trim().isNotEmpty) {
        Navigator.pop(context, _heard);
      } else {
        _stt.cancel();
        setState(() => _error = speechErrorText(e.errorMsg));
      }
    });
    if (!ok) {
      if (mounted) setState(() => _error = speechUnavailableText);
      return;
    }
    final locale = await pickPolishLocale(_stt);
    await _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult && _heard.trim().isNotEmpty) Navigator.pop(context, _heard);
      },
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () async {
              if (_error != null) {
                await _start();
                return;
              }
              await _stt.stop();
              if (_heard.trim().isNotEmpty && mounted) Navigator.pop(context, _heard);
            },
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
              child: Icon(Icons.mic, color: AppColors.onAccent, size: 44),
            ),
          ),
          const SizedBox(height: 14),
          Text(_heard.isEmpty ? widget.hint : _heard,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: AppColors.amber))),
        ]),
      );
}
