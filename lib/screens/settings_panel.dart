import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../models/app_config.dart';

class SettingsPanel extends StatefulWidget {
  final double size;
  const SettingsPanel({super.key, required this.size});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late TextEditingController _urlController;
  late String _theme;
  late String _language;
  late bool _ssEnabled;
  late double _ssTimeout;
  late String _ssMode;
  late double _ssBrightness;
  late bool _hwDimming;
  late double _spinDuration;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().config;
    _urlController = TextEditingController(text: cfg.socoApi.baseUrl);
    _theme = cfg.ui.theme;
    _language = cfg.ui.language;
    _ssEnabled = cfg.ui.screensaver.enabled;
    _ssTimeout = cfg.ui.screensaver.timeout.toDouble();
    _ssMode = cfg.ui.screensaver.mode;
    _ssBrightness = cfg.ui.screensaver.brightness;
    _hwDimming = cfg.ui.screensaver.hardwareDimming;
    _spinDuration = cfg.ui.turntable.spinDuration.toDouble();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final s = widget.size;
    final conn = state.connection;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: s * 0.025, vertical: s * 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // API Status
          _sectionTitle(c, s, state.t('settings.api')),
          _settingRow(
              c,
              s,
              state.t('settings.api.baseUrl'),
              TextField(
                controller: _urlController,
                style: TextStyle(color: c.text, fontSize: s * 0.024),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              )),
          _settingRow(
              c,
              s,
              state.t('settings.api.status'),
              Text(
                conn.mock
                    ? state.t('connection.mock_title')
                    : conn.connected
                        ? state.t('settings.api.status.connected')
                        : state.t('settings.api.status.disconnected'),
                style: TextStyle(
                  color: conn.connected ? c.success : c.danger,
                  fontSize: s * 0.026,
                ),
              )),
          if (conn.mock)
            Padding(
              padding: EdgeInsets.only(bottom: s * 0.02),
              child: Row(
                children: [
                  Expanded(
                    child: Text(state.t('connection.mock_text'),
                        style: TextStyle(color: c.textDim, fontSize: s * 0.02)),
                  ),
                  GestureDetector(
                    onTap: () {
                      state.api.retryRealConnection();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: s * 0.02, vertical: s * 0.01),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, size: s * 0.024, color: c.accent),
                          SizedBox(width: s * 0.008),
                          Text(state.t('connection.retry'),
                              style: TextStyle(color: c.accent, fontSize: s * 0.022)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _divider(c, s),
          // Theme
          _sectionTitle(c, s, state.t('settings.theme')),
          _segmentedPicker(
              c,
              s,
              [
                const SegOption('auto', 'System'),
                const SegOption('dark', 'Dark'),
                const SegOption('light', 'Light'),
              ],
              _theme,
              (v) => setState(() => _theme = v)),
          _divider(c, s),
          // Language
          _sectionTitle(c, s, state.t('settings.language')),
          _segmentedPicker(
              c,
              s,
              [
                const SegOption('de', 'Deutsch'),
                const SegOption('en', 'English'),
              ],
              _language,
              (v) => setState(() => _language = v)),
          _divider(c, s),
          // Screensaver
          _sectionTitle(c, s, state.t('settings.screensaver')),
          _switchRow(c, s, state.t('settings.screensaver.enabled'), _ssEnabled,
              (v) => setState(() => _ssEnabled = v)),
          _sliderRow(c, s, state.t('settings.screensaver.timeout'), _ssTimeout, 5.0, 120.0,
              (v) => setState(() => _ssTimeout = v),
              suffix: 's'),
          _segmentedPicker(
              c,
              s,
              [
                const SegOption('analog', 'Analog'),
                const SegOption('digital', 'Digital'),
              ],
              _ssMode,
              (v) => setState(() => _ssMode = v)),
          _sliderRow(c, s, state.t('settings.screensaver.brightness'), _ssBrightness, 0.05, 1.0,
              (v) => setState(() => _ssBrightness = v)),
          _switchRow(c, s, state.t('settings.screensaver.hardware_dimming'), _hwDimming,
              (v) => setState(() => _hwDimming = v)),
          _divider(c, s),
          // Turntable
          _sectionTitle(c, s, state.t('settings.turntable')),
          _sliderRow(c, s, state.t('settings.turntable.spin'), _spinDuration, 2.0, 30.0,
              (v) => setState(() => _spinDuration = v),
              suffix: 's'),
          const SizedBox(height: 20),
          // Buttons with Material icons — proportioned for readability and touch target.
          // FittedBox auto-scales text to fit, preventing overflow with longer
          // translated strings (e.g. German "auf Standard zurücksetzen").
          Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => state.resetConfig(),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s * 0.025),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh, size: s * 0.034, color: c.textDim),
                        SizedBox(width: s * 0.014),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(state.t('settings.reset'),
                                style: TextStyle(color: c.textDim, fontSize: s * 0.026)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: s * 0.015),
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s * 0.025),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, size: s * 0.034, color: c.bg),
                        SizedBox(width: s * 0.014),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(state.t('settings.save'),
                                style: TextStyle(
                                    color: c.bg, fontSize: s * 0.03, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _save() {
    final state = context.read<AppState>();
    state.updateConfig(AppConfig(
      socoApi: state.config.socoApi.copyWith(
        baseUrl: _urlController.text.trim(),
      ),
      ui: UiConfig(
        language: _language,
        theme: _theme,
        screensaver: ScreensaverConfig(
          enabled: _ssEnabled,
          timeout: _ssTimeout.round(),
          mode: _ssMode,
          brightness: _ssBrightness,
          hardwareDimming: _hwDimming,
        ),
        turntable: TurntableConfig(
          spinDuration: _spinDuration.round(),
        ),
      ),
      spotify: state.config.spotify,
    ));
    state.setView(AppView.turntable);
  }

  Widget _sectionTitle(SonosColors c, double s, String title) => Padding(
        padding: EdgeInsets.only(bottom: s * 0.015),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: c.accent,
            fontSize: s * 0.032,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _divider(SonosColors c, double s) => Padding(
        padding: EdgeInsets.symmetric(vertical: s * 0.015),
        child: Container(height: 1, color: c.glassBorder),
      );

  Widget _settingRow(SonosColors c, double s, String label, Widget child) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.008),
      child: Row(
        children: [
          SizedBox(
            width: s * 0.24,
            child: Text(label, style: TextStyle(color: c.textDim, fontSize: s * 0.026)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _switchRow(
      SonosColors c, double s, String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.008),
      child: Row(
        children: [
          SizedBox(
            width: s * 0.24,
            child: Text(label, style: TextStyle(color: c.textDim, fontSize: s * 0.026)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: c.accent,
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(SonosColors c, double s, String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {String? suffix}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.006),
      child: Row(
        children: [
          SizedBox(
            width: s * 0.24,
            child: Text(label, style: TextStyle(color: c.textDim, fontSize: s * 0.026)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              activeColor: c.accent,
              label: '${value.round()}${suffix ?? ''}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedPicker(SonosColors c, double s, List<SegOption> options, String current,
      ValueChanged<String> onSelected) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.008),
      child: Row(
        children: options.map((opt) {
          final active = opt.value == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(opt.value),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: EdgeInsets.symmetric(vertical: s * 0.014),
                decoration: BoxDecoration(
                  color: active ? c.accent : c.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(opt.label,
                      style: TextStyle(
                        color: active ? c.bg : c.textDim,
                        fontSize: s * 0.024,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      )),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegOption {
  final String value, label;
  const SegOption(this.value, this.label);
}
