import 'package:flutter/material.dart';

/// 首页，展示在非 Windows / Android 平台上，
/// 提供导航入口进入发送端或接收端演示。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Steam Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'QR Steam',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // 简介文字
            const Text(
              '通过动态 QR 码传输任意二进制数据（喷泉码 + AVIF/HEIC）',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // 发送端入口（途径 /sender）
            _DemoCard(
              icon: Icons.desktop_windows,
              title: '发送端（Windows）',
              description: '截图 → AVIF/HEIC 压缩 → 喷泉码动态 QR',
              onTap: () => Navigator.pushNamed(context, '/sender'),
            ),
            const SizedBox(height: 16),
            // 接收端入口（途径 /receiver）
            _DemoCard(
              icon: Icons.camera_alt,
              title: '接收端（Android）',
              description: '摄像头扫描 → 喷泉码解码 → 显示图片',
              onTap: () => Navigator.pushNamed(context, '/receiver'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 带图标的导航卡片。
class _DemoCard extends StatelessWidget {
  final IconData icon; // 卖点图标
  final String title; // 卡片标题
  final String description; // 概要描述
  final VoidCallback onTap; // 点击回调

  const _DemoCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: ListTile(
          leading: Icon(icon, size: 40),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(description),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: onTap,
        ),
      ),
    );
  }
}
