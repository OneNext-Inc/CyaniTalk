import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '/src/features/misskey/domain/note.dart';
import '/src/features/misskey/domain/note_event.dart';
import '/src/features/misskey/domain/messaging_message.dart';

import '/src/features/auth/application/auth_service.dart';
import '/src/features/auth/domain/account.dart';
import '/src/core/config/constants.dart';
import '/src/core/services/streaming/streaming_service_interface.dart';
import '/src/core/services/audio_engine.dart';
import '/src/features/profile/application/network_settings_provider.dart';
import '/src/features/profile/application/sound_settings_provider.dart';
import '/src/shared/widgets/toast_helper.dart';
import '/src/core/utils/utils.dart';

part 'misskey_streaming_service.g.dart';

@Riverpod()
class MisskeyStreamingService extends _$MisskeyStreamingService
    implements IMisskeyStreamingService {
  WebSocketChannel? _channel;
  final _noteController = StreamController<NoteEvent>.broadcast();
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageController = StreamController<MessagingMessage>.broadcast();
  final _statusController = StreamController<StreamingStatus>.broadcast();
  final _toastVisibilityController = StreamController<bool>.broadcast();

  /// 当前显示的重连 toast 引用，用于在显示新 toast 前关闭旧的
  ToastificationItem? _currentReconnectToast;

  final Set<String> _activeTimelineSubscriptions = {};
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _pongWatchdogTimer;
  Timer? _backgroundMaxTimer;
  Timer? _toastHideTimer;
  Future<void>? _audioPlayFuture;
  DateTime? _backgroundStartTime;
  DateTime _lastPongReceived = DateTime.now();
  int _reconnectAttempts = 0;
  int _preResetReconnectAttempts = 0;
  DateTime? _connectionEstablishedAt;
  StreamingStatus _status = StreamingStatus.disconnected;

  /// 切换账户期间为 true，抑制所有重连 toast 直到新连接建立
  bool _suppressToast = false;

  static const _foregroundHeartbeat = Duration(seconds: 30);
  static const _backgroundHeartbeat = Duration(seconds: 90);
  Duration _heartbeatInterval = _foregroundHeartbeat;

  @override
  Stream<NoteEvent> get noteStream => _noteController.stream;

  @override
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;

  @override
  Stream<MessagingMessage> get messageStream => _messageController.stream;

  @override
  Stream<StreamingStatus> get statusStream => _statusController.stream;

  /// Toast 可见性流，用于在 AppBar 中显示/隐藏刷新按钮
  Stream<bool> get toastVisibilityStream => _toastVisibilityController.stream;

  StreamingStatus get status => _status;

  void _updateStatus(StreamingStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
    // 连接建立时自动清除 toast 抑制
    if (newStatus == StreamingStatus.connected && _suppressToast) {
      _suppressToast = false;
      logger.info('MisskeyStreaming: Connection established, clearing toast suppression');
    }
    logger.info('MisskeyStreaming: Status updated to $newStatus');
  }

  @override
  void build() {
    // Listen to account changes
    ref.listen(selectedMisskeyAccountProvider, (previous, next) {
      if (!ref.mounted) return;

      final account = next.asData?.value;
      if (account != null) {
        _connect();
      } else {
        _disconnect();
      }
    });

    // Initial connection check
    final initialAccount = ref
        .read(selectedMisskeyAccountProvider)
        .asData
        ?.value;
    if (initialAccount != null) {
      _connect();
    }

    ref.onDispose(() {
      _cleanup();
      _noteController.close();
      _messageController.close();
      _notificationController.close();
      _statusController.close();
      _toastVisibilityController.close();
    });
  }

  void _cleanup() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pongWatchdogTimer?.cancel();
    _backgroundMaxTimer?.cancel();
    _toastHideTimer?.cancel();
    _backgroundStartTime = null;
    _channel?.sink.close();
    _channel = null;
    _activeTimelineSubscriptions.clear();
  }

  @override
  void dispose() {
    _cleanup();
    _toastVisibilityController.close();
  }

  @override
  void reconnect() {
    // 如果刚从后台回来，无论当前状态如何都强制重连（连接可能已过期）
    if (_backgroundStartTime != null) {
      logger.info('MisskeyStreaming: Returning from background, forcing reconnect...');
      _cleanup();
      _updateStatus(StreamingStatus.disconnected);
      _reconnectAttempts = 0;
      final subscriptionsToRestore = Set<String>.from(_activeTimelineSubscriptions);
      _connect().then((_) {
        if (!ref.mounted) return;
        for (final channelName in subscriptionsToRestore) {
          _subscribeToChannel(channelName);
        }
      });
      return;
    }

    if (_status == StreamingStatus.connected && _channel != null) {
      logger.info('MisskeyStreaming: Already connected, skipping reconnect');
      return;
    }
    logger.info('MisskeyStreaming: Manually triggering reconnect...');
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    // Store current subscriptions to restore them after connection
    final subscriptionsToRestore = Set<String>.from(_activeTimelineSubscriptions);
    _connect().then((_) {
      if (!ref.mounted) return;
      for (final channelName in subscriptionsToRestore) {
        _subscribeToChannel(channelName);
      }
    });
  }

  bool _isConnecting = false;

  Future<void> _connect() async {
    if (!ref.mounted) return;
    if (_isConnecting) {
      logger.info('MisskeyStreaming: Already connecting, skipping...');
      return;
    }
    _isConnecting = true;

    final account = ref.read(selectedMisskeyAccountProvider).value;
    if (account == null) {
      _updateStatus(StreamingStatus.disconnected);
      _isConnecting = false;
      return;
    }

    _cleanup();
    _updateStatus(StreamingStatus.connecting);

    // 防御性清理：移除无效端口号（如 :0），防止 Cloudflare 524 错误
    final host = sanitizeHost(account.host);
    if (host != account.host) {
      logger.warning('MisskeyStreaming: Sanitized host from "${account.host}" to "$host"');
    }

    final uri = Uri.parse('wss://$host/streaming?i=${account.token}');
    logger.info('MisskeyStreaming: Connecting to $uri');

    try {
      final networkSettings = ref.read(networkSettingsProvider).value;
      final disableCertValidation = networkSettings?.disableCertificateValidation ?? false;

      final client = HttpClient();
      // 仅在用户明确禁用证书验证时跳过（用于自签名证书的实例）
      if (disableCertValidation) {
        logger.warning('MisskeyStreaming: SSL certificate validation disabled by user setting');
        client.badCertificateCallback = (cert, host, port) => true;
      }
      // 使用用户配置的超时时间（默认 30s），防止后台被挂起时超时
      final timeoutSeconds = networkSettings?.httpRequestTimeout ?? 30;
      client.connectionTimeout = Duration(seconds: timeoutSeconds);
      // 显式设置闲置超时
      client.idleTimeout = const Duration(seconds: 120);

      final userAgent = networkSettings?.effectiveUserAgent ?? Constants.getUserAgent();

      // 使用局部变量防止竞态条件
      final channel = IOWebSocketChannel.connect(
        uri,
        customClient: client,
        headers: {
          'User-Agent': userAgent,
        },
      );
      _channel = channel;

      // 显式等待并监听流，以捕获连接初始阶段的异常
      await channel.ready; 

      if (_channel != channel) {
        logger.warning('MisskeyStreaming: Connection established but channel was swapped. Closing old one.');
        channel.sink.close();
        return;
      }

      _updateStatus(StreamingStatus.connected);
      _preResetReconnectAttempts = _reconnectAttempts;
      _connectionEstablishedAt = DateTime.now();
      _reconnectAttempts = 0;

      channel.stream.listen(
        (message) {
          try {
            _handleMessage(message);
          } catch (e) {
            logger.error('MisskeyStreaming: Error handling message: $e');
            // 消息处理错误不应导致连接断开
          }
        },
        onDone: () {
          logger.warning('MisskeyStreaming: Connection closed');
          _updateStatus(StreamingStatus.disconnected);
          _handleDisconnect(account);
        },
        onError: (error) {
          final errorStr = error.toString().toLowerCase();
          logger.error('MisskeyStreaming: Stream error: $error');

          // ── 错误分类 ──────────────────────────────────────────
          // 仅"致命"错误（WebSocket 连接本身不可恢复）才触发重连；
          // HTTP 5xx 等瞬态错误只记录日志，不中断连接。
          if (_isFatalStreamError(errorStr)) {
            _logStreamError(errorStr);
            _updateStatus(StreamingStatus.error);
            _handleDisconnect(account);
          } else {
            // 非致命：仅记录，不触发重连
            logger.info(
              'MisskeyStreaming: Non-fatal stream error, '
              'connection remains alive',
            );
          }
        },
        cancelOnError: false, // 即使发生错误也不取消订阅，让onError处理
      );

      _startHeartbeat();
      _subscribeToMain();
    } catch (e) {
      logger.error('MisskeyStreaming Connection failed (Catch): $e');
      _updateStatus(StreamingStatus.error);
      _handleDisconnect(account);
    } finally {
      _isConnecting = false;
    }
  }

  // ── 流错误分类 ──────────────────────────────────────────────────────
  //
  // WebSocket 流的 onError 可能收到多种错误：
  //   [致命] 真正的连接中断 → 需要重连
  //     - SocketException（连接被重置、网络不可达、管道破裂…）
  //     - WebSocketException / HttpException（协议层错误）
  //     - SSL/TLS 握手失败、证书问题
  //     - Windows Error 121 (Semaphore Timeout)
  //     - EOFError（对端异常关闭）
  //     - "Connection closed before full header was received"（升级被拒）
  //
  //   [非致命] 瞬态 / 资源层错误 → 仅记录，连接仍存活
  //     - HTTP 5xx（502 Bad Gateway / 503 / 524 等，反向代理或 CDN 临时故障）
  //     - HTTP 4xx（429 Too Many Requests / 403 Forbidden）
  //     - 请求超时（单次 API 调用失败）
  //     - DNS 解析抖动（非首次连接阶段）

  /// 判断流错误是否为致命错误（需要触发重连）
  bool _isFatalStreamError(String errorStr) {
    // ── 真正的连接中断 ────────────────────────────────────────
    if (errorStr.contains('socket')) {
      return true;
    }
    if (errorStr.contains('connection reset by peer')) {
      return true;
    }
    if (errorStr.contains('connection refused')) {
      return true;
    }
    if (errorStr.contains('connection timed out') ||
        errorStr.contains('connection timeout')) {
      return true;
    }
    if (errorStr.contains('network is unreachable')) {
      return true;
    }
    if (errorStr.contains('no route to host')) {
      return true;
    }
    if (errorStr.contains('broken pipe')) {
      return true;
    }
    if (errorStr.contains('connection aborted')) {
      return true;
    }
    if (errorStr.contains('connection closed')) {
      return true;
    }
    if (errorStr.contains('eof')) {
      return true;
    }

    // ── WebSocket 协议层错误 ──────────────────────────────────
    if (errorStr.contains('websocket')) {
      return true;
    }
    if (errorStr.contains('handshake')) {
      return true;
    }
    if (errorStr.contains('terminated')) {
      return true;
    }

    // ── SSL / TLS 错误 ────────────────────────────────────────
    if (errorStr.contains('ssl') || errorStr.contains('tls')) {
      return true;
    }
    if (errorStr.contains('certificate')) {
      return true;
    }

    // ── Windows 特有 ──────────────────────────────────────────
    if (errorStr.contains('121') || errorStr.contains('semaphore')) {
      return true;
    }

    // ── 非致命：HTTP 错误、超时、DNS 抖动 ────────────────────
    // HTTP 5xx (502/503/504/524 等) — 反向代理或 CDN 临时故障
    if (errorStr.contains('502') || errorStr.contains('bad gateway')) {
      return false;
    }
    if (errorStr.contains('503') ||
        errorStr.contains('service unavailable')) {
      return false;
    }
    if (errorStr.contains('504') || errorStr.contains('gateway timeout')) {
      return false;
    }
    if (errorStr.contains('524') ||
        errorStr.contains('a timeout occurred')) {
      return false;
    }
    if (errorStr.contains('5')) {
      return false; // 通用 5xx
    }

    // HTTP 4xx (429 限流 / 403 禁止)
    if (errorStr.contains('429') || errorStr.contains('too many requests')) {
      return false;
    }
    if (errorStr.contains('403') || errorStr.contains('forbidden')) {
      return false;
    }
    if (errorStr.contains('4')) {
      return false; // 通用 4xx
    }

    // 请求超时、DNS 解析抖动
    if (errorStr.contains('timeout')) {
      return false;
    }
    if (errorStr.contains('temporarily')) {
      return false;
    }

    // ── 未识别的错误：保守策略，视为致命 ──────────────────────
    logger.warning(
      'MisskeyStreaming: Unrecognized stream error, treating as fatal: $errorStr',
    );
    return true;
  }

  /// 为已知的致命错误类型记录详细的诊断日志
  void _logStreamError(String errorStr) {
    if (errorStr.contains('121') || errorStr.contains('semaphore')) {
      logger.error('MisskeyStreaming: Windows Semaphore Timeout (Error 121)');
    } else if (errorStr.contains('handshake') || errorStr.contains('terminated')) {
      logger.error('MisskeyStreaming: SSL Handshake Failure');
    } else if (errorStr.contains('connection reset by peer')) {
      logger.error('MisskeyStreaming: Connection Reset by Peer');
    } else if (errorStr.contains('socket closed')) {
      logger.error('MisskeyStreaming: Socket Closed');
    } else if (errorStr.contains('certificate')) {
      logger.error('MisskeyStreaming: SSL Certificate Error');
    } else if (errorStr.contains('eof')) {
      logger.error('MisskeyStreaming: Unexpected EOF');
    }
  }

  void _handleDisconnect(Account account) {
    _reconnectTimer?.cancel();

    final settingsAsync = ref.read(networkSettingsProvider);
    final maxAttempts = settingsAsync.value?.webSocketReconnectAttempts ?? 5;

    // 如果连接存活时间过短（<10秒），不重置退避计数，防止1秒重连风暴
    if (_connectionEstablishedAt != null) {
      final alive = DateTime.now().difference(_connectionEstablishedAt!);
      if (alive < const Duration(seconds: 10)) {
        _reconnectAttempts = _preResetReconnectAttempts;
        logger.info(
          'MisskeyStreaming: 连接仅存活 ${alive.inSeconds}s，'
          '恢复退避计数为 $_reconnectAttempts',
        );
      }
    }
    _connectionEstablishedAt = null;

    _reconnectAttempts++;

    if (_reconnectAttempts >= maxAttempts) {
      logger.error('MisskeyStreaming: Maximum reconnection attempts reached ($maxAttempts). Stopping automatic retry.');
      _updateStatus(StreamingStatus.error);
      _showMaxRetryToast();
      return;
    }

    // 指数避退重连
    final delay = Duration(seconds: (1 << (_reconnectAttempts - 1)));

    logger.info(
      'MisskeyStreaming: Scheduling reconnect in ${delay.inSeconds}s (Attempt $_reconnectAttempts/$maxAttempts)',
    );

    _showReconnectToast();

    _reconnectTimer = Timer(delay, () {
      if (!ref.mounted) return;

      final currentAccount = ref.read(selectedMisskeyAccountProvider).value;
      if (currentAccount?.id == account.id) {
        _connect();
      }
    });
  }

  void _showReconnectToast() {
    // 切换账户期间抑制 toast
    if (_suppressToast) {
      logger.info('MisskeyStreaming: Toast suppressed during account switch');
      return;
    }
    // 关闭旧的重连 toast，避免屏幕上堆积多个提示
    _dismissCurrentReconnectToast();

    _toastVisibilityController.add(true);
    _currentReconnectToast = showToast(
      title: 'stream_disconnected'.tr(),
      description: 'stream_reconnecting'.tr(namedArgs: {'n': _reconnectAttempts.toString()}),
      type: ToastificationType.warning,
      autoCloseDuration: const Duration(seconds: 8),
    );
    // 8 秒后自动隐藏刷新按钮
    _toastHideTimer?.cancel();
    _toastHideTimer = Timer(const Duration(seconds: 8), () {
      if (!_toastVisibilityController.isClosed) {
        _toastVisibilityController.add(false);
      }
    });
  }

  void _showMaxRetryToast() {
    // 关闭旧的重连 toast，避免屏幕上堆积多个提示
    _dismissCurrentReconnectToast();

    final soundAsync = ref.read(soundSettingsProvider);
    final soundPath = soundAsync.value?.streamErrorSound;
    if (soundPath != null && soundPath.isNotEmpty) {
      _audioPlayFuture = ref.read(audioEngineProvider).playAsset(soundPath);
      _audioPlayFuture?.catchError((_) {});
    }

    _toastVisibilityController.add(true);
    _currentReconnectToast = showToast(
      title: 'stream_reconnect_failed_title'.tr(),
      description: 'stream_reconnect_failed_body'.tr(),
      type: ToastificationType.error,
      autoCloseDuration: null, // 持续显示，直到用户手动刷新
    );
  }

  /// 关闭当前 Toast 并隐藏刷新按钮，然后尝试重连
  void dismissToastAndReconnect() {
    _dismissCurrentReconnectToast();
    toastification.dismissAll();
    _toastVisibilityController.add(false);
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    reconnect();
  }

  /// 关闭当前显示的重连 toast
  void _dismissCurrentReconnectToast() {
    if (_currentReconnectToast != null) {
      toastification.dismiss(_currentReconnectToast!);
      _currentReconnectToast = null;
    }
  }

  /// 切换账户期间抑制所有重连 toast，直到新连接建立
  ///
  /// 在调用 [setPrimaryAccount] 前设为 true，
  /// 在检测到 [StreamingStatus.connected] 后自动清除。
  void setSuppressToast(bool value) {
    _suppressToast = value;
    if (value) {
      // 立即关闭当前 toast
      _dismissCurrentReconnectToast();
      _toastVisibilityController.add(false);
    }
    logger.info('MisskeyStreaming: Toast suppression set to $value');
  }

  bool get isSuppressingToast => _suppressToast;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _pongWatchdogTimer?.cancel();
    _lastPongReceived = DateTime.now(); // 连接刚建立，重置计时
    final interval = _heartbeatInterval;

    // 心跳发送定时器
    _heartbeatTimer = Timer.periodic(interval, (timer) {
      if (_status == StreamingStatus.connected && _channel != null) {
        try {
          _channel!.sink.add('h');
          logger.debug('MisskeyStreaming: Sent app-level heartbeat ("h")');
        } catch (e) {
          logger.error('MisskeyStreaming: Heartbeat send failed: $e');
          final account = ref.read(selectedMisskeyAccountProvider).value;
          if (account != null) {
            _handleDisconnect(account);
          }
        }
      }
    });

    // Pong 监视定时器：检查是否在 2× 心跳间隔内收到过 pong/h 响应
    // 如果超时未收到，说明连接已死但未触发 onDone
    final watchdogInterval = Duration(seconds: interval.inSeconds * 2);
    _pongWatchdogTimer = Timer.periodic(watchdogInterval, (timer) {
      if (_status != StreamingStatus.connected || _channel == null) return;
      final elapsed = DateTime.now().difference(_lastPongReceived);
      if (elapsed > watchdogInterval) {
        logger.warning(
          'MisskeyStreaming: No pong/h received in ${elapsed.inSeconds}s '
          '(expected ${watchdogInterval.inSeconds}s). Triggering reconnect.',
        );
        final account = ref.read(selectedMisskeyAccountProvider).value;
        if (account != null) {
          _handleDisconnect(account);
        }
      }
    });
  }

  void setBackgroundMode(bool isBackground) {
    final newInterval =
        isBackground ? _backgroundHeartbeat : _foregroundHeartbeat;
    if (_heartbeatInterval == newInterval) return;
    _heartbeatInterval = newInterval;
    logger.info(
      'MisskeyStreaming: 切换心跳频率为 ${isBackground ? "90s(后台)" : "30s(前台)"}',
    );

    if (isBackground) {
      _backgroundStartTime = DateTime.now();
      // 启动后台最大时长定时器
      _backgroundMaxTimer?.cancel();
      final maxDuration = ref.read(networkSettingsProvider).value?.webSocketBackgroundMaxDuration ?? 3600;
      _backgroundMaxTimer = Timer(Duration(seconds: maxDuration), () {
        if (_status == StreamingStatus.connected) {
          logger.info('MisskeyStreaming: 后台超时 ${maxDuration}s，强制重连');
          _cleanup();
          _updateStatus(StreamingStatus.disconnected);
          _connect();
        }
      });
    } else {
      _backgroundMaxTimer?.cancel();
      _backgroundStartTime = null;
    }

    if (_status == StreamingStatus.connected && _channel != null) {
      _startHeartbeat();
    }
  }

  void _disconnect() {
    _cleanup();
    _updateStatus(StreamingStatus.disconnected);
  }

  void _subscribeToMain() {
    if (_channel == null) return;

    final msg = jsonEncode({
      'type': 'connect',
      'body': {
        'channel': 'main',
        'id': 'main-${DateTime.now().millisecondsSinceEpoch}',
      },
    });

    _channel!.sink.add(msg);
    logger.info('MisskeyStreaming: Subscribed to main channel');
  }

  @override
  void subscribeToTimeline(String timelineType) {
    // Map internal type to Misskey channel name
    final channelName = switch (timelineType) {
      'Home' => 'homeTimeline',
      'Local' => 'localTimeline',
      'Social' => 'hybridTimeline',
      'Global' => 'globalTimeline',
      _ => 'homeTimeline',
    };

    _subscribeToChannel(channelName);
  }

  void _subscribeToChannel(String channelName) {
    if (_channel == null) return;

    final msg = jsonEncode({
      'type': 'connect',
      'body': {'channel': channelName, 'id': 'timeline-$channelName'},
    });

    _channel!.sink.add(msg);
    _activeTimelineSubscriptions.add(channelName);
    logger.info('MisskeyStreaming: Subscribed to $channelName channel');
  }

  void _handleMessage(dynamic message) {
    // 忽略心跳响应，但更新最后 pong 时间用于连接活性检测
    if (message == 'h' || message == 'pong') {
      _lastPongReceived = DateTime.now();
      return;
    }
    
    logger.debug('MisskeyStreaming Received: $message');

    try {
      // 确保消息是字符串类型
      if (message is! String) {
        logger.warning('MisskeyStreaming: Received non-string message: $message');
        return;
      }

      final Map<String, dynamic> data = jsonDecode(message);
      final type = data['type'];
      final body = data['body'];

      if (type == 'channel' && body != null) {
        try {
          final channelId = body['id'] as String;
          final eventType = body['type'];
          final eventBody = body['body'];

          if (eventType == 'note' && eventBody != null) {
            try {
              final note = Note.fromJson(eventBody as Map<String, dynamic>);
              String? timelineType;

              if (channelId.startsWith('timeline-')) {
                final misskeyChannel = channelId.substring(9);
                timelineType = switch (misskeyChannel) {
                  'homeTimeline' => 'Home',
                  'localTimeline' => 'Local',
                  'hybridTimeline' => 'Social',
                  'globalTimeline' => 'Global',
                  _ => null,
                };
              }

              if (timelineType != null && !_noteController.isClosed) {
                _noteController.add(
                  NoteEvent(note: note, timelineType: timelineType),
                );
              }
            } catch (e) {
              logger.error('MisskeyStreaming: Error parsing note event: $e');
            }
          } else if (eventType == 'notification' && eventBody != null) {
            if (!_notificationController.isClosed) {
              _notificationController.add(eventBody as Map<String, dynamic>);
            }
          } else if ((eventType == 'chatMessage' ||
                  eventType == 'messagingMessage') &&
              eventBody != null) {
            try {
              final message = MessagingMessage.fromJson(
                eventBody as Map<String, dynamic>,
              );
              if (!_messageController.isClosed) {
                _messageController.add(message);
              }
            } catch (e) {
              logger.error('MisskeyStreaming: Error parsing messaging message: $e');
            }
          } else if (eventType == 'noteDeleted') {
            try {
              final noteId =
                  eventBody?['deletedId'] as String? ??
                  eventBody?['id'] as String? ??
                  eventBody?['noteId'] as String?;

              if (noteId != null && !_noteController.isClosed) {
                _noteController.add(NoteEvent(noteId: noteId, isDelete: true));
              }
            } catch (e) {
              logger.error('MisskeyStreaming: Error parsing note deleted event: $e');
            }
          }
        } catch (e) {
          logger.error('MisskeyStreaming: Error processing channel event: $e');
        }
      }
    } catch (e) {
      logger.error('MisskeyStreaming: Error parsing message: $e');
    }
  }

  @override
  void sendMessage(Map<String, dynamic> data) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        logger.error('MisskeyStreaming: Error sending message: $e');
        // 发送失败不应导致应用崩溃，尝试重连
        final account = ref.read(selectedMisskeyAccountProvider).value;
        if (account != null) {
          _handleDisconnect(account);
        }
      }
    }
  }
}
