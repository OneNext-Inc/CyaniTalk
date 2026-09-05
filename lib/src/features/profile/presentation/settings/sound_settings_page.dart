import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Nyachi/src/core/services/audio_engine.dart';
import 'package:Nyachi/src/core/theme/color_constants.dart';
import 'package:Nyachi/src/core/widgets/settings_widgets.dart';
import 'package:Nyachi/src/core/widgets/sound_picker.dart';
import 'package:Nyachi/src/features/profile/application/sound_settings_provider.dart';
import 'package:Nyachi/src/shared/widgets/cyani_loading_indicator.dart';
import 'package:Nyachi/src/shared/widgets/toast_helper.dart';
import 'package:Nyachi/src/shared/widgets/error_state.dart';

/// 声音插槽配置
class _SoundSlotConfig {
  final String id;
  final IconData icon;
  final Color iconColor;
  final String labelKey;
  final String descKey;
  final String Function(SoundSettings) getter;
  final void Function(SoundSettingsNotifier, String) setter;
  final List<SoundPickerItem> presets;

  const _SoundSlotConfig({
    required this.id,
    required this.icon,
    required this.iconColor,
    required this.labelKey,
    required this.descKey,
    required this.getter,
    required this.setter,
    this.presets = const [],
  });

  String get label => labelKey.tr();
  String get description => descKey.tr();

  /// 当前选中的显示文本
  String displayValue(SoundSettings s) {
    final v = getter(s);
    if (v.isEmpty) return 'sound_silent'.tr();
    final name = v.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
    return name;
  }
}

/// 从文件名生成友好标签
SoundPickerItem _preset(String path) {
  final name = path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
  return SoundPickerItem(label: name, value: path);
}

// ── 预设音频列表 ──────────────────────────────────────────
const _newPostPresets = [
  'assets/sounds/PostReceived/n-aec.mp3',
  'assets/sounds/PostReceived/soft.mp3',
];

const _postPresets = [
  'assets/sounds/PostSend/n-cea-4va.mp3',
];

const _notificationPresets = [
  'assets/sounds/Notifications/n-ea.mp3',
  'assets/sounds/Notifications/OpenHarmonyEvent.wav',
];

const _reactionPresets = [
  'assets/sounds/Emoji-Responses/bubble2.mp3',
  'assets/sounds/Emoji-Responses/OpenHarmony-Click.wav',
];

const _messagePresets = [
  'assets/sounds/Chat/waon.mp3',
  'assets/sounds/Chat/YunaAyase-Message.wav',
];

const _appUpdatePresets = [
  'assets/sounds/App/Update/update-available.ogg',
];

const _streamErrorPresets = [
  'assets/sounds/App/RTStream/disconnect.ogg',
];

// ── 插槽列表 ──────────────────────────────────────────────
final _notificationSlots = [
  _SoundSlotConfig(
    id: 'newPost',
    icon: Icons.edit_note_rounded,
    iconColor: SettingsIconColors.blue,
    labelKey: 'sound_new_post',
    descKey: 'sound_new_post_desc',
    getter: (s) => s.newPostSound,
    setter: (n, v) => n.setNewPostSound(v),
    presets: _newPostPresets.map(_preset).toList(),
  ),
  _SoundSlotConfig(
    id: 'post',
    icon: Icons.send_rounded,
    iconColor: SettingsIconColors.green,
    labelKey: 'sound_post',
    descKey: 'sound_post_desc',
    getter: (s) => s.postSound,
    setter: (n, v) => n.setPostSound(v),
    presets: _postPresets.map(_preset).toList(),
  ),
  _SoundSlotConfig(
    id: 'notification',
    icon: Icons.notifications_rounded,
    iconColor: SettingsIconColors.orange,
    labelKey: 'sound_notification',
    descKey: 'sound_notification_desc',
    getter: (s) => s.notificationSound,
    setter: (n, v) => n.setNotificationSound(v),
    presets: _notificationPresets.map(_preset).toList(),
  ),
  _SoundSlotConfig(
    id: 'reaction',
    icon: Icons.emoji_emotions_rounded,
    iconColor: SettingsIconColors.pink,
    labelKey: 'sound_reaction',
    descKey: 'sound_reaction_desc',
    getter: (s) => s.reactionSound,
    setter: (n, v) => n.setReactionSound(v),
    presets: _reactionPresets.map(_preset).toList(),
  ),
  _SoundSlotConfig(
    id: 'message',
    icon: Icons.chat_rounded,
    iconColor: SettingsIconColors.purple,
    labelKey: 'sound_message',
    descKey: 'sound_message_desc',
    getter: (s) => s.messageSound,
    setter: (n, v) => n.setMessageSound(v),
    presets: _messagePresets.map(_preset).toList(),
  ),
];

final _inAppSlots = [
  _SoundSlotConfig(
    id: 'switchAccount',
    icon: Icons.swap_horiz_rounded,
    iconColor: SettingsIconColors.cyan,
    labelKey: 'sound_switch_account',
    descKey: 'sound_switch_account_desc',
    getter: (s) => s.switchAccountSound,
    setter: (n, v) => n.setSwitchAccountSound(v),
  ),
  _SoundSlotConfig(
    id: 'triggerRefresh',
    icon: Icons.refresh_rounded,
    iconColor: SettingsIconColors.teal,
    labelKey: 'sound_trigger_refresh',
    descKey: 'sound_trigger_refresh_desc',
    getter: (s) => s.triggerRefreshSound,
    setter: (n, v) => n.setTriggerRefreshSound(v),
  ),
  _SoundSlotConfig(
    id: 'refresh',
    icon: Icons.sync_rounded,
    iconColor: SettingsIconColors.indigo,
    labelKey: 'sound_refresh',
    descKey: 'sound_refresh_desc',
    getter: (s) => s.refreshSound,
    setter: (n, v) => n.setRefreshSound(v),
  ),
  _SoundSlotConfig(
    id: 'appUpdate',
    icon: Icons.system_update_rounded,
    iconColor: SettingsIconColors.amber,
    labelKey: 'sound_app_update',
    descKey: 'sound_app_update_desc',
    getter: (s) => s.appUpdateSound,
    setter: (n, v) => n.setAppUpdateSound(v),
    presets: _appUpdatePresets.map(_preset).toList(),
  ),
  _SoundSlotConfig(
    id: 'streamError',
    icon: Icons.wifi_off_rounded,
    iconColor: SettingsIconColors.red,
    labelKey: 'sound_stream_error',
    descKey: 'sound_stream_error_desc',
    getter: (s) => s.streamErrorSound,
    setter: (n, v) => n.setStreamErrorSound(v),
    presets: _streamErrorPresets.map(_preset).toList(),
  ),
  _SoundSlotConfig(
    id: 'appError',
    icon: Icons.error_outline_rounded,
    iconColor: SettingsIconColors.deepOrange,
    labelKey: 'sound_app_error',
    descKey: 'sound_app_error_desc',
    getter: (s) => s.appErrorSound,
    setter: (n, v) => n.setAppErrorSound(v),
  ),
];

class SoundSettingsPage extends ConsumerWidget {
  const SoundSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(soundSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings_sound_title'.tr())),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            SettingsCardGroup(
              children: [
                for (final slot in _notificationSlots)
                  _buildTile(context, ref, settings, slot),
              ],
            ),
            const SizedBox(height: 16),
            SettingsCardGroup(
              children: [
                for (final slot in _inAppSlots)
                  _buildTile(context, ref, settings, slot),
              ],
            ),
          ],
        ),
        loading: () => const Center(child: CyaniLoadingIndicator()),
        error: (_, _) => ErrorState(message: 'common_error_occurred'.tr()),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    WidgetRef ref,
    SoundSettings settings,
    _SoundSlotConfig slot,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = slot.displayValue(settings);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openSoundPicker(context, ref, settings, slot),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: slot.iconColor.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(slot.icon, color: slot.iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.label,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      displayValue,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSoundPicker(
    BuildContext context,
    WidgetRef ref,
    SoundSettings settings,
    _SoundSlotConfig slot,
  ) async {
    final result = await showSoundPicker(
      context: context,
      icon: slot.icon,
      iconColor: slot.iconColor,
      title: slot.label,
      description: slot.description,
      currentValue: slot.getter(settings),
      presets: slot.presets,
      imports: [],
      silentLabel: 'sound_silent'.tr(),
      presetSectionLabel: 'sound_preset_section'.tr(),
      importSectionLabel: 'sound_import_section'.tr(),
      addFileLabel: 'sound_add_file'.tr(),
      onPreview: (path) async {
        final clean = path.replaceFirst('assets/', '');
        await ref.read(audioEngineProvider).playAsset(clean);
      },
      onAddFile: () async {
        if (!context.mounted) return null;
        showToast(title: 'sound_add_file_coming_soon'.tr());
        return null;
      },
    );
    if (result != null && context.mounted) {
      slot.setter(ref.read(soundSettingsProvider.notifier), result);
    }
  }

}

// ── Icon color palette ──
// Colors moved to SettingsIconColors in core/theme/color_constants.dart
