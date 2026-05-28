import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_steam/qr_steam.dart';

import '../services/image_service.dart';

/// Windows 发送端页面：
/// 1. 截取全屏截图。
/// 2. 使用 [ImageCompressService] 压缩为 AVIF 或 HEIC。
/// 3. 使用普通分片或喷泉码对压缩字节编码。
/// 4. 以动态 [QrStreamSender] 组件显示。
class SenderPage extends StatefulWidget {
  const SenderPage({super.key});

  @override
  State<SenderPage> createState() => _SenderPageState();
}

class _SenderPageState extends State<SenderPage> {
  // 页面状态机
  _SenderState _state = _SenderState.idle;
  String? _errorMessage; // 错误时展示的描述信息

  // 数据大小统计，用于 UI 信息栏展示
  int _rawSize = 0; // 原始 PNG 大小（字节）
  int _compressedSize = 0; // 压缩后大小（字节）
  int _numChunks = 0; // 喷泉码源块数量

  // 待流式传输的压缩字节
  Uint8List? _payload;

  // QR 流参数
  int _fps = 5;
  int _chunkSize = 280; // 单块字节数 → base64 约 380 字符 → QR v18

  // 压缩格式：AVIF（全平台）或 HEIC（Android/iOS/macOS）
  ImageFormat _format = ImageFormat.avif;

  // 传输模式：默认喷泉码，更适合摄像头丢帧场景。
  QrTransferMode _mode = QrTransferMode.fountain;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _captureAndStream() async {
    setState(() {
      _state = _SenderState.capturing;
      _errorMessage = null;
    });

    try {
      // 1. 截图 → PNG 字节
      final raw = await ScreenshotService.captureScreen();
      _rawSize = raw.length;

      setState(() => _state = _SenderState.compressing);

      // 2. Compress → AVIF 或 HEIC（Windows 选 HEIC 时自动回退到 AVIF）
      final compressed = await ImageCompressService.compress(
        raw,
        format: _format,
        quality: 55,
        maxDimension: 1280,
      );
      _compressedSize = compressed.length;
      // 3. 计算总块数并更新 UI
      _numChunks = (_compressedSize + _chunkSize - 1) ~/ _chunkSize;

      setState(() {
        _payload = compressed;
        _state = _SenderState.streaming;
      });
    } catch (e) {
      setState(() {
        _state = _SenderState.error;
        _errorMessage = e.toString();
      });
    }
  }

  /// 停止流式传输并清空状态。
  void _stopAndReset() {
    setState(() {
      _payload = null;
      _state = _SenderState.idle;
      _errorMessage = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Steam – 发送端'),
        actions: [
          if (_state == _SenderState.streaming)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '停止',
              onPressed: _stopAndReset,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '参数设置',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _ModeSwitchTile(
            value: _mode == QrTransferMode.fountain,
            onChanged: (enabled) {
              setState(() {
                _mode = enabled
                    ? QrTransferMode.fountain
                    : QrTransferMode.sequential;
              });
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _state != _SenderState.streaming
          ? FloatingActionButton.extended(
              onPressed:
                  _state == _SenderState.idle || _state == _SenderState.error
                      ? _captureAndStream
                      : null,
              icon: const Icon(Icons.screenshot),
              label: const Text('截图并发送'),
            )
          : FloatingActionButton.extended(
              onPressed: _captureAndStream,
              icon: const Icon(Icons.refresh),
              label: const Text('重新截图'),
            ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _SenderState.idle:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_2, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text('点击下方按钮截图并开始发送',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        );

      case _SenderState.capturing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在截图...'),
            ],
          ),
        );

      case _SenderState.compressing:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在压缩图片 (${_format.label})...'),
            ],
          ),
        );

      case _SenderState.streaming:
        return _buildStreamingView();

      case _SenderState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 12),
              const Text('发生错误', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _errorMessage ?? '未知错误',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        );
    }
  }

  /// 构建流式传输视图：展示信息栏 + 动态 QR 码。
  Widget _buildStreamingView() {
    return Column(
      children: [
        // 信息栏：显示大小、压缩率、格式、分块数等元数据
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Wrap(
            spacing: 24,
            runSpacing: 4,
            children: [
              _InfoChip(label: '原始大小', value: _formatBytes(_rawSize)),
              _InfoChip(label: '压缩后', value: _formatBytes(_compressedSize)),
              _InfoChip(
                  label: '压缩率',
                  value:
                      '${(_compressedSize / _rawSize * 100).toStringAsFixed(1)}%'),
              _InfoChip(label: '传输模式', value: _mode.label),
              _InfoChip(label: '格式', value: _format.label),
              _InfoChip(label: '数据块数', value: '$_numChunks'),
              _InfoChip(label: '帧率', value: '$_fps fps'),
            ],
          ),
        ),

        // 动态 QR 码展示区域
        Expanded(
          child: Center(
            child: QrStreamSender(
              data: _payload!,
              fps: _fps,
              chunkSize: _chunkSize,
              mode: _mode,
              size: 360,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 设置底部弹层
  // ---------------------------------------------------------------------------

  /// 展开参数设置底部弹层，允许用户调整 fps、块大小和压缩格式。
  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _SettingsSheet(
        fps: _fps,
        chunkSize: _chunkSize,
        format: _format,
        onChanged: (fps, chunkSize, format) => setState(() {
          _fps = fps;
          _chunkSize = chunkSize;
          _format = format;
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 工具方法
  // ---------------------------------------------------------------------------

  /// 将字节数格式化为可读字符串（B / KB / MB）。
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

// ---------------------------------------------------------------------------
// 辅助组件
// ---------------------------------------------------------------------------

/// 页面内部状态枚举：空闲 / 截图中 / 压缩中 / 流式传输中 / 错误。
enum _SenderState { idle, capturing, compressing, streaming, error }

/// 信息栏展示一个标签-数字对。
class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
        children: [
          TextSpan(
              text: '$label: ', style: const TextStyle(color: Colors.grey)),
          TextSpan(
              text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 参数设置底部弹层：可调整 fps、块大小和压缩格式。
class _SettingsSheet extends StatefulWidget {
  final int fps; // 当前帧率
  final int chunkSize; // 当前块大小（字节）
  final ImageFormat format; // 当前压缩格式
  /// 任一参数变更后的回调
  final void Function(int fps, int chunkSize, ImageFormat format) onChanged;

  const _SettingsSheet({
    required this.fps,
    required this.chunkSize,
    required this.format,
    required this.onChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _fps; // 本地帧率剥本
  late int _chunkSize; // 本地块大小剥本
  late ImageFormat _format; // 本地格式剥本

  @override
  void initState() {
    super.initState();
    _fps = widget.fps;
    _chunkSize = widget.chunkSize;
    _format = widget.format;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('参数设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // 帧率滑块 (1–15 fps)
          Text('帧率: $_fps fps'),
          Slider(
            value: _fps.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            label: '$_fps',
            onChanged: (v) {
              setState(() => _fps = v.round());
              widget.onChanged(_fps, _chunkSize, _format);
            },
          ),

          // 块大小滑块 (100–500 字节，步进 50)
          Text('块大小: $_chunkSize 字节 '
              '(QR 容量: ~${(_chunkSize * 4 / 3 + 30).round()} 字节)'),
          Slider(
            value: _chunkSize.toDouble(),
            min: 100,
            max: 500,
            divisions: 16,
            label: '$_chunkSize',
            onChanged: (v) {
              setState(() => _chunkSize = (v / 50).round() * 50);
              widget.onChanged(_fps, _chunkSize, _format);
            },
          ),
          const SizedBox(height: 12),

          // 压缩格式切换按鈕（AVIF 全平台，HEIC 仅支持非 Windows）
          const Text('压缩格式'),
          const SizedBox(height: 8),
          SegmentedButton<ImageFormat>(
            segments: [
              const ButtonSegment(
                value: ImageFormat.avif,
                label: Text('AVIF'),
                icon: Icon(Icons.high_quality),
              ),
              ButtonSegment(
                value: ImageFormat.heic,
                label: const Text('HEIC'),
                icon: const Icon(Icons.photo),
                enabled: ImageCompressService.heicSupported,
              ),
            ],
            selected: {_format},
            onSelectionChanged: (s) {
              setState(() => _format = s.first);
              widget.onChanged(_fps, _chunkSize, _format);
            },
          ),
          if (!ImageCompressService.heicSupported)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'HEIC 在 Windows 上不可用，仅支持 Android / iOS / macOS',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ModeSwitchTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ModeSwitchTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final mode = value ? QrTransferMode.fountain : QrTransferMode.sequential;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        secondary: Icon(value ? Icons.water_drop : Icons.view_week),
        title: const Text('喷泉码加速'),
        subtitle: Text(mode.description),
      ),
    );
  }
}
