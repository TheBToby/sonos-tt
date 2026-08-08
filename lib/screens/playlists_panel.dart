import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';

class PlaylistsPanel extends StatefulWidget {
  final double size;
  const PlaylistsPanel({super.key, required this.size});

  @override
  State<PlaylistsPanel> createState() => _PlaylistsPanelState();
}

class _PlaylistsPanelState extends State<PlaylistsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchPlaylists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final s = widget.size;
    final playlists = state.sonos.activePlaylists;
    final queue = state.sonos.activeQueue;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: s * 0.02, vertical: s * 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (playlists.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(s * 0.04),
                child: Text(state.t('playlists.empty'),
                    style: TextStyle(color: c.textDim, fontSize: s * 0.028)),
              ),
            )
          else
            ...playlists.map((pl) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: GestureDetector(
                    onTap: () => state.playPlaylist(pl.title),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.queue_music, size: s * 0.03, color: c.accent),
                          SizedBox(width: s * 0.015),
                          Expanded(
                            child: Text(
                              pl.title,
                              style: TextStyle(
                                color: c.text,
                                fontSize: s * 0.026,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
          if (queue.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(top: s * 0.04, bottom: s * 0.02, left: 4),
              child: Text(
                state.t('playlists.queue').toUpperCase(),
                style: TextStyle(
                  color: c.textDim,
                  fontSize: s * 0.022,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
            ...queue.take(6).toList().asMap().entries.map((e) {
              final i = e.key;
              final q = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: i == 0 ? Border(left: BorderSide(color: c.accent, width: 3)) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: s * 0.024,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis),
                      if (q.artist.isNotEmpty)
                        Text(q.artist, style: TextStyle(color: c.textDim, fontSize: s * 0.02)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
