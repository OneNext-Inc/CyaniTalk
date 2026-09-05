import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'sound_settings_provider.g.dart';

/// 各插槽的默认资产路径。
/// 空字串 = 静音，非空字串 = 直接播放此路径。
class SoundDefaults {
  // 通知音
  static const newPost = 'assets/sounds/PostReceived/n-aec.mp3';
  static const post = 'assets/sounds/PostSend/n-cea-4va.mp3';
  static const notification = 'assets/sounds/Notifications/n-ea.mp3';
  static const reaction = 'assets/sounds/Emoji-Responses/bubble2.mp3';
  static const message = 'assets/sounds/Chat/waon.mp3';

  // App 内提示音
  static const appUpdate = 'assets/sounds/App/Update/update-available.ogg';
  static const streamError = 'assets/sounds/App/RTStream/disconnect.ogg';
}

class SoundSettings {
  final String newPostSound;
  final String postSound;
  final String notificationSound;
  final String reactionSound;
  final String messageSound;

  final String switchAccountSound;
  final String triggerRefreshSound;
  final String refreshSound;
  final String appUpdateSound;
  final String streamErrorSound;
  final String appErrorSound;

  SoundSettings({
    required this.newPostSound,
    required this.postSound,
    required this.notificationSound,
    required this.reactionSound,
    required this.messageSound,
    required this.switchAccountSound,
    required this.triggerRefreshSound,
    required this.refreshSound,
    required this.appUpdateSound,
    required this.streamErrorSound,
    required this.appErrorSound,
  });

  SoundSettings copyWith({
    String? newPostSound,
    String? postSound,
    String? notificationSound,
    String? reactionSound,
    String? messageSound,
    String? switchAccountSound,
    String? triggerRefreshSound,
    String? refreshSound,
    String? appUpdateSound,
    String? streamErrorSound,
    String? appErrorSound,
  }) {
    return SoundSettings(
      newPostSound: newPostSound ?? this.newPostSound,
      postSound: postSound ?? this.postSound,
      notificationSound: notificationSound ?? this.notificationSound,
      reactionSound: reactionSound ?? this.reactionSound,
      messageSound: messageSound ?? this.messageSound,
      switchAccountSound: switchAccountSound ?? this.switchAccountSound,
      triggerRefreshSound: triggerRefreshSound ?? this.triggerRefreshSound,
      refreshSound: refreshSound ?? this.refreshSound,
      appUpdateSound: appUpdateSound ?? this.appUpdateSound,
      streamErrorSound: streamErrorSound ?? this.streamErrorSound,
      appErrorSound: appErrorSound ?? this.appErrorSound,
    );
  }
}

@riverpod
class SoundSettingsNotifier extends _$SoundSettingsNotifier {
  static const _kNewPost = 'sound_new_post';
  static const _kPost = 'sound_post';
  static const _kNotification = 'sound_notification';
  static const _kReaction = 'sound_reaction';
  static const _kMessage = 'sound_message';
  static const _kSwitchAccount = 'sound_switch_account';
  static const _kTriggerRefresh = 'sound_trigger_refresh';
  static const _kRefresh = 'sound_refresh';
  static const _kAppUpdate = 'sound_app_update';
  static const _kStreamError = 'sound_stream_error';
  static const _kAppError = 'sound_app_error';

  @override
  FutureOr<SoundSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return SoundSettings(
      newPostSound: prefs.getString(_kNewPost) ?? SoundDefaults.newPost,
      postSound: prefs.getString(_kPost) ?? SoundDefaults.post,
      notificationSound:
          prefs.getString(_kNotification) ?? SoundDefaults.notification,
      reactionSound: prefs.getString(_kReaction) ?? SoundDefaults.reaction,
      messageSound: prefs.getString(_kMessage) ?? SoundDefaults.message,
      switchAccountSound: prefs.getString(_kSwitchAccount) ?? '',
      triggerRefreshSound: prefs.getString(_kTriggerRefresh) ?? '',
      refreshSound: prefs.getString(_kRefresh) ?? '',
      appUpdateSound: prefs.getString(_kAppUpdate) ?? SoundDefaults.appUpdate,
      streamErrorSound:
          prefs.getString(_kStreamError) ?? SoundDefaults.streamError,
      appErrorSound: prefs.getString(_kAppError) ?? '',
    );
  }

  Future<void> _setSlot(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> setNewPostSound(String v) async {
    await _setSlot(_kNewPost, v);
    state = AsyncData(state.value!.copyWith(newPostSound: v));
  }

  Future<void> setPostSound(String v) async {
    await _setSlot(_kPost, v);
    state = AsyncData(state.value!.copyWith(postSound: v));
  }

  Future<void> setNotificationSound(String v) async {
    await _setSlot(_kNotification, v);
    state = AsyncData(state.value!.copyWith(notificationSound: v));
  }

  Future<void> setReactionSound(String v) async {
    await _setSlot(_kReaction, v);
    state = AsyncData(state.value!.copyWith(reactionSound: v));
  }

  Future<void> setMessageSound(String v) async {
    await _setSlot(_kMessage, v);
    state = AsyncData(state.value!.copyWith(messageSound: v));
  }

  Future<void> setSwitchAccountSound(String v) async {
    await _setSlot(_kSwitchAccount, v);
    state = AsyncData(state.value!.copyWith(switchAccountSound: v));
  }

  Future<void> setTriggerRefreshSound(String v) async {
    await _setSlot(_kTriggerRefresh, v);
    state = AsyncData(state.value!.copyWith(triggerRefreshSound: v));
  }

  Future<void> setRefreshSound(String v) async {
    await _setSlot(_kRefresh, v);
    state = AsyncData(state.value!.copyWith(refreshSound: v));
  }

  Future<void> setAppUpdateSound(String v) async {
    await _setSlot(_kAppUpdate, v);
    state = AsyncData(state.value!.copyWith(appUpdateSound: v));
  }

  Future<void> setStreamErrorSound(String v) async {
    await _setSlot(_kStreamError, v);
    state = AsyncData(state.value!.copyWith(streamErrorSound: v));
  }

  Future<void> setAppErrorSound(String v) async {
    await _setSlot(_kAppError, v);
    state = AsyncData(state.value!.copyWith(appErrorSound: v));
  }
}
