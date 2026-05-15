import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_steam/qr_steam.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Soliton distribution
  // ---------------------------------------------------------------------------
  group('RobustSoliton', () {
    test('sampleDegree returns value in [1, k]', () {
      final rsd = RobustSoliton(k: 50);
      final rng = Random(42);
      for (int i = 0; i < 1000; i++) {
        final d = rsd.sampleDegree(rng);
        expect(d, greaterThanOrEqualTo(1));
        expect(d, lessThanOrEqualTo(50));
      }
    });

    test('average degree is reasonable (< k/2)', () {
      final k = 100;
      final rsd = RobustSoliton(k: k);
      final rng = Random(0);
      int total = 0;
      const samples = 10000;
      for (int i = 0; i < samples; i++) {
        total += rsd.sampleDegree(rng);
      }
      final avg = total / samples;
      // Average degree should be well below k/2 for LT codes to work
      expect(avg, lessThan(k / 2));
    });
  });

  // ---------------------------------------------------------------------------
  // FountainPacket serialisation
  // ---------------------------------------------------------------------------
  group('FountainPacket', () {
    test('round-trips through toBytes / fromBytes', () {
      final data = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final pkt = FountainPacket(
        totalLength: 1234,
        numChunks: 5,
        chunkSize: 300,
        seqNo: 42,
        degree: 3,
        data: data,
      );

      final restored = FountainPacket.fromBytes(pkt.toBytes());
      expect(restored.totalLength, pkt.totalLength);
      expect(restored.numChunks, pkt.numChunks);
      expect(restored.chunkSize, pkt.chunkSize);
      expect(restored.seqNo, pkt.seqNo);
      expect(restored.degree, pkt.degree);
      expect(restored.data, pkt.data);
    });

    test('round-trips through base64url', () {
      final data = Uint8List.fromList(List.generate(100, (i) => i));
      final pkt = FountainPacket(
        totalLength: 100,
        numChunks: 1,
        chunkSize: 100,
        seqNo: 7,
        degree: 1,
        data: data,
      );

      final restored = FountainPacket.fromBase64Url(pkt.toBase64Url());
      expect(restored.seqNo, 7);
      expect(restored.data, pkt.data);
    });

    test('fromBytes throws on bad magic', () {
      final bytes = Uint8List(30);
      expect(() => FountainPacket.fromBytes(bytes), throwsFormatException);
    });
  });

  // ---------------------------------------------------------------------------
  // Encode / decode round-trip
  // ---------------------------------------------------------------------------
  group('FountainEncoder + FountainDecoder', () {
    Uint8List _makeData(int size) =>
        Uint8List.fromList(List.generate(size, (i) => (i * 31 + 7) % 256));

    void _runRoundTrip({
      required int dataSize,
      required int chunkSize,
      double overheadFactor = 2.5,
    }) {
      final original = _makeData(dataSize);
      final encoder = FountainEncoder(original, chunkSize: chunkSize);
      final decoder = FountainDecoder();

      final maxPackets = (encoder.numChunks * overheadFactor)
          .ceil()
          .clamp(encoder.numChunks + 5, 5000);

      bool decoded = false;
      for (int i = 0; i < maxPackets && !decoded; i++) {
        decoded = decoder.addPacket(encoder.nextPacket());
      }

      expect(decoded, isTrue,
          reason: 'Failed to decode $dataSize bytes, chunkSize=$chunkSize '
              'within $maxPackets packets');
      expect(decoder.decodedData, equals(original),
          reason: 'Decoded data does not match original');
    }

    test('tiny data (< 1 chunk)', () {
      _runRoundTrip(dataSize: 50, chunkSize: 100);
    });

    test('data exactly one chunk', () {
      _runRoundTrip(dataSize: 200, chunkSize: 200);
    });

    test('small data (10 chunks)', () {
      _runRoundTrip(dataSize: 1000, chunkSize: 100);
    });

    test('medium data (50 chunks)', () {
      _runRoundTrip(dataSize: 5000, chunkSize: 100);
    });

    test('large data (100 chunks)', () {
      _runRoundTrip(dataSize: 30000, chunkSize: 300);
    });

    test('decoder handles duplicate packets gracefully', () {
      final data = _makeData(600);
      final encoder = FountainEncoder(data, chunkSize: 100);
      final decoder = FountainDecoder();

      // Send first packet 10 times, then keep going
      final first = encoder.nextPacket();
      for (int i = 0; i < 10; i++) {
        decoder.addPacket(first);
      }

      bool done = false;
      for (int i = 0; i < 500 && !done; i++) {
        done = decoder.addPacket(encoder.nextPacket());
      }
      expect(done, isTrue);
      expect(decoder.decodedData, equals(data));
    });

    test('decoder reset allows reuse', () {
      final data = _makeData(500);
      final decoder = FountainDecoder();

      // First pass
      final enc1 = FountainEncoder(data, chunkSize: 100);
      bool done = false;
      for (int i = 0; i < 300 && !done; i++) {
        done = decoder.addPacket(enc1.nextPacket());
      }
      expect(done, isTrue);

      // Reset and decode again
      decoder.reset();
      expect(decoder.isComplete, isFalse);
      expect(decoder.progress, 0.0);

      final enc2 = FountainEncoder(data, chunkSize: 100);
      done = false;
      for (int i = 0; i < 300 && !done; i++) {
        done = decoder.addPacket(enc2.nextPacket());
      }
      expect(done, isTrue);
      expect(decoder.decodedData, equals(data));
    });

    test('progress advances monotonically', () {
      final data = _makeData(3000);
      final encoder = FountainEncoder(data, chunkSize: 150);
      final decoder = FountainDecoder();

      double lastProgress = -1;
      for (int i = 0; i < 200; i++) {
        decoder.addPacket(encoder.nextPacket());
        expect(decoder.progress, greaterThanOrEqualTo(lastProgress));
        lastProgress = decoder.progress;
        if (decoder.isComplete) break;
      }
    });
  });

  // ---------------------------------------------------------------------------
  // FountainEncoder helpers
  // ---------------------------------------------------------------------------
  group('FountainEncoder', () {
    test('numChunks is correct', () {
      final enc = FountainEncoder(Uint8List(301), chunkSize: 100);
      expect(enc.numChunks, 4);
    });

    test('encodeN produces n packets', () {
      final enc = FountainEncoder(Uint8List(500), chunkSize: 100);
      expect(enc.encodeN(20).length, 20);
    });

    test('packet data length equals chunkSize', () {
      final enc = FountainEncoder(Uint8List(500), chunkSize: 100);
      final pkt = enc.nextPacket();
      expect(pkt.data.length, 100);
    });
  });
}
