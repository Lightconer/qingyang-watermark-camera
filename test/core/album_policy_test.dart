import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/policy/album_policy.dart';

void main() {
  group('AlbumPolicy.normalize', () {
    test('空值回退默认相册名', () {
      expect(AlbumPolicy.normalize(null), AlbumPolicy.defaultAlbum);
      expect(AlbumPolicy.normalize(''), AlbumPolicy.defaultAlbum);
      expect(AlbumPolicy.normalize('   '), AlbumPolicy.defaultAlbum);
    });

    test('中文与常规名称原样保留', () {
      expect(AlbumPolicy.normalize('青阳水印相机'), '青阳水印相机');
      expect(AlbumPolicy.normalize('  巡检 2026  '), '巡检 2026');
    });

    test('路径分隔符与保留字符替换为下划线', () {
      // 相册名会拼进 Pictures/<名称>/，出现分隔符就会写进别的目录
      expect(AlbumPolicy.normalize('取证/现场'), '取证_现场');
      expect(AlbumPolicy.normalize(r'取证\现场'), '取证_现场');
      expect(AlbumPolicy.normalize('a:b*c?d"e<f>g|h'), 'a_b_c_d_e_f_g_h');
    });

    test('控制字符被清除', () {
      expect(AlbumPolicy.normalize('取证\n现场\u0000图'), '取证_现场_图');
    });

    test('首尾点号与空白去掉，避免非法目录名', () {
      expect(AlbumPolicy.normalize(' ..取证.. '), '取证');
      expect(AlbumPolicy.normalize('.'), AlbumPolicy.defaultAlbum);
      expect(AlbumPolicy.normalize('..'), AlbumPolicy.defaultAlbum);
    });

    test('连续空白压成单个空格', () {
      expect(AlbumPolicy.normalize('青阳   水印'), '青阳 水印');
    });

    test('超长名称截断到上限内', () {
      final long = '青' * 80;
      final normalized = AlbumPolicy.normalize(long);
      expect(normalized.length, AlbumPolicy.maxLength);
      expect(normalized, '青' * AlbumPolicy.maxLength);
    });

    test('全部字符非法时回退默认名，而不是写出下划线目录', () {
      expect(AlbumPolicy.normalize('////'), '____');
      expect(AlbumPolicy.normalize('***'), '___');
      // 只有点号的情况必须回退：'.' 与 '..' 是目录语义
      expect(AlbumPolicy.normalize('...'), AlbumPolicy.defaultAlbum);
    });

    test('isClean 判断是否需要提示用户', () {
      expect(AlbumPolicy.isClean('青阳水印相机'), isTrue);
      expect(AlbumPolicy.isClean('取证/现场'), isFalse);
    });
  });
}
