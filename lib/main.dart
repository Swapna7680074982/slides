import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'demo_slides.dart';
import 'slide_item.dart';

/// Slideshow from **bundled assets only**. Content is not read from USB.
///
/// **USB:** The Android manifest registers [USB_DEVICE_ATTACHED] so plugging in a
/// USB mass-storage device can **launch this already-installed app**. That is the only
/// USB-related behavior — no files are loaded from the stick in Dart.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const SlidesApp());
}

class SlidesApp extends StatelessWidget {
  const SlidesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slides',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1a1a2e),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SlideShowPage(),
    );
  }
}

class SlideShowPage extends StatefulWidget {
  const SlideShowPage({super.key});

  @override
  State<SlideShowPage> createState() => _SlideShowPageState();
}

class _SlideShowPageState extends State<SlideShowPage> {
  static const _intervalSeconds = 2;

  late List<SlideItem> _slides;
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _slides = buildShuffledDemoSlides();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  void _armTimer() {
    _timer?.cancel();
    if (!mounted || _slides.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: _intervalSeconds), (_) {
      if (!mounted || _slides.isEmpty) return;
      setState(() {
        _index = (_index + 1) % _slides.length;
      });
    });
  }

  void _onTap() {
    if (_slides.length <= 1) return;
    setState(() {
      _index = (_index + 1) % _slides.length;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _slides[_index];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _buildSlide(item),
        ),
      ),
    );
  }

  Widget _buildSlide(SlideItem item) {
    if (item.isSvg) {
      return SvgPicture.asset(
        item.assetPath,
        key: ValueKey(item.assetPath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Image.asset(
      item.assetPath,
      key: ValueKey(item.assetPath),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Could not load image',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
