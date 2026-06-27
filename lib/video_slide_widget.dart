import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoSlideWidget extends StatefulWidget {
  final String url;
  final bool isMuted;

  const VideoSlideWidget({super.key, required this.url, this.isMuted = false});

  @override
  State<VideoSlideWidget> createState() => _VideoSlideWidgetState();
}

class _VideoSlideWidgetState extends State<VideoSlideWidget> {
  VideoPlayerController? _controller;
  bool _hasError = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant VideoSlideWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initializePlayer();
    } else if (oldWidget.isMuted != widget.isMuted) {
      _controller?.setVolume(widget.isMuted ? 0.0 : 1.0);
    }
  }

  Future<void> _initializePlayer() async {
    // Clean up old controller if any
    final oldController = _controller;
    if (oldController != null) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
      });
      // Delay disposal to allow widget structure to update
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await oldController.dispose();
      });
    }

    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() {
        _hasError = true;
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      await controller.setLooping(true);
      await controller.play();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint("Error initializing video player: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_camera_back_outlined,
                color: Colors.white24,
                size: 64,
              ),
              SizedBox(height: 12),
              Text(
                'Could not stream video',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E94F2)),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Buffering live video...',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}
