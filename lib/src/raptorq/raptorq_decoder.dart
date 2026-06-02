import 'dart:math';
import 'dart:typed_data';

import 'raptorq_packet.dart';

/// RaptorQ-inspired 解码器。
///
/// 解码策略：
/// 1. 收到系统符号（原始块）时直接存储。
/// 2. 收到修复符号时，用已知块抵消后，若度数降为 1 则恢复未知块（与 LT 码相同）。
/// 3. 当所有 k 个原始块都被恢复后，解码完成。
class RaptorQDecoder {
  int? _totalLength;
  int? _numChunks;
  int? _chunkSize;

  late List<Uint8List?> _recovered;
  int _recoveredCount = 0;
  int _acceptedPacketCount = 0;
  final Set<int> _seenSeqNos = <int>{};
  final List<_ActiveRepair> _activeRepairs = [];
  bool _initialized = false;
  bool _complete = false;

  bool get isComplete => _complete;
  int get recoveredCount => _recoveredCount;
  int get receivedPacketCount => _acceptedPacketCount;
  int? get totalChunks => _numChunks;

  double get progress {
    if (_numChunks == null || _numChunks == 0) return 0.0;
    if (_complete) return 1.0;
    return (_recoveredCount / _numChunks!).clamp(0.0, 0.98);
  }

  Uint8List? get decodedData {
    if (!_complete) return null;
    final builder = BytesBuilder(copy: false);
    for (final chunk in _recovered) {
      builder.add(chunk!);
    }
    return builder.toBytes().sublist(0, _totalLength!);
  }

  bool addPacket(RaptorQPacket packet) {
    if (_complete) return true;

    if (!_initialized) {
      _initialize(packet);
    } else if (!_matchesStream(packet)) {
      return false;
    }

    if (!_seenSeqNos.add(packet.seqNo)) return _complete;
    _acceptedPacketCount++;

    if (!packet.isRepair) {
      // 系统符号：直接存储对应源块（seqNo == block index）
      final idx = packet.seqNo;
      if (idx < _numChunks! && _recovered[idx] == null) {
        _recovered[idx] = Uint8List.fromList(packet.data);
        _recoveredCount++;
        _propagate(idx);
        _checkComplete();
      }
    } else {
      // 修复符号：重新计算引用的块下标
      final indices = _deriveIndices(packet.seqNo, packet.degree, _numChunks!);
      final data = Uint8List.fromList(packet.data);

      // 消除已知块
      final pending = <int>[];
      for (final idx in indices) {
        final r = _recovered[idx];
        if (r != null) {
          _xorInPlace(data, r);
        } else {
          pending.add(idx);
        }
      }

      if (pending.isEmpty) return _complete;

      if (pending.length == 1) {
        _recoverBlock(pending[0], data);
        _checkComplete();
      } else {
        _activeRepairs.add(_ActiveRepair(pending, data));
      }
    }

    return _complete;
  }

  void reset() {
    _totalLength = null;
    _numChunks = null;
    _chunkSize = null;
    _recovered = [];
    _recoveredCount = 0;
    _acceptedPacketCount = 0;
    _seenSeqNos.clear();
    _activeRepairs.clear();
    _initialized = false;
    _complete = false;
  }

  void _initialize(RaptorQPacket pkt) {
    _totalLength = pkt.totalLength;
    _numChunks = pkt.numChunks;
    _chunkSize = pkt.chunkSize;
    _recovered = List<Uint8List?>.filled(_numChunks!, null);
    _initialized = true;
  }

  bool _matchesStream(RaptorQPacket pkt) =>
      pkt.totalLength == _totalLength &&
      pkt.numChunks == _numChunks &&
      pkt.chunkSize == _chunkSize;

  void _recoverBlock(int idx, Uint8List data) {
    if (_recovered[idx] != null) return;
    _recovered[idx] = Uint8List.fromList(data);
    _recoveredCount++;
    _propagate(idx);
  }

  void _propagate(int newIdx) {
    bool progress = true;
    while (progress) {
      progress = false;
      for (int i = _activeRepairs.length - 1; i >= 0; i--) {
        final repair = _activeRepairs[i];
        if (repair.pending.remove(newIdx)) {
          _xorInPlace(repair.data, _recovered[newIdx]!);
          if (repair.pending.length == 1) {
            final only = repair.pending.first;
            _activeRepairs.removeAt(i);
            if (_recovered[only] == null) {
              _recoverBlock(only, repair.data);
              progress = true;
            }
          } else if (repair.pending.isEmpty) {
            _activeRepairs.removeAt(i);
          }
        }
      }
    }
  }

  void _checkComplete() {
    if (_recoveredCount == _numChunks) _complete = true;
  }

  static List<int> _deriveIndices(int seqNo, int degree, int numChunks) {
    final rng = Random(seqNo ^ 0xA5B2C3D4);
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

class _ActiveRepair {
  final Set<int> pending;
  final Uint8List data;

  _ActiveRepair(List<int> pendingList, this.data)
      : pending = Set<int>.from(pendingList);
}
