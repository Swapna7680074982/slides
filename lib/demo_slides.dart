import 'dart:math';

import 'slide_item.dart';

const kDemoAssetPaths = [
  'assets/demo/img.png',
  'assets/demo/img_3.png',
  'assets/demo/img_4.png',
  'assets/demo/img.png',
  'assets/demo/img_3.png',
  'assets/demo/img_4.png',
];

/// Random order for bundled demo slides.
List<SlideItem> buildShuffledDemoSlides() {
  final paths = List<String>.from(kDemoAssetPaths)..shuffle(Random());
  return paths.map(SlideItem.asset).toList();
}
