import 'dart:math';
import 'dart:typed_data';

import 'fountain_packet.dart';
import 'soliton.dart';

/// LT（Luby Transform）喷泉码编码器。
///
/// 将输入 [data] 分割为 [numChunks] 个大小为 [chunkSize] 字节的源块，
/// 然后按照鲁棒孤子分布挑选度数，生成无限流的编码包。
/// 接收方收到约 1.05k 个包就能解码成功。
///
/// ```dart
/// final encoder = FountainEncoder(myBytes);
/// // 逐包获取：
/// final pkt = encoder.nextPacket();
/// // 或流式获取：
/// encoder.encode().take(100).forEach(sendOverNetwork);
/// ```
class FountainEncoder {
  /// 默认源块大小（字节）。
  ///
  /// 300 字节 → base64url 约 400 字符 → 在 ECC-M 条件下适入 QR 版本 ≤20。
  static const int defaultChunkSize = 300;

  final Uint8List _data; // 原始数据
  final int _chunkSize; // 单块字节数
  late final int _numChunks; // 源块总数 k
  late final List<Uint8List> _chunks; // 分割后的源块列表
  late final RobustSoliton _distribution; // 度数采样器

  /// 当前序列号，每生成一个包就自增
  int _seqNo = 0;

  FountainEncoder(this._data, {int chunkSize = defaultChunkSize})
      : _chunkSize = chunkSize {
    assert(_data.isNotEmpty, 'Data must not be empty');
    assert(chunkSize > 0 && chunkSize <= 0xFFFF, 'chunkSize must be 1..65535');

    // 向上取整除法计算块数
    _numChunks = (_data.length + chunkSize - 1) ~/ chunkSize;
    _chunks = _splitData();
    _distribution = RobustSoliton(k: _numChunks);
  }

  // ---------------------------------------------------------------------------
  // 公共 API
  // ---------------------------------------------------------------------------

  /// 源块总数 k。
  int get numChunks => _numChunks;

  /// 单个源块的字节数。
  int get chunkSize => _chunkSize;

  /// 原始数据的字节长度。
  int get dataLength => _data.length;

  /// 生成下一个编码 [FountainPacket]（序列无限，可循环播放）。
  FountainPacket nextPacket() {
    // 序列号限制在 uint32 范围内，防止溢出
    final seq = _seqNo++ & 0xFFFFFFFF;

    // 用序列号作为种子，从鲁棒孤子分布采样度数
    final degreeRng = Random(seq);
    final degree = _distribution.sampleDegree(degreeRng).clamp(1, _numChunks);

    // 用另一个派生种子采样源块下标，解码器可用同样方式复现而无需存储
    final indexRng = Random(seq ^ 0xDEADBEEF);
    final indices = _sampleIndices(indexRng, degree, _numChunks);

    // 将选定的源块逐字节 XOR 得到载荷
    final xorData = Uint8List(_chunkSize);
    xorData.setRange(0, _chunkSize, _chunks[indices[0]]); // 先复制第一块
    for (int i = 1; i < degree; i++) {
      _xorInPlace(xorData, _chunks[indices[i]]); // 依次 XOR 其余块
    }

    return FountainPacket(
      totalLength: _data.length,
      numChunks: _numChunks,
      chunkSize: _chunkSize,
      seqNo: seq,
      degree: degree,
      data: xorData,
    );
  }

  /// 无限异步流，持续生成编码包。
  Stream<FountainPacket> encode() async* {
    while (true) {
      yield nextPacket();
    }
  }

  /// 生成 [count] 个包（便于测试）。
  List<FountainPacket> encodeN(int count) =>
      List.generate(count, (_) => nextPacket());

  // ---------------------------------------------------------------------------
  // 内部辅助方法
  // ---------------------------------------------------------------------------

  /// 将原始数据分割为等长源块，最后一块用零字节填充。
  List<Uint8List> _splitData() {
    final chunks = <Uint8List>[];
    for (int i = 0; i < _numChunks; i++) {
      final start = i * _chunkSize;
      final end = (start + _chunkSize).clamp(0, _data.length);
      final chunk = Uint8List(_chunkSize); // 初始化为全零（尾部自动填充）
      chunk.setRange(0, end - start, _data, start);
      chunks.add(chunk);
    }
    return chunks;
  }

  /// 部分 Fisher-Yates 洗牌算法：从 [0, numChunks) 中无重复地采样 [degree] 个下标。
  static List<int> _sampleIndices(Random rng, int degree, int numChunks) {
    // 度数不小于块数时，直接返回所有下标
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

  /// 将 [src] 逐字节 XOR 到 [dst] 中（就地操作，两者长度应相同）。
  static void _xorInPlace(Uint8List dst, Uint8List src) {
    for (int i = 0; i < dst.length; i++) {
      dst[i] ^= src[i];
    }
  }
}
