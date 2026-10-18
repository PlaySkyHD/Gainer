import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../training/training_format.dart';
import 'cardio_format.dart';
import 'cardio_session_controller.dart';

/// Kompakte Karte oben im Tagebuch: „Cardio läuft · 12:34 · 131 bpm“. Tippen
/// öffnet die Live-Ansicht. Ohne laufende Einheit bleibt sie leer.
class CardioRunningCard extends StatefulWidget {
  const CardioRunningCard({
    required this.session,
    required this.onOpen,
    super.key,
  });

  final CardioSessionController session;
  final VoidCallback onOpen;

  @override
  State<CardioRunningCard> createState() => _CardioRunningCardState();
}

class _CardioRunningCardState extends State<CardioRunningCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.isRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        if (!session.isRunning) return const SizedBox.shrink();
        final colors = GainerDesign.colorsOf(context);
        final bpm = session.liveBpm;
        final text = [
          'Cardio läuft',
          formatElapsed(session.elapsed),
          if (bpm != null) formatBpm(bpm),
        ].join(' · ');
        return Padding(
          padding: const EdgeInsets.only(bottom: GainerSpacing.m),
          child: Semantics(
            button: true,
            label: text,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('cardio-running-card'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              child: GainerCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: GainerSpacing.m,
                  vertical: GainerSpacing.s,
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.heart_fill,
                      size: 20,
                      color: colors.destructive,
                    ),
                    const SizedBox(width: GainerSpacing.s),
                    Expanded(
                      child: Text(
                        text,
                        style: GainerTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_forward,
                      size: 16,
                      color: colors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
