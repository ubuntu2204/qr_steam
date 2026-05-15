import 'dart:math';

/// 鲁棒孤子分布（Robust Soliton Distribution，RSD），用于 LT 喷泉码。
///
/// RSD 用于为每个编码数据包选择「度数」（即异或几个源块）。
/// 相比理想孤子分布，RSD 在实际中具有更好的性能。
///
/// 参数说明：
/// - [k]     : 源数据块总数
/// - [c]     : 涟漪大小常数（默认 0.03，用于在开销和性能之间取得平衡）
/// - [delta] : 目标解码失败概率（默认 0.05，即允许 5% 的失败率）
class RobustSoliton {
  final int k; // 源块总数
  final double c; // 涟漪常数
  final double delta; // 失败概率上限

  /// 预先计算好的累积分布函数（CDF），用于逆变换采样。
  late final List<double> _cdf;

  RobustSoliton({
    required this.k,
    this.c = 0.03,
    this.delta = 0.05,
  }) : assert(k >= 1) {
    _buildCdf();
  }

  /// 构建归一化 CDF。
  ///
  /// 对每个度数 d（1 ≤ d ≤ k），计算理想孤子分布 ρ(d) 与鲁棒修正项 τ(d) 之和，
  /// 再归一化为概率分布，最后累积为 CDF 便于逆变换采样。
  void _buildCdf() {
    // r 控制「涟漪」——从高度数到低度数的额外概率质量
    final r = c * log(k / delta) * sqrt(k.toDouble());
    // rFloor 是发生概率「峰值」的度数（限制在 [1, k]）
    final rFloor = r.floor().clamp(1, k);

    final pmf = List<double>.filled(k + 1, 0.0); // 概率质量函数
    double total = 0.0;

    for (int d = 1; d <= k; d++) {
      // 理想孤子分布 ρ(d)：d=1 时为 1/k，其余为 1/(d*(d-1))
      final rhoD = d == 1 ? 1.0 / k : 1.0 / (d.toDouble() * (d - 1));

      // 鲁棒修正项 τ(d)
      double tauD = 0.0;
      if (d < rFloor) {
        // 对低度数增加额外概率，确保有足够的度数为 1 的包触发解码级联
        tauD = r / (k.toDouble() * d);
      } else if (d == rFloor) {
        // 在 rFloor 处集中额外的概率质量
        tauD = r * log(r / delta) / k.toDouble();
      }

      pmf[d] = rhoD + tauD;
      total += pmf[d];
    }

    // 归一化并累积为 CDF（_cdf[d] = P(degree ≤ d)）
    _cdf = List<double>.filled(k + 1, 0.0);
    double cumulative = 0.0;
    for (int d = 1; d <= k; d++) {
      cumulative += pmf[d] / total;
      _cdf[d] = cumulative;
    }
  }

  /// 使用逆变换采样从分布中采样一个度数值。
  ///
  /// 生成 [0,1) 均匀随机数 u，返回满足 CDF[d] ≥ u 的最小 d。
  int sampleDegree(Random rng) {
    final u = rng.nextDouble();
    for (int d = 1; d <= k; d++) {
      if (u <= _cdf[d]) return d;
    }
    return k; // 浮点误差兜底
  }
}
