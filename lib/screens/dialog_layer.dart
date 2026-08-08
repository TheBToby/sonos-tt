import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/bar_panel.dart';
import 'playlists_panel.dart';
import 'settings_panel.dart';
import 'speakers_panel.dart';
import 'users_panel.dart';

class DialogLayer extends StatelessWidget {
  const DialogLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final view = state.view;
    if (view == AppView.turntable || view == AppView.screensaver) {
      return const SizedBox.shrink();
    }

    final title = _titleForView(state, view);
    final screenSize = MediaQuery.of(context).size.shortestSide;
    // Content area is 68% of screen width — pass this as the panel size so
    // panels scale their padding/fonts to the actual available space.
    final contentSize = screenSize * 0.68;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: BarPanel(
        key: ValueKey(view),
        title: title,
        onClose: () => state.setView(AppView.turntable),
        child: _buildContent(view, contentSize),
      ),
    );
  }

  String _titleForView(AppState state, AppView view) {
    switch (view) {
      case AppView.speakers:
        return state.t('speakers.title');
      case AppView.playlists:
        return state.t('playlists.title');
      case AppView.users:
        return state.t('users.title');
      case AppView.settings:
        return state.t('settings.title');
      default:
        return '';
    }
  }

  Widget _buildContent(AppView view, double size) {
    switch (view) {
      case AppView.speakers:
        return SpeakersPanel(size: size);
      case AppView.playlists:
        return PlaylistsPanel(size: size);
      case AppView.users:
        return UsersPanel(size: size);
      case AppView.settings:
        return SettingsPanel(size: size);
      default:
        return const SizedBox.shrink();
    }
  }
}
