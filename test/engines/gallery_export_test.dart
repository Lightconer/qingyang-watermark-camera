import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/policy/album_policy.dart';
import 'package:qingyang_watermark/engines/media/gallery_export_engine.dart';

void main() {
  group('GalleryExportService', () {
    test('关闭开关时不调用引擎，返回 disabled', () async {
      final engine = FakeGalleryExportEngine();
      final service = GalleryExportService(engine: engine, isEnabled: () => false);

      final result = await service.save(path: '/tmp/a.jpg', fileName: 'a.jpg');

      expect(result.status, GalleryExportStatus.disabled);
      expect(result.isSaved, isFalse);
      expect(engine.calls, isEmpty);
      expect(service.enabled, isFalse);
    });

    test('相册名先归一化再交给引擎：分隔符不会写进别的目录', () async {
      final engine = FakeGalleryExportEngine();
      final service = GalleryExportService(
        engine: engine,
        albumName: () => '取证/现场',
      );

      final result = await service.save(path: '/tmp/a.jpg', fileName: 'a.jpg');

      expect(service.album, '取证_现场');
      expect(engine.calls.single.album, '取证_现场');
      expect(result.album, '取证_现场');
      expect(result.isSaved, isTrue);
      expect(result.uri, isNotEmpty);
    });

    test('空相册名回退默认名', () async {
      final engine = FakeGalleryExportEngine();
      final service = GalleryExportService(engine: engine, albumName: () => '  ');

      await service.save(path: '/tmp/a.jpg', fileName: 'a.jpg');

      expect(engine.calls.single.album, AlbumPolicy.defaultAlbum);
    });

    test('缺权限时不谎报成功，且只申请一次', () async {
      final engine = FakeGalleryExportEngine(
        failStatus: GalleryExportStatus.permissionRequired,
        failTimes: 99,
      );
      var asked = 0;
      final service = GalleryExportService(
        engine: engine,
        requestPermission: () async {
          asked++;
          return false;
        },
      );

      final result = await service.save(path: '/tmp/a.jpg', fileName: 'a.jpg');

      expect(result.status, GalleryExportStatus.permissionRequired);
      expect(result.isSaved, isFalse);
      expect(asked, 1);
      // 申请被拒后不应反复重试（避免刷权限弹窗）
      expect(engine.calls.length, 1);
    });

    test('补到权限后重试一次即成功', () async {
      final engine = FakeGalleryExportEngine(
        failStatus: GalleryExportStatus.permissionRequired,
        failTimes: 1,
      );
      var asked = 0;
      final service = GalleryExportService(
        engine: engine,
        requestPermission: () async {
          asked++;
          return true;
        },
      );

      final result = await service.save(path: '/tmp/a.jpg', fileName: 'a.jpg');

      expect(asked, 1);
      expect(result.isSaved, isTrue);
      expect(engine.calls.length, 2);
      expect(result.describe(), contains('已存入相册'));
    });

    test('失败原因进入提示文案，便于现场排查', () async {
      final engine = FakeGalleryExportEngine(
        failTimes: 99,
        detail: '磁盘已满',
      );
      final service = GalleryExportService(engine: engine);

      final result = await service.save(path: '/tmp/a.jpg', fileName: 'a.jpg');

      expect(result.status, GalleryExportStatus.failed);
      expect(result.describe(), contains('磁盘已满'));
    });
  });

  group('MediaStoreGalleryExportEngine', () {
    test('原文件不存在时直接失败，不发起平台调用', () async {
      const engine = MediaStoreGalleryExportEngine();

      // 该路径必然不存在：说明落盘失败时不会在相册里留下空条目
      final result = await engine.saveImage(
        sourcePath: '/definitely/not/here/photo.jpg',
        fileName: 'photo.jpg',
        album: AlbumPolicy.defaultAlbum,
      );

      expect(result.status, GalleryExportStatus.failed);
      expect(result.detail, '原文件不存在');
    });
  });
}
