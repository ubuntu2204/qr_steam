import 'dart:math';
import 'dart:typed_data';

import 'raptorq_packet.dart';

/// RaptorQ-inspired 编码器。
///
/// 相比 LT 码改进：
/// 1. 先发送所有系统符号（原始块），接收端可直接用前 k 个包恢复。
/// 2. 之后发送 LDPC 修复符号（XOR 组合），允许对抗丢帧。
/// 3. 修复符号使用基于 seqNo 的伪随机选择，覆盖范围比 LT 码均匀。
///
/// 实际开销：只需 k + ε 个包即可以高概率解码（ε ≈ k * 0.05）。
class RaptorQEncoder {
  static const int defaultChunkSize = 300;

  final Uint8List _data;
  final int _chunkSize;
  late final int _numChunks;
  late final List<Uint8List> _chunks;
  late final int _repairPerCycle;
  late final int _cycleLength;

  int _seqNo = 0;
  // 使用循环发送窗口，避免接收端后加入时永远收不到系统符号。
  // 一个窗口内先发送系统符号，再发送少量修复符号。

  RaptorQEncoder(this._data, {int chunkSize = defaultChunkSize})
      : _chunkSize = chunkSize {
    assert(_data.isNotEmpty);
    assert(chunkSize > 0 && chunkSize <= 0xFFFF);
    _numChunks = (_data.length + chunkSize - 1) ~/ chunkSize;
    _chunks = _splitData();
    _repairPerCycle = max(2, (_numChunks * 0.2).ceil());
    _cycleLength = _numChunks + _repairPerCycle;
  }

  int get numChunks => _numChunks;
  int get chunkSize => _chunkSize;
  int get dataLength => _data.length;

  /// 生成下一个编码包。
  /// - seqNo < numChunks: 发送系统符号
  /// - seqNo >= numChunks: 发送修复符号
  ///
  /// 注意：seqNo 在循环窗口内取值 [0, cycleLength)，并周期性重复。
  /// 这样接收端即使中途加入，也能在后续窗口中拿到系统符号。
  RaptorQPacket nextPacket() {
    final seq = _seqNo;
    _seqNo = (_seqNo + 1) % _cycleLength;

    if (seq < _numChunks) {
      // 系统符号：直接发送第 seq 个原始块
      return RaptorQPacket(
        totalLength: _data.length,
        numChunks: _numChunks,
        chunkSize: _chunkSize,
        seqNo: seq,
        isRepair: false,
        degree: 1,
        data: Uint8List.fromList(_chunks[seq]),
      );
    } else {
      // 修复符号：伪随机选取 2~4 个块 XOR
      final rng = Random(seq ^ 0xA5B2C3D4);
      // 修复符号度数分布：较高度数覆盖面更广，更好地对抗突发丢帧
      final maxDeg = min(4, _numChunks);
      final degree = maxDeg == 1 ? 1 : (rng.nextInt(maxDeg - 1) + 2);
      final indices = _sampleIndices(rng, degree, _numChunks);

      final xorData = Uint8List(_chunkSize);
      xorData.setRange(0, _chunkSize, _chunks[indices[0]]);
      for (int i = 1; i < degree; i++) {
        _xorInPlace(xorData, _chunks[indices[i]]);
      }

      return RaptorQPacket(
        totalLength: _data.length,
        numChunks: _numChunks,
        chunkSize: _chunkSize,
        seqNo: seq,
        isRepair: true,
        degree: degree,
        data: xorData,
      );
    }
  }

  Stream<RaptorQPacket> encode() async* {
    while (true) {
      yield nextPacket();
    }
  }

  List<Uint8List> _splitData() {
    final chunks = <Uint8List>[];
    for (int i = 0; i < _numChunks; i++) {
      final start = i * _chunkSize;
      final end = (start + _chunkSize).clamp(0, _data.length);
      final chunk = Uint8List(_chunkSize);
      chunk.setRange(0, end - start, _data, start);
      chunks.add(chunk);
    }
    return chunks;
  }

  static List<int> _sampleIndices(Random rng, int degree, int numChunks) {
    if (degree >= numChunks) return List.generate(numChunks, (i) => i);
    final pool = List<int>.generate(numChunks, (i) => i);
    for (int i = 0; i < degree; i++) {
      final j = i + rng.nextInt(numChunks - i);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return pool.sublist(0, degree);
  }

  static void _xorInPlace(Uint8List dst, Uint8List src) {
    final len = min(dst.length, src.length);
    for (int i = 0; i < len; i++) {
      dst[i] ^= src[i];
    }
  }
}
