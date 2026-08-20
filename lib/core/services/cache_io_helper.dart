import 'cache_io_helper_stub.dart';
import 'cache_io_helper_stub.dart'
    if (dart.library.io) 'cache_io_helper_io.dart'
    if (dart.library.html) 'cache_io_helper_web.dart' as impl;

export 'cache_io_helper_stub.dart';

CacheIoHelper getCacheIoHelper() => impl.createCacheIoHelper();
