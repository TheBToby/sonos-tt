import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';

class SpeakersPanel extends StatefulWidget {
  final double size;
  const SpeakersPanel({super.key, required this.size});

  @override
  State<SpeakersPanel> createState() => _SpeakersPanelState();
}

class _SpeakersPanelState extends State<SpeakersPanel> {
  String? expandedGroup;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final sonos = state.sonos;
    final s = widget.size;

    final multiGroups = sonos.groups.where((g) => g.memberUids.length > 1).toList();

    final soloSpeakers = sonos.speakers.where((sp) {
      return !multiGroups.any((g) => g.memberUids.contains(sp.uid));
    }).toList();

    if (sonos.speakers.isEmpty) {
      return Center(
        child: Text(state.t('speakers.none_found'),
            style: TextStyle(color: c.textDim, fontSize: s * 0.04)),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: s * 0.03, vertical: s * 0.1),
      child: Column(
        children: [
          // Grouped speakers
          ...multiGroups.map((g) {
            final coord = sonos.speakers.firstWhere((sp) => sp.uid == g.coordinatorUid);
            final members = g.memberUids.where((uid) => uid != g.coordinatorUid).map((uid) {
              return sonos.speakers.firstWhere((sp) => sp.uid == uid);
            }).toList();
            final isExpanded = expandedGroup == g.coordinatorUid;

            return SpeakerCard(
              size: s,
              name: coord.name,
              volume: coord.volume,
              isActive: coord.uid == sonos.activeSpeakerUid,
              isCoordinator: true,
              suffix: '+${members.length}',
              expanded: isExpanded,
              onTap: () => state.setActiveSpeaker(coord.uid),
              onExpand: () => setState(() => expandedGroup = isExpanded ? null : g.coordinatorUid),
              child: isExpanded
                  ? Column(
                      children: members.map((m) {
                        return SpeakerCard(
                          size: s,
                          name: m.name,
                          volume: m.volume,
                          isActive: m.uid == sonos.activeSpeakerUid,
                          isCoordinator: false,
                          onTap: () => state.setActiveSpeaker(m.uid),
                        );
                      }).toList(),
                    )
                  : null,
            );
          }),
          // Solo speakers
          ...soloSpeakers.map((sp) => SpeakerCard(
                size: s,
                name: sp.name,
                volume: sp.volume,
                isActive: sp.uid == sonos.activeSpeakerUid,
                isCoordinator: true,
                onTap: () => state.setActiveSpeaker(sp.uid),
              )),
        ],
      ),
    );
  }
}

class SpeakerCard extends StatelessWidget {
  final double size;
  final String name;
  final int volume;
  final bool isActive;
  final bool isCoordinator;
  final String? suffix;
  final VoidCallback onTap;
  final VoidCallback? onExpand;
  final Widget? child;
  final bool expanded;

  const SpeakerCard({
    super.key,
    required this.size,
    required this.name,
    required this.volume,
    required this.isActive,
    required this.isCoordinator,
    this.suffix,
    required this.onTap,
    this.onExpand,
    this.child,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: isActive ? Border.all(color: c.accent, width: 2) : null,
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size * 0.02, vertical: size * 0.017),
                child: Row(
                  children: [
                    // Speaker icon — coordinator vs member
                    Icon(
                      isCoordinator ? Icons.speaker : Icons.speaker_group_outlined,
                      size: size * 0.032,
                      color: isCoordinator ? c.accent : c.textDim,
                    ),
                    SizedBox(width: size * 0.017),
                    Expanded(
                      child: Text(
                        '$name${suffix != null ? ' $suffix' : ''}',
                        style: TextStyle(
                          color: c.text,
                          fontSize: size * 0.045,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Volume with Material icon
                    Icon(Icons.volume_up, size: size * 0.026, color: c.textDim),
                    SizedBox(width: size * 0.006),
                    Text('$volume', style: TextStyle(color: c.textDim, fontSize: size * 0.038)),
                    if (onExpand != null) ...[
                      SizedBox(width: size * 0.012),
                      GestureDetector(
                        onTap: onExpand,
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: size * 0.032,
                          color: c.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}
