import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'demo_slides.dart';
import 'slide_item.dart';

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

class _SlideShowPageState extends State<SlideShowPage> with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.example.slides/settings');

  late List<SlideItem> _slides;
  late PageController _pageController;
  int _intervalSeconds = 2;
  Timer? _timer;

  // Platform states
  bool _isDefaultLauncher = false;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slides = buildShuffledDemoSlides();
    // 5000 is a safe start page to allow scrolling backwards if desired, aligning to index 0.
    _pageController = PageController(initialPage: 5000);
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final isDefault = await _platform.invokeMethod<bool>('isDefaultLauncher') ?? false;
      setState(() {
        _isDefaultLauncher = isDefault;
        // If settings have never been enabled/configured, auto-show settings screen to guide the user.
        if (!isDefault) {
          _showSettings = true;
        }
      });
    } on PlatformException catch (e) {
      debugPrint("Error loading platform settings: $e");
    }
  }

  Future<void> _openHomeSettings() async {
    try {
      await _platform.invokeMethod('openHomeSettings');
    } on PlatformException catch (e) {
      debugPrint("Error opening home settings: $e");
    }
  }

  void _armTimer() {
    _timer?.cancel();
    if (!mounted || _slides.length <= 1) return;
    _timer = Timer.periodic(Duration(seconds: _intervalSeconds), (_) {
      if (!mounted || _slides.isEmpty) return;
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onTap() {
    if (_slides.length <= 1) return;
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Vertical PageView for Slides
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemBuilder: (context, index) {
                if (_slides.isEmpty) return const SizedBox();
                final item = _slides[index % _slides.length];
                return _buildSlide(item);
              },
            ),
          ),

          // 2. Settings button (Top Right)
          Positioned(
            top: 20,
            right: 20,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.white.withOpacity(0.12),
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white, size: 26),
                    onPressed: () {
                      setState(() {
                        _showSettings = !_showSettings;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),

          // 3. Settings Overlay Panel
          if (_showSettings)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showSettings = false;
                  });
                },
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () {}, // Prevent taps inside from dismissing dialog
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.85,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.85,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F0F1A).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.6),
                                  blurRadius: 35,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeader(),
                                  const Divider(color: Colors.white24, height: 32),
                                  _buildLauncherSetting(),
                                  const SizedBox(height: 16),
                                  _buildSpeedSetting(),
                                  const Divider(color: Colors.white24, height: 32),
                                  Center(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4E54C8),
                                        foregroundColor: Colors.white,
                                        elevation: 4,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 40,
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _showSettings = false;
                                        });
                                      },
                                      child: const Text(
                                        'Save & Close',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF4E54C8).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.settings_suggest, color: Color(0xFF8E94F2), size: 28),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Slideshow Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Set defaults and auto-start configurations',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white60, size: 22),
          onPressed: () {
            setState(() {
              _showSettings = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildLauncherSetting() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDefaultLauncher
              ? Colors.greenAccent.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set Default Home Screen',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isDefaultLauncher
                      ? 'Slides is currently your default Home App. Tap Remove to change/clear this in device settings.'
                      : 'Make Slides the default Home App so it starts when turning on device',
                  style: TextStyle(
                    color: _isDefaultLauncher ? Colors.greenAccent : Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_isDefaultLauncher)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                    SizedBox(width: 4),
                    Text(
                      'Active',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    backgroundColor: Colors.redAccent.withOpacity(0.08),
                  ),
                  onPressed: _openHomeSettings,
                  icon: const Icon(Icons.settings_backup_restore, size: 16),
                  label: const Text(
                    'Remove',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4E54C8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: _openHomeSettings,
              child: const Text('Configure', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }



  Widget _buildSpeedSetting() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Auto-Scroll Interval',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4E54C8).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_intervalSeconds sec',
                  style: const TextStyle(
                    color: Color(0xFF8E94F2),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Adjust how long each slide displays before scrolling down to the next.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Slider(
            value: _intervalSeconds.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: const Color(0xFF4E54C8),
            inactiveColor: Colors.white12,
            onChanged: (val) {
              setState(() {
                _intervalSeconds = val.toInt();
              });
              _armTimer();
            },
          ),
        ],
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
