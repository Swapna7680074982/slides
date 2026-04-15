/// One slide: bundled asset path (SVG under [assets/demo/]).
class SlideItem {
  const SlideItem.asset(this.assetPath);

  final String assetPath;

  bool get isSvg => assetPath.toLowerCase().endsWith('.svg');
}
