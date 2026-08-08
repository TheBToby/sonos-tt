import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../models/app_config.dart';

class UsersPanel extends StatelessWidget {
  final double size;
  const UsersPanel({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final s = size;
    final accounts = state.config.spotify.accounts;
    final defaultId = state.config.spotify.defaultAccount;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: s * 0.03, vertical: s * 0.1),
      child: Column(
        children: accounts.map((acc) {
          final isCurrent = acc.id == defaultId;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: GestureDetector(
              onTap: () {
                if (!isCurrent) {
                  final newCfg = state.config.copyWith(
                    spotify: SpotifyConfig(
                      accounts: accounts,
                      defaultAccount: acc.id,
                    ),
                  );
                  state.updateConfig(newCfg);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: isCurrent ? Border.all(color: c.accent, width: 2) : null,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _parseColor(acc.color),
                      child: Text(
                        acc.label.isNotEmpty ? acc.label[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: Colors.white, fontSize: s * 0.024, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(acc.label,
                              style: TextStyle(
                                color: c.text,
                                fontSize: s * 0.028,
                                fontWeight: FontWeight.w600,
                              )),
                          if (isCurrent)
                            Text(state.t('users.current'),
                                style: TextStyle(color: c.accent, fontSize: s * 0.02)),
                        ],
                      ),
                    ),
                    if (!isCurrent) Icon(Icons.chevron_right, size: s * 0.035, color: c.textDim),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF4fc3f7);
    }
  }
}
