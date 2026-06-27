import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'demo_slides.dart';
import 'slide_item.dart';
import 'video_slide_widget.dart';

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
  Timer? _timer;

  // Platform states
  bool _isDefaultLauncher = false;
  bool _showSettings = false;
  bool _isMuted = false;

  // Custom states
  PlaybackMode _playbackMode = PlaybackMode.all;
  final _addUrlController = TextEditingController();
  SlideType _addType = SlideType.networkImage;
  int _addDuration = 5;

  List<SlideItem> get _activeSlides {
    return _slides.where((slide) {
      if (!slide.isActive) return false;
      switch (_playbackMode) {
        case PlaybackMode.all:
          return true;
        case PlaybackMode.imagesOnly:
          return !slide.isVideo;
        case PlaybackMode.videosOnly:
          return slide.isVideo;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slides = buildShuffledDemoSlides();
    // 5000 is a safe start page to allow scrolling backwards if desired, aligning to index 0.
    _pageController = PageController(initialPage: 5000);
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheImages();
      _armTimer();
    });
  }

  void _precacheImages() {
    for (final slide in _slides) {
      if (slide.type == SlideType.assetImage) {
        precacheImage(AssetImage(slide.assetPath), context);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _timer?.cancel();
    _addUrlController.dispose();
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
      final hasDismissed = await _platform.invokeMethod<bool>('hasDismissedSettings') ?? false;
      setState(() {
        _isDefaultLauncher = isDefault;
        if (isDefault) {
          _showSettings = false;
          if (!hasDismissed) {
            _platform.invokeMethod('setDismissedSettings', {'dismissed': true});
          }
        } else if (!hasDismissed) {
          _showSettings = true;
        }
      });
    } on PlatformException catch (e) {
      debugPrint("Error loading platform settings: $e");
    }
  }

  Future<void> _dismissSettings() async {
    try {
      await _platform.invokeMethod('setDismissedSettings', {'dismissed': true});
    } on PlatformException catch (e) {
      debugPrint("Error saving settings dismissal: $e");
    }
    if (mounted) {
      setState(() {
        _showSettings = false;
      });
    }
  }

  Future<void> _openHomeSettings() async {
    try {
      await _platform.invokeMethod('openHomeSettings');
      await _dismissSettings();
    } on PlatformException catch (e) {
      debugPrint("Error opening home settings: $e");
    }
  }

  void _armTimer() {
    _timer?.cancel();
    final active = _activeSlides;
    if (!mounted || active.isEmpty) return;

    final index = _pageController.hasClients ? _pageController.page?.round() ?? 5000 : 5000;
    final currentSlide = active[index % active.length];

    _timer = Timer(Duration(seconds: currentSlide.duration), () {
      if (!mounted || _activeSlides.isEmpty) return;
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onTap() {
    if (_activeSlides.length <= 1) return;
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
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_showSettings) {
            _dismissSettings();
          } else if (!_isDefaultLauncher) {
            SystemNavigator.pop();
          }
        },
        child: Stack(
          children: [
            // 1. PageView for Slides
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              child: _activeSlides.isEmpty
                  ? const Center(
                      child: Text(
                        'No active slides matching filter',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      onPageChanged: (index) {
                        _armTimer();
                      },
                      itemBuilder: (context, index) {
                        final active = _activeSlides;
                        if (active.isEmpty) return const SizedBox();
                        final item = active[index % active.length];
                        return _buildSlide(item);
                      },
                    ),
            ),

            // 2. Control buttons (Top Right)
            Positioned(
              top: 20,
              right: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mute / Unmute Button
                  ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.12),
                        child: IconButton(
                          icon: Icon(
                            _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () {
                            setState(() {
                              _isMuted = !_isMuted;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Settings Button
                  ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.12),
                        child: IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white, size: 26),
                          onPressed: () {
                            if (_showSettings) {
                              _dismissSettings();
                            } else {
                              setState(() {
                                _showSettings = true;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Settings Overlay Panel
            if (_showSettings)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _dismissSettings,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {}, // Prevent taps inside from dismissing dialog
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.height * 0.9,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0F1A).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 35,
                                    offset: const Offset(0, 15),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeader(),
                                  const Divider(color: Colors.white24, height: 24),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Left Panel: Controls
                                        Expanded(
                                          flex: 5,
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                _buildLauncherSetting(),
                                                const SizedBox(height: 12),
                                                _buildPlaybackModeSetting(),
                                                const SizedBox(height: 12),
                                                _buildAddSlideSetting(),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const VerticalDivider(width: 24, color: Colors.white12),
                                        // Right Panel: Slide List
                                        Expanded(
                                          flex: 6,
                                          child: _buildMediaManagerSetting(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(color: Colors.white24, height: 24),
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
                                          vertical: 12,
                                        ),
                                      ),
                                      onPressed: _dismissSettings,
                                      child: const Text(
                                        'Save & Close',
                                        style: TextStyle(
                                          fontSize: 15,
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF4E54C8).withValues(alpha: 0.2),
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
                'Set defaults, filter content types, and configure slot durations',
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
          onPressed: _dismissSettings,
        ),
      ],
    );
  }

  Widget _buildLauncherSetting() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDefaultLauncher
              ? Colors.greenAccent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
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
                    color: _isDefaultLauncher ? Colors.greenAccent : Colors.white.withValues(alpha: 0.5),
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
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
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

  Widget _buildPlaybackModeSetting() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Playback Filter',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildPlaybackModeBtn(PlaybackMode.all, 'All', Icons.all_inclusive),
              const SizedBox(width: 8),
              _buildPlaybackModeBtn(PlaybackMode.imagesOnly, 'Images', Icons.image),
              const SizedBox(width: 8),
              _buildPlaybackModeBtn(PlaybackMode.videosOnly, 'Videos', Icons.videocam),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackModeBtn(PlaybackMode mode, String label, IconData icon) {
    final isSelected = _playbackMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _playbackMode = mode;
          });
          _armTimer();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4E54C8).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF8E94F2) : Colors.white12,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF8E94F2) : Colors.white54,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddSlideSetting() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Custom Media URL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Enter image or video URL...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Type: ', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Image', style: TextStyle(fontSize: 11)),
                selected: _addType == SlideType.networkImage,
                onSelected: (val) {
                  if (val) setState(() => _addType = SlideType.networkImage);
                },
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Video', style: TextStyle(fontSize: 11)),
                selected: _addType == SlideType.networkVideo,
                onSelected: (val) {
                  if (val) setState(() => _addType = SlideType.networkVideo);
                },
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Duration: ', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.remove, color: Colors.white60, size: 16),
                onPressed: () {
                  if (_addDuration > 1) {
                    setState(() => _addDuration--);
                  }
                },
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_addDuration sec',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white60, size: 16),
                onPressed: () {
                  if (_addDuration < 60) {
                    setState(() => _addDuration++);
                  }
                },
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add to Slideshow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8E94F2),
                foregroundColor: const Color(0xFF0F0F1A),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () {
                final url = _addUrlController.text.trim();
                if (url.isEmpty) return;

                final newItem = SlideItem(
                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                  type: _addType,
                  assetPath: url,
                  duration: _addDuration,
                  isActive: true,
                );

                setState(() {
                  _slides.add(newItem);
                  _addUrlController.clear();
                });
                _armTimer();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Custom slide added!'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaManagerSetting() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Manage & Order Slides',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Drag items or toggle',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _slides.isEmpty
                ? const Center(
                    child: Text(
                      'No slides available.\nAdd some or reset.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: _slides.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = _slides.removeAt(oldIndex);
                        _slides.insert(newIndex, item);
                      });
                      _armTimer();
                    },
                    itemBuilder: (context, index) {
                      final item = _slides[index];
                      return _buildSlideManagerItem(item, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideManagerItem(SlideItem item, int index) {
    Widget thumbnail;
    if (item.type == SlideType.assetImage) {
      thumbnail = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.asset(
          item.assetPath,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 24, color: Colors.white38),
        ),
      );
    } else if (item.type == SlideType.networkImage) {
      thumbnail = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          item.assetPath,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.cloud_queue, size: 24, color: Colors.white38),
        ),
      );
    } else if (item.type == SlideType.networkVideo) {
      thumbnail = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF8E94F2).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.play_circle_outline, size: 20, color: Color(0xFF8E94F2)),
      );
    } else {
      thumbnail = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.code, size: 20, color: Colors.white54),
      );
    }

    final isURL = item.type == SlideType.networkImage || item.type == SlideType.networkVideo;
    final name = isURL
        ? (item.assetPath.split('/').last.split('?').first)
        : item.assetPath.split('/').last;

    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isActive
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.01),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator, color: Colors.white30, size: 18),
              ),
              const SizedBox(width: 8),
              thumbnail,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: item.isActive ? Colors.white : Colors.white30,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _slides.removeAt(index);
                  });
                  _armTimer();
                },
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 26),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.type.name.replaceAll('network', 'Live ').replaceAll('asset', 'Local '),
                  style: TextStyle(
                    color: item.isActive ? Colors.white60 : Colors.white24,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 12, color: Colors.white54),
                    onPressed: !item.isActive
                        ? null
                        : () {
                            if (item.duration > 1) {
                              setState(() {
                                _slides[index] = item.copyWith(duration: item.duration - 1);
                              });
                              _armTimer();
                            }
                          },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    alignment: Alignment.center,
                    child: Text(
                      '${item.duration}s',
                      style: TextStyle(
                        color: item.isActive ? const Color(0xFF8E94F2) : Colors.white30,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 12, color: Colors.white54),
                    onPressed: !item.isActive
                        ? null
                        : () {
                            if (item.duration < 60) {
                              setState(() {
                                _slides[index] = item.copyWith(duration: item.duration + 1);
                              });
                              _armTimer();
                            }
                          },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: item.isActive,
                  activeThumbColor: const Color(0xFF8E94F2),
                  onChanged: (val) {
                    setState(() {
                      _slides[index] = item.copyWith(isActive: val);
                    });
                    _armTimer();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(SlideItem item) {
    switch (item.type) {
      case SlideType.assetSvg:
        return SvgPicture.asset(
          item.assetPath,
          key: ValueKey(item.id),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      case SlideType.assetImage:
        return Image.asset(
          item.assetPath,
          key: ValueKey(item.id),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(item.assetPath),
        );
      case SlideType.networkImage:
        return Image.network(
          item.assetPath,
          key: ValueKey(item.id),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E94F2)),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(item.assetPath),
        );
      case SlideType.networkVideo:
        return VideoSlideWidget(
          key: ValueKey(item.id),
          url: item.assetPath,
          isMuted: _isMuted,
        );
    }
  }

  Widget _buildErrorPlaceholder(String path) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.white24, size: 64),
            const SizedBox(height: 12),
            Text(
              'Could not load media:\n$path',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

enum PlaybackMode { all, imagesOnly, videosOnly }
