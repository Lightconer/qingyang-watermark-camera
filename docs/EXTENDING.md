# 扩展指南

五类扩展都不需要改动既有模块的主流程。下面每条都给出"新增什么文件 + 改哪一行"。

---

## 1. 新增水印字段

场景：卫片执法要写"图斑编号"，工程巡检要写"车牌号"。

```dart
// features/workorder/plate_field.dart
import '../../core/extensions/watermark_field_provider.dart';
import '../../core/models/template.dart';

class PlateFieldProvider implements WatermarkFieldProvider {
  const PlateFieldProvider();

  @override
  String get id => 'vehicle_plate';

  @override
  String get label => '车牌号';

  @override
  int get priority => 82; // 项目名称(80) 之后、备注(90) 之前

  @override
  bool isAvailable(FieldContext ctx) => _plate(ctx) != null;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final plate = _plate(ctx);
    if (plate == null) return null;
    return ResolvedField(
      id: id,
      label: label,
      text: '车牌 $plate',
      priority: priority,
    );
  }

  String? _plate(FieldContext ctx) {
    final value = ctx.template.valueOf('vehicle_plate');
    return value.isEmpty ? null : value;
  }
}
```

挂载（二选一）：

```dart
// 方式 A：作为某个业务模块的一部分
class WorkOrderFeature implements FeatureModule {
  @override
  String get id => 'workorder';

  @override
  List<WatermarkFieldProvider> get fields => const [PlateFieldProvider()];
}

// 方式 B：直接在 bootstrap 里注册模块
registry.register(WorkOrderFeature());
```

字段会自动出现在设置页的字段池、模板编辑器的开关、以及水印绘制里。
**不需要**改 `WatermarkRenderer`、`LayoutEngine`、`CapturePage`、`ImportPage`。

> 字段值来源：`TemplateConfig.values['vehicle_plate']`（模板级）或
> `IdentityInfo`（全局）。需要外部数据（传感器、工单接口）时，把值写进
> `FieldContext` 的扩展位——请优先复用 `template.values`，避免给字段插件加 I/O。

---

## 2. 新增图像管线中间件

场景：需要在编码前给画面右下角打一个项目 LOGO；或者接人脸检测做打码。

```dart
// features/workorder/logo_middleware.dart
class LogoMiddleware implements ImageMiddleware {
  const LogoMiddleware(this.logoAsset);

  final String logoAsset;

  @override
  String get id => 'logo-overlay';

  @override
  int get order => 650; // 绘制水印(600) 之后、编码(700) 之前

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(FrameBuffer? frame, PipelineJob job, PipelineContext ctx) async {
    final current = frame!;
    // …用 Canvas 把 LOGO 画到 current.image 上…
    return current.fork(image: newImage);
  }
}
```

注册：

```dart
class WorkOrderFeature implements FeatureModule {
  @override
  List<ImageMiddleware> get middlewares => const [LogoMiddleware('assets/logo.png')];
}
```

`PipelineRunner` 会把所有中间件按 `order` 排序后串行执行；`order` 已预留间隔
（100/200/300/400/550/600/700/800），插入时取中间值即可（如 450、650、780）。

注意事项：
* 第一个中间件（100 解码）可以为 `frame == null`；其余中间件必须返回新帧；
* 中间件之间用 `FrameBuffer.bag` 传旁路数据（`fingerprint`、`layout`、`skipReason`…）；
* 需要"跳过整张图"时设置 `bag['skipped'] = true` 并给出 `skipReason`。

---

## 3. 新增元数据来源

场景：接执法记录仪同步的照片，它的元数据在自己的 SQLite 里而不是 EXIF。

```dart
class RecorderMetadataProvider implements MetadataProvider {
  @override
  String get id => 'metadata.recorder';

  @override
  bool supports(PhotoSource source) => source == PhotoSource.folder;

  @override
  Future<PhotoMetadata> read(String path) async {
    // 查本地索引，返回统一 PhotoMetadata
  }

  @override
  Future<Uint8List> write(Uint8List jpegBytes, {
    required WatermarkStamp stamp,
    required PhotoMetadata original,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
  }) async {
    // 复用 ExifCodec 写入 Software / UserComment / XMP
  }
}
```

装配（`bootstrap.dart`）：

```dart
metadata: MetadataEngine(providers: [
  CameraMetadataProvider(),
  ExifMetadataProvider(),
  RecorderMetadataProvider(), // 放在前面可优先命中
]),
```

`MetadataEngine.providerFor(source)` 按 `supports()` 顺序匹配，渲染层无需任何改动。

---

## 4. 新增业务模式

只加 JSON，不写分支。

```json
// assets/profiles/supervision.json
{
  "id": "supervision",
  "label": "督查",
  "timePolicy": "trustedRequired",
  "coordPolicy": "deviceFixRequired",
  "allowedFields": ["source_badge", "time", "coords", "address", "operator", "organization", "hash"],
  "requireProvenanceBadge": true,
  "allowMetaEditing": false,
  "weatherAllowed": false,
  "shutterLocked": true
}
```

```json
// assets/profiles/index.json
{
  "version": "1.0",
  "profiles": [
    "assets/profiles/forensics.json",
    "assets/profiles/processed.json",
    "assets/profiles/free.json",
    "assets/profiles/supervision.json"
  ]
}
```

模式出现在设置页与模板的模式选择里；口径判定自动生效
（`TimePolicyEvaluator` / `CoordPolicyEvaluator` 读的是 `TimePolicyKind` / `CoordPolicyKind`）。

---

## 5. 新增业务功能模块

```dart
// features/workorder/workorder_feature.dart
class WorkOrderFeature implements FeatureModule {
  @override
  String get id => 'workorder';

  @override
  bool get enabledByDefault => true;

  @override
  List<RouteSpec> get routes => [
        RouteSpec(name: '/workorder', builder: (context) => const WorkOrderPage()),
      ];

  @override
  List<WatermarkFieldProvider> get fields => const [PlateFieldProvider()];

  @override
  List<ImageMiddleware> get middlewares => const [LogoMiddleware('assets/logo.png')];

  @override
  List<SettingSection> get settings => [
        SettingSection(
          id: 'workorder',
          title: '工单',
          priority: 60,
          builder: (context) => const WorkOrderSettings(),
        ),
      ];

  @override
  Future<void> init(AppServices services) async {
    // 例如预热工单缓存
  }
}
```

```dart
// app/bootstrap.dart，唯一改动
registry.register(WorkOrderFeature());
```

页面跳转用路由名：`Navigator.of(context).pushNamed('/workorder')`。
模块可以被用户在设置页整体关闭（`FeatureRegistry.isEnabled`），关闭后其路由、
字段、中间件、设置分区一起下线，不影响其它模块。

---

## 测试要求

新增扩展时按引擎的分层补测试：

| 扩展类型 | 建议测试 |
| --- | --- |
| 字段插件 | 纯 Dart 单测：可用性 + 文案（`test/core/field_catalog_test.dart` 可仿写） |
| 中间件 | 管线顺序 + 帧前后变化（`test/engines/pipeline_test.dart`） |
| 元数据适配器 | 读写往返：写进去的戳记能被 `ExifCodec.read` 读回 |
| 业务模式 | JSON 解析 + 白名单过滤（`test/core/template_test.dart`） |
| 功能模块 | 注册后 `FeatureRegistry` 的 routes/fields/middlewares 计数变化 |

所有引擎都应提供 Fake 实现，使上述测试不依赖真实相机、网络、文件系统。
