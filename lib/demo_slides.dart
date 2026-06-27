import 'dart:math';

import 'slide_item.dart';

const kDemoAssetPaths = [
  'assets/demo/img.png',
  'assets/demo/img_3.png',
  'assets/demo/img_4.png',
  'assets/demo/img_evening.png',
  'assets/demo/img_morning.png',
  'assets/demo/img_night.png',
];

/// Curated demo slides including network videos and local images.
List<SlideItem> buildShuffledDemoSlides() {
  final List<SlideItem> items = [
    const SlideItem(
      id: 'demo_morning',
      type: SlideType.assetImage,
      assetPath: 'assets/demo/img_morning.png',
      duration: 4,
    ),
    const SlideItem(
      id: 'demo_video_forest',
      type: SlideType.networkVideo,
      assetPath: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      duration: 10,
    ),
    const SlideItem(
      id: 'demo_evening',
      type: SlideType.assetImage,
      assetPath: 'assets/demo/img_evening.png',
      duration: 4,
    ),
    const SlideItem(
      id: 'demo_video_lights',
      type: SlideType.networkVideo,
      assetPath: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      duration: 8,
    ),
    const SlideItem(
      id: 'demo_night',
      type: SlideType.assetImage,
      assetPath: 'assets/demo/img_night.png',
      duration: 4,
    ),
    const SlideItem(
      id: 'demo_img',
      type: SlideType.assetImage,
      assetPath: 'assets/demo/img.png',
      duration: 4,
    ),
    const SlideItem(
      id: 'demo_img_3',
      type: SlideType.assetImage,
      assetPath: 'assets/demo/img_3.png',
      duration: 4,
    ),
    const SlideItem(
      id: 'video1',
      type: SlideType.networkVideo,
      assetPath: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      duration: 10,
    ),

    const SlideItem(
      id: 'video3',
      type: SlideType.networkVideo,
      assetPath: 'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-1080p-30sec.mp4',
      duration: 15,
    ),


  ];
  return items..shuffle(Random());
}
