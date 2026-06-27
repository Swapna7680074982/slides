enum SlideType {
  assetImage,
  assetSvg,
  networkImage,
  networkVideo,
}

class SlideItem {
  final String id;
  final SlideType type;
  final String assetPath; // keeps the original field name for ease of use or transition
  final int duration; // duration in seconds for this slot
  final bool isActive;

  const SlideItem({
    required this.id,
    required this.type,
    required this.assetPath,
    required this.duration,
    this.isActive = true,
  });

  factory SlideItem.asset(String path, {int duration = 3}) {
    final isSvg = path.toLowerCase().endsWith('.svg');
    return SlideItem(
      id: path,
      type: isSvg ? SlideType.assetSvg : SlideType.assetImage,
      assetPath: path,
      duration: duration,
      isActive: true,
    );
  }

  bool get isSvg => type == SlideType.assetSvg;
  bool get isVideo => type == SlideType.networkVideo;

  SlideItem copyWith({
    String? id,
    SlideType? type,
    String? assetPath,
    int? duration,
    bool? isActive,
  }) {
    return SlideItem(
      id: id ?? this.id,
      type: type ?? this.type,
      assetPath: assetPath ?? this.assetPath,
      duration: duration ?? this.duration,
      isActive: isActive ?? this.isActive,
    );
  }
}
