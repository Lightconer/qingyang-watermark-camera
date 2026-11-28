/// 安装包 ABI 选择策略。
///
/// 为什么需要它：为了压体积，发布时按 ABI 拆包（arm64-v8a / armeabi-v7a），
/// 同一版本对应两个 `.apk`。自动更新必须挑到**与本机匹配**的那一只——
/// 给 32 位设备推 arm64 包，系统会报 `INSTALL_FAILED_NO_MATCHING_ABIS`，
/// 用户看到的又是一句"安装失败"。
///
/// 全部是纯函数，方便单测；不依赖 Platform，桌面环境照样能跑。
library;

/// 发布包里能识别的 ABI 形态。
enum ApkAbi {
  /// arm64-v8a：2016 年以后几乎所有手机。
  arm64,

  /// armeabi-v7a：32 位 ARM，老设备 / 低端机。
  armv7,

  /// x86_64：模拟器与少数平板。
  x86_64,

  /// x86：模拟器。
  x86,

  /// 未标注 ABI 的通用包（含多套 native 库）。
  universal,
}

extension ApkAbiX on ApkAbi {
  /// `Build.SUPPORTED_ABIS` 里的写法。
  String get androidName {
    switch (this) {
      case ApkAbi.arm64:
        return 'arm64-v8a';
      case ApkAbi.armv7:
        return 'armeabi-v7a';
      case ApkAbi.x86_64:
        return 'x86_64';
      case ApkAbi.x86:
        return 'x86';
      case ApkAbi.universal:
        return '';
    }
  }
}

class ApkAssetPolicy {
  const ApkAssetPolicy._();

  /// 从文件名识别 ABI。
  ///
  /// 顺序有讲究：`arm64` 要排在 `arm` 之前判断，否则
  /// `app-arm64-v8a-release.apk` 会被当成 32 位包。
  static ApkAbi classify(String fileName) {
    final name = fileName.toLowerCase();
    if (name.contains('arm64-v8a') || name.contains('arm64') || name.contains('aarch64')) {
      return ApkAbi.arm64;
    }
    if (name.contains('armeabi-v7a') ||
        name.contains('armeabi') ||
        name.contains('armv7') ||
        name.contains('v7a')) {
      return ApkAbi.armv7;
    }
    if (name.contains('x86_64') || name.contains('x64')) {
      return ApkAbi.x86_64;
    }
    if (name.contains('x86')) {
      return ApkAbi.x86;
    }
    return ApkAbi.universal;
  }

  /// 给候选包打分，负数表示本机装不了。
  ///
  /// [deviceAbis] 来自 `Build.SUPPORTED_ABIS`，**有序**：首选 ABI 在最前，
  /// 所以命中下标越小分越高（arm64 设备上 arm64 包 > v7a 兼容包）。
  static int score(String fileName, List<String> deviceAbis) {
    final abi = classify(fileName);

    if (deviceAbis.isEmpty) {
      // 拿不到设备 ABI（通道缺失 / 桌面）：按通用性排序，
      // 通用包最稳，arm64 次之，32 位再次。
      switch (abi) {
        case ApkAbi.universal:
          return 100;
        case ApkAbi.arm64:
          return 90;
        case ApkAbi.armv7:
          return 80;
        case ApkAbi.x86_64:
          return 10;
        case ApkAbi.x86:
          return 5;
      }
    }

    if (abi == ApkAbi.universal) {
      // 通用包一定能装，但体积大，所以排在"精确匹配"之后。
      return 50;
    }

    final wanted = abi.androidName;
    for (var i = 0; i < deviceAbis.length; i++) {
      if (deviceAbis[i].trim().toLowerCase() == wanted) {
        return 1000 - i * 10;
      }
    }
    return -1;
  }

  /// 在候选里挑最适合本机的一只；都不合适返回 null。
  ///
  /// 同分时保持原顺序（GitHub 返回的顺序通常是最新上传在前），
  /// 用严格大于比较即可。
  static T? pick<T>(
    List<T> candidates,
    String Function(T) nameOf,
    List<String> deviceAbis,
  ) {
    T? best;
    var bestScore = -1;
    for (final candidate in candidates) {
      final s = score(nameOf(candidate), deviceAbis);
      if (s > bestScore) {
        bestScore = s;
        best = candidate;
      }
    }
    return bestScore < 0 ? null : best;
  }
}
