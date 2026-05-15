import 'dart:io';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/receiver_page.dart';
import 'pages/sender_page.dart';

void main() {
  // 确保 Flutter 引擎初始化（平台插件在 runApp 前需要）
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QrSteamApp());
}

/// 应用根组件。
/// 根据当前运行平台自动路由到对应页面：
/// - Windows  → 发送端（SenderPage）
/// - Android  → 接收端（ReceiverPage）
/// - 其他平台 → 首页（HomePage）
class QrSteamApp extends StatelessWidget {
  const QrSteamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Steam Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // 平台析分到对应初始页面
      home: _initialPage(),
      routes: {
        '/home': (_) => const HomePage(),
        '/sender': (_) => const SenderPage(),
        '/receiver': (_) => const ReceiverPage(),
      },
    );
  }

  /// 根据运行平台返回对应的初始页面。
  Widget _initialPage() {
    if (Platform.isWindows) return const SenderPage(); // Windows 直接进发送页
    if (Platform.isAndroid) return const ReceiverPage(); // Android 直接进接收页
    return const HomePage(); // 其他平台显示首页导航
  }
}
