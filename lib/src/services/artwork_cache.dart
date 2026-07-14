import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class OtohaArtworkCache {
  OtohaArtworkCache._();

  static final CacheManager instance = CacheManager(
    Config(
      'otoha-artwork-v1',
      stalePeriod: const Duration(days: 21),
      maxNrOfCacheObjects: 300,
    ),
  );
}
