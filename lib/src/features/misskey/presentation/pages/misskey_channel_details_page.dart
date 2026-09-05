import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '/src/shared/widgets/toast_helper.dart';
import '/src/shared/widgets/error_state.dart';
import 'package:Nyachi/src/core/utils/logger.dart';
import 'package:Nyachi/src/features/auth/application/auth_service.dart';
import 'package:Nyachi/src/routing/router.dart';
import 'package:Nyachi/src/features/misskey/presentation/pages/misskey_post_page.dart';
import 'package:Nyachi/src/features/misskey/application/misskey_notifier.dart';
import 'package:Nyachi/src/features/misskey/application/timeline_jump_provider.dart';
import 'package:Nyachi/src/features/misskey/domain/channel.dart';
import 'package:Nyachi/src/features/misskey/presentation/widgets/modern_note_card.dart';
import '/src/shared/widgets/cyani_loading_indicator.dart';

class MisskeyChannelDetailsPage extends ConsumerStatefulWidget {
  final Channel channel;

  const MisskeyChannelDetailsPage({super.key, required this.channel});

  @override
  ConsumerState<MisskeyChannelDetailsPage> createState() =>
      _MisskeyChannelDetailsPageState();
}

class _MisskeyChannelDetailsPageState
    extends ConsumerState<MisskeyChannelDetailsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(misskeyChannelTimelineProvider(widget.channel.id).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(
      misskeyChannelTimelineProvider(widget.channel.id),
    );

    // 监听跳转信号
    ref.listen(timelineJumpProvider(widget.channel.id), (previous, next) {
      if (next != null) {
        final notes = timelineAsync.value ?? [];
        final index = notes.indexWhere((n) => n.id == next);
        if (index != -1) {
          _scrollController.animateTo(
            index * 250.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
          ref.read(timelineJumpProvider(widget.channel.id).notifier).trigger(
              null);
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'misskey_fab_channel_${widget.channel.id}',
        onPressed: () async {
          logger.info(
            'MisskeyChannelDetailsPage: Floating action button pressed',
          );
          // 检查是否已登录 Misskey
          final authState = ref.read(authServiceProvider);
          final hasMisskeyAccount = authState.maybeWhen(
            data: (accounts) => accounts.any((a) => a.platform == 'misskey'),
            orElse: () => false,
          );

          if (hasMisskeyAccount) {
            // 已登录，打开发布窗口，并传入当前频道ID
            logger.info(
              'MisskeyChannelDetailsPage: Opening post dialog for channel ${widget.channel.id}',
            );
            showDialog(
              context: context,
              builder: (context) =>
                  MisskeyPostPage(channelId: widget.channel.id),
            );
          } else {
            // 未登录，提示用户
            if (mounted) {
              showToast(title: 'misskey_page_please_login'.tr(), type: ToastificationType.info);
              // 跳转到 Profile 页面进行登录
              final router = ref.read(goRouterProvider);
              router.go('/profile');
            }
          }
        },
        child: const Icon(Icons.edit),
      ),
      body: timelineAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return Center(
              child: Text('channel_details_no_notes_in_this_channel'.tr()),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref
                .read(
                  misskeyChannelTimelineProvider(widget.channel.id).notifier,
                )
                .refresh(),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: notes.length + 1,
              itemBuilder: (context, index) {
                if (index < notes.length) {
                  return ModernNoteCard(
                    note: notes[index],
                    timelineType: widget.channel.id,
                  );
                } else {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
              },
            ),
          );
        },
        loading: () => const Center(child: CyaniLoadingIndicator()),
        error: (err, stack) => ErrorState(
          message: '${'common_loading_failed'.tr()}\nError: $err',
          retryLabel: 'common_reload'.tr(),
          onRetry: () => ref
              .read(
                misskeyChannelTimelineProvider(
                  widget.channel.id,
                ).notifier,
              )
              .refresh(),
        ),
      ),
    );
  }
}
