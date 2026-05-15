import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'fountain_packet.dart';

/// LT 喷泉码解码器（置信传播 / 剥离解码器）。
///
/// 通过 [addPacket] 逐个投入接收到的 [FountainPacket]。
/// 解码器采用消息传递算法：一旦发现度数为 1 的包，就直接恢复对应源块，
/// 再将已恢复的块 XOR 到所有引用它的活跃包中（度数减 1），如此洚涁打开直到恢复全部 k 个块。
///
/// 典型用法：
/// ```dart
/// final decoder = FountainDecoder();
/// while (!decoder.isComplete) {
///   final pkt = receivedPackets.next();
///   decoder.addPacket(pkt);
/// }
/// final original = decoder.decodedData!;
/// ```
class FountainDecoder {
  // 数据流元信息（从第一个有效包中提取）
  int? _totalLength; // 原始数据的总字节数
  int? _numChunks; // 源块总数 k
  int? _chunkSize; // 单块字节数

  // 已恢复的源块列表，null 表示尚未恢复
  late List<Uint8List?> _recovered;
  int _recoveredCount = 0; // 已成功恢复的块数

  /// 还未被完全解码、仍需参与传播的活跃包
  final List<_ActivePacket> _active = [];

  /// 刚刺恢复的块的下标队列，等待传播处理
  final Queue<int> _propagationQueue = Queue();

  bool _initialized = false; // 是否已从第一个包初始化元信息
  bool _complete = false; // 是否已全部解码完成

  // ---------------------------------------------------------------------------
  // 公共 API
  // ---------------------------------------------------------------------------

  /// 解码是否成功，[decodedData] 可用时返回 true。
  bool get isComplete => _complete;

  /// 已恢复的源块数量。
  int get recoveredCount => _recoveredCount;

  /// 源块总数（未收到任何包之前为 null）。
  int? get totalChunks => _numChunks;

  /// 解码进度，范围 [0.0, 1.0]。
  double get progress {
    if (_numChunks == null || _numChunks == 0) return 0.0;
    return _recoveredCount / _numChunks!;
  }

  /// 解码得到的原始数据。
  ///
  /// [isComplete] 为 true 前返回 null。
  Uint8List? get decodedData {
    if (!_complete) return null;
    final builder = BytesBuilder(copy: false);
    for (final chunk in _recovered) {
      builder.add(chunk!);
    }
    // 剔掉最后一块的零字节填充，恢复原始长度
    return builder.toBytes().sublist(0, _totalLength!);
  }

  /// 投入一个接收到的包进行解码。
  ///
  /// 解码完成时返回 true（同 [isComplete]）。
  bool addPacket(FountainPacket packet) {
    if (_complete) return true; // 已完成，忽略后续包

    if (!_initialized) {
      _initialize(packet); // 用第一个包初始化元信息
    } else if (!_matchesStream(packet)) {
      return false; // 不属于当前数据流，忽略
    }

    // 还原该包引用的源块下标（必须与编码器逻辑完全一致）
    final indices = _deriveIndices(packet.seqNo, packet.degree, _numChunks!);
    final data = Uint8List.fromList(packet.data);

    // 将已恢复的块从载荷中 XOR 消除，收集未尚确定的块下标
    final pending = <int>[];
    for (final idx in indices) {
      final recovered = _recovered[idx];
      if (recovered != null) {
        _xorInPlace(data, recovered); // 抵消已知尾部
      } else {
        pending.add(idx); // 还不知道这个块
      }
    }

    if (pending.isEmpty) return _complete; // 全冗余包，不提供新信息

    if (pending.length == 1) {
      // 度数降至 1，可直接恢复包含的唯一未知块
      _recoverBlock(pending[0], data);
      _propagate(); // 站起级联传播
    } else {
      // 度数还 > 1，加入活跃包列表等待后续传播
      _active.add(_ActivePacket(pending, data));
    }

    return _complete;
  }

  /// 重置解码器，准备接收下一个数据流。
  void reset() {
    _totalLength = null;
    _numChunks = null;
    _chunkSize = null;
    _recovered = [];
    _recoveredCount = 0;
    _active.clear();
    _propagationQueue.clear();
    _initialized = false;
    _complete = false;
  }

  // ---------------------------------------------------------------------------
  // 内部辅助方法
  // ---------------------------------------------------------------------------

  /// 从第一个包初始化数据流元信息（大小、块数、块大小）。
  void _initialize(FountainPacket pkt) {
    _totalLength = pkt.totalLength;
    _numChunks = pkt.numChunks;
    _chunkSize = pkt.chunkSize;
    _recovered = List<Uint8List?>.filled(_numChunks!, null);
    _initialized = true;
  }

  /// 检测包是否属于当前数据流（元信息必须完全一致）。
  bool _matchesStream(FountainPacket pkt) =>
      pkt.numChunks == _numChunks &&
      pkt.chunkSize == _chunkSize &&
      pkt.totalLength == _totalLength;

  /// 标记一个源块已恢复，并将其加入传播队列。
  void _recoverBlock(int index, Uint8List data) {
    if (_recovered[index] != null) return; // 已恢复，跳过
    _recovered[index] = Uint8List.fromList(data);
    _recoveredCount++;
    _propagationQueue.add(index); // 入队，等待传播
    if (_recoveredCount == _numChunks) {
      _complete = true; // 所有块均已恢复，完成！
    }
  }

  /// BFS 传播：将新恢复的块从所有引用它的活跃包中 XOR 剔掉。
  void _propagate() {
    while (_propagationQueue.isNotEmpty) {
      final recoveredIdx = _propagationQueue.removeFirst();
      final resolved = <_ActivePacket>[]; // 本轮可移除的活跃包

      for (final pkt in _active) {
        // 如果该包不引用刺恢复的块，跳过
        if (!pkt.indices.remove(recoveredIdx)) continue;

        // XOR 剔除已恢复的块
        _xorInPlace(pkt.data, _recovered[recoveredIdx]!);

        if (pkt.indices.length == 1) {
          // 度数降为 1，可直接恢复唯一剩余块
          final newIdx = pkt.indices.first;
          if (_recovered[newIdx] == null) {
            _recoverBlock(newIdx, pkt.data);
          }
          resolved.add(pkt);
        } else if (pkt.indices.isEmpty) {
          // 充分兑余，可將其移除
          resolved.add(pkt);
        }
      }

      // 移除已处理完成的活跃包
      for (final pkt in resolved) {
        _active.remove(pkt);
      }

      if (_complete) return; // 已完成，早退出
    }
  }

  /// 为指定序列号的包重新推导源块下标。
  /// 必须与 [FountainEncoder.nextPacket] 中的逻辑严格对应：种子 = seqNo ^ 0xDEADBEEF。
  static List<int> _deriveIndices(int seqNo, int degree, int numChunks) {
    final indexRng = Random(seqNo ^ 0xDEADBEEF);
    return _sampleIndices(indexRng, degree, numChunks);
  }

  /// 部分 Fisher-Yates 洗牌：从 [0, numChunks) 中无重复采样 [degree] 个下标。
  static List<int> _sampleIndices(Random rng, int degree, int numChunks) {
    if (degree >= numChunks) return List.generate(numChunks, (i) => i);

    final pool = List<int>.generate(numChunks, (i) => i);
    // 部分 Fisher-Yates 洗牌，只交换 degree 次
    for (int i = 0; i < degree; i++) {
      final j = i + rng.nextInt(numChunks - i);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return pool.sublist(0, degree);
  }

  /// 将 [src] 逐字节 XOR 到 [dst] 中（就地操作）。
  static void _xorInPlace(Uint8List dst, Uint8List src) {
    final len = dst.length < src.length ? dst.length : src.length;
    for (int i = 0; i < len; i++) {
      dst[i] ^= src[i];
    }
  }
}

// ---------------------------------------------------------------------------
// 解码过程中的可变数据包包装器
// ---------------------------------------------------------------------------
/// 代表一个尚未完全解码的活跃数据包，记录其仍未确定的源块下标集合。
class _ActivePacket {
  /// 当前还未被 XOR 消除的源块下标集合（度数 = indices.length）
  final Set<int> indices;

  /// 经过历次 XOR 消除后的剩余载荷
  final Uint8List data;

  _ActivePacket(List<int> indices, this.data) : indices = indices.toSet();
}
