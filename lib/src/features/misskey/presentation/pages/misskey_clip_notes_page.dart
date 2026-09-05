import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '/src/shared/widgets/toast_helper.dart';
import '/src/shared/widgets/error_state.dart';
import 'package:Nyachi/src/core/utils/logger.dart';
import 'package:Nyachi/src/features/auth/application/auth_service.dart';
import 'package:Nyachi/src/routing/router.dart';
import 'package:Nyachi/src/features/misskey/presentation/pages/misskey_post_page.dart';
import '/src/features/misskey/application/misskey_notifier.dart';
import '/src/features/misskey/domain/clip.dart';
import '/src/features/misskey/presentation/widgets/modern_note_card.dart';
import '/src/shared/widgets/cyani_loading_indicator.dart';

class MisskeyClipNotesPage extends ConsumerStatefulWidget {
  final Clip clip;

  const MisskeyClipNotesPage({super.key, required this.clip});

  @override
  ConsumerState<MisskeyClipNotesPage> createState() =>
      _MisskeyClipNotesPageState();
}

class _MisskeyClipNotesPageState extends ConsumerState<MisskeyClipNotesPage> {
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
      ref.read(misskeyClipNotesProvider(widget.clip.id).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(misskeyClipNotesProvider(widget.clip.id));
    final hasMore = ref
        .watch(misskeyClipNotesProvider(widget.clip.id).notifier)
        .hasMore;

    return Scaffold(
      appBar: AppBar(title: Text(widget.clip.name)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'misskey_fab_clip_${widget.clip.id}',
        onPressed: () async {
          logger.info('MisskeyClipNotesPage: Floating action button pressed');
          // 检查是否已登录 Misskey
          final authState = ref.read(authServiceProvider);
          final hasMisskeyAccount = authState.maybeWhen(
            data: (accounts) => accounts.any((a) => a.platform == 'misskey'),
            orElse: () => false,
          );

          if (hasMisskeyAccount) {
            // 已登录，打开发布窗口
            logger.info('MisskeyClipNotesPage: Opening post dialog');
            showDialog(
              context: context,
              builder: (context) => const MisskeyPostPage(),
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
      body: notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return Center(child: Text('timeline_no_notes_found'.tr()));
          }
          return RefreshIndicator(
            onRefresh: () => ref
                .read(misskeyClipNotesProvider(widget.clip.id).notifier)
                .refresh(),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: notes.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < notes.length) {
                  return ModernNoteCard(
                    key: ValueKey(notes[index].id),
                    note: notes[index],
                  );
                } else {
                  return _buildLoadMoreIndicator();
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
              .read(misskeyClipNotesProvider(widget.clip.id).notifier)
              .refresh(),
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
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
}
