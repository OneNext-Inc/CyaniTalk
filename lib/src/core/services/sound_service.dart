import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/src/features/profile/application/sound_settings_provider.dart';
import 'audio_engine.dart';

class SoundService {
  final Ref ref;

  SoundService(this.ref);

  Future<void> playMisskeyRealtimePost() async {
    final settings = await ref.read(soundSettingsProvider.future);
    if (settings.newPostSound.isNotEmpty) {
      await _play(settings.newPostSound);
    }
  }

  Future<void> playMisskeyPosting() async {
    final settings = await ref.read(soundSettingsProvider.future);
    if (settings.postSound.isNotEmpty) {
      await _play(settings.postSound);
    }
  }

  Future<void> playMisskeyNotifications() async {
    final settings = await ref.read(soundSettingsProvider.future);
    if (settings.notificationSound.isNotEmpty) {
      await _play(settings.notificationSound);
    }
  }

  Future<void> playMisskeyEmojiReactions() async {
    final settings = await ref.read(soundSettingsProvider.future);
    if (settings.reactionSound.isNotEmpty) {
      await _play(settings.reactionSound);
    }
  }

  Future<void> playMisskeyMessages() async {
    final settings = await ref.read(soundSettingsProvider.future);
    if (settings.messageSound.isNotEmpty) {
      await _play(settings.messageSound);
    }
  }

  Future<void> playAppUpdate() async {
    final settings = await ref.read(soundSettingsProvider.future);
    if (settings.appUpdateSound.isNotEmpty) {
      await _play(settings.appUpdateSound);
    }
  }

    Future<void> _play(String assetPath) async {
      await ref.read(audioEngineProvider).playAsset(assetPath);
    }
}

final soundServiceProvider = Provider(SoundService.new);
