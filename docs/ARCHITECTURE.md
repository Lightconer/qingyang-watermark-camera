# 架构说明（青阳水印相机）

目标：**新增功能只需要新增文件 + 一行注册，不改动任何既有模块的主流程。**
为达成这一点，工程按"四层单向依赖 + 五个扩展点"组织，所有跨层调用都走接口。

---

## 1. 四层目录结构与依赖方向

```
lib/
├── main.dart                     入口：只做 bootstrap + runApp
├── app/                          组装层：依赖注入 / 路由 / 功能注册表 / 应用外壳
│   ├── bootstrap.dart            装配顺序：设置 → 模板 → 模式 → 注册模块 → 服务容器 → 模块 init
│   ├── services.dart             AppServices（服务容器）+ ServicesScope（InheritedWidget）
│   ├── feature_module.dart       FeatureModule / RouteSpec / SettingSection 接口
│   ├── feature_registry.dart     唯一装配点：路由 / 字段 / 中间件 / 设置分区汇总
│   ├── router.dart               路由表（完全由注册表驱动）
│   ├── app_shell.dart            外壳：相机主页 + 底部三按钮（模板 / 快门 / 相册）
│   ├── app.dart                  根节点：注入服务 → 主题 → 路由
│   └── theme.dart                简约政务工具风，深浅色主题
├── features/                     业务单元：彼此不互相引用
│   ├── capture/                  拍摄链路（预览/冻结上下文/出图/落盘/台账）
│   ├── import/                   导入链路（三入口/网格预览/批量/失败重试）
│   ├── template/                 模板编辑器（字段/样式/取值/导入导出）
│   ├── gallery/                  相册列表 + 详情（原始信息与哈希）
│   ├── verify/                   校验工具（哈希与戳记比对）
│   ├── ledger/                   台账查看与 XLSX 导出
│   ├── settings/                 设置页（字段/模板/密钥/输出/台账/权限/模块）
│   └── feature_modules.dart      各模块的 FeatureModule 声明（新增模块在此加类）
├── engines/                      能力引擎：接口 + 默认实现 + fake 实现
│   ├── watermark/                水印渲染（Canvas，描边+填充，二维码）
│   ├── image/                    编解码、管线、8 个中间件
│   ├── metadata/                 元数据来源适配器（拍摄 / EXIF）+ 引擎分派
│   ├── location/                 定位（北斗+GPS+网络融合由系统提供）
│   ├── time/                     NTP 授时（UDP/123，无第三方库）
│   ├── geocoding/                逆地理（高德 / Nominatim / 关闭）
│   ├── weather/                  天气（Open-Meteo / 关闭）
│   ├── hash/                     SHA256（文件 / 去元数据像素流）
│   ├── storage/                  存储目录、设置、模板、台账
│   └── media/                    相册写入（MediaStore）/ SAF / ACTION_SEND 入口
└── core/                         纯 Dart 领域层：无 Flutter 依赖，可单测
    ├── models/                   PhotoMetadata / CaptureContext / Provenance / Template / Profile / Job / Ledger
    ├── policy/                   时间口径、坐标口径、时间格式
    ├── layout/                   水印排版引擎（几何计算，测量函数可注入）
    ├── service/                  字段目录、校验（attestation）
    ├── metadata/                 JPEG/EXIF/TIFF 编解码、XMP 包
    ├── extensions/               WatermarkFieldProvider 等纯 Dart 接口
    └── ledger/                   XLSX 生成（自写 ZIP，无第三方依赖）
```

依赖方向（严格单向，箭头表示"可以依赖"）：

```
app ──▶ features ──▶ engines ──▶ core
 │                                   ▲
 └───────────────────────────────────┘
```

| 约束 | 落地方式 |
| --- | --- |
| `engines` 不引用 `features` | engines 目录下没有任何 `../features` 导入；`grep -r "features/" lib/engines` 为空 |
| `features` 之间不互相引用 | 页面之间只通过路由名跳转，跨模块数据通过 `AppServices` 的接口取用 |
| `core` 不引用 Flutter | core 下无 `package:flutter` 导入，只用 `dart:io`/`dart:convert`/`dart:typed_data`；排版用可注入的测量函数，不依赖 `TextPainter` |
| 接口先行、实现后置 | 每个引擎都是"抽象接口 + 默认实现 + Fake 实现"三件套，见下表 |

### 引擎三件套对照

| 能力 | 接口 | 默认实现 | 测试替身 |
| --- | --- | --- | --- |
| 图片编解码 | `ImageCodecEngine` | `FlutterImageCodec` | `FakeImageCodec` |
| 水印绘制 | `WatermarkRenderer` | `CanvasWatermarkRenderer` | `FakeWatermarkRenderer` |
| 元数据 | `MetadataProvider` | `CameraMetadataProvider` / `ExifMetadataProvider` | `FakeMetadataProvider` |
| 定位 | `LocationEngine` | `GeolocatorLocationEngine` | `FakeLocationEngine` |
| 授时 | `TimeSource` + `TimeEngine` | `NtpClient` | `FakeTimeSource` |
| 逆地理 | `GeocodingEngine` | `HttpGeocodingEngine` | `FakeGeocodingEngine` / `DisabledGeocodingEngine` |
| 天气 | `WeatherEngine` | `OpenMeteoWeatherEngine` | `FakeWeatherEngine` / `DisabledWeatherEngine` |
| 哈希 | `HashEngine` | `CryptoHashEngine` | `FakeHashEngine` |
| 存储 | `StorageEngine` | `FileStorageEngine` | `FakeStorageEngine` |
| 媒体入口 | `MediaGateway` | `PlatformMediaGateway` | `FakeMediaGateway` |
| 相册输出 | `GalleryExportEngine` | `MediaStoreGalleryExportEngine` | `FakeGalleryExportEngine` |
| 远程更新 | `UpdateEngine` + `ApkInstaller` | `GitHubUpdateEngine` + `NativeApkInstaller` | `FakeUpdateEngine` + `FakeApkInstaller` |

---

## 2. 五个可插拔扩展点

### 2.1 水印字段插件（`core/extensions/watermark_field_provider.dart`）

```dart
abstract class WatermarkFieldProvider {
  String get id;                                   // 全局唯一，模板开关与持久化用
  String get label;                                // 设置页/模板编辑器展示
  int get priority;                                // 越小越靠前（时间 10，坐标 20 …）
  bool isAvailable(FieldContext ctx);              // 不可用则整体不绘制
  ResolvedField? resolve(FieldContext ctx);        // 解析成一行文字
}
```

`FieldContext` 只提供领域数据（冻结的采集上下文、原图元数据、模板、指纹），
**不允许**插件访问文件系统或网络。字段汇总在 `FieldCatalog`，渲染器与页面只认 id。

新增「项目编号」只需新增一个实现类并挂到某个 `FeatureModule.fields`，
不需要改渲染器、排版引擎、任何页面（见 `docs/EXTENDING.md`）。

### 2.2 图像管线中间件（`engines/image/pipeline.dart`）

```dart
abstract class ImageMiddleware {
  String get id;
  int get order;                                   // 100 200 300 400 550 600 700 800
  bool appliesTo(PipelineJob job);
  Future<FrameBuffer> process(FrameBuffer? frame, PipelineJob job, PipelineContext ctx);
}
```

固定顺序与 order 间隔：

| order | 阶段 | 实现 |
| --- | --- | --- |
| 100 | 解码取帧 | `DecodeMiddleware`（解码阶段按长边降采样，等价 `inSampleSize`） |
| 200 | 方向校正 | `OrientMiddleware`（EXIF Orientation 1–8 → 旋转/镜像） |
| 300 | 降采样 | `DownscaleMiddleware`（长边 ≤ 4096） |
| 400 | 水印查重 | `DedupeMiddleware`（已有 QY1 戳记/XMP 标记则跳过） |
| 550 | 可选人脸打码 | `FaceBlurMiddleware`（默认不启用，注入检测框后生效） |
| 600 | 绘制水印 | `DrawWatermarkMiddleware`（两遍渲染：先算指纹，再画哈希小字） |
| 700 | 编码 | `EncodeMiddleware`（JPEG，质量可配） |
| 800 | EXIF 回写 | `MetadataWriteMiddleware`（像素哈希 → 戳记 → 落盘） |

`order` 之间留了间隔（100/200/…），插入新中间件选一个空隙值即可，例如 450 = 查重后的额外校验。

### 2.3 元数据来源适配器（`engines/metadata/metadata_engine.dart`）

```dart
abstract class MetadataProvider {
  String get id;
  bool supports(PhotoSource source);
  Future<PhotoMetadata> read(String path);
  Future<Uint8List> write(Uint8List jpegBytes, {
    required WatermarkStamp stamp,
    required PhotoMetadata original,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
  });
}
```

`MetadataEngine.providerFor(source)` 按来源分派：拍摄走 `CameraMetadataProvider`
（写入冻结时间与坐标），导入走 `ExifMetadataProvider`（保留 `DateTimeOriginal`/GPS/Make，
只追加 `Software` 与 `UserComment`）。渲染层只看到 `PhotoMetadata`，不感知来源。

### 2.4 模式配置化（`core/models/profile_config.dart` + `assets/profiles/*.json`）

```json
{
  "id": "processed",
  "label": "加工",
  "timePolicy": "originalOnly",
  "coordPolicy": "originalOnly",
  "allowedFields": ["source_badge", "time", "coords", "hash"],
  "requireProvenanceBadge": true,
  "allowMetaEditing": false,
  "weatherAllowed": false,
  "shutterLocked": false
}
```

代码里没有任何 `if (mode == forensics)` 分支：模式差异全部读 `ProfileConfig`。
新增模式 = 在 `assets/profiles/` 加一个 JSON + 在 `index.json` 登记一行。
口径判定在 `core/policy/policies.dart`（`TimePolicyEvaluator` / `CoordPolicyEvaluator`），
输出的是"提示/告警/阻断"列表，UI 与管线共用同一份判定。

### 2.5 业务功能模块化（`app/feature_module.dart`）

```dart
abstract class FeatureModule {
  String get id;
  bool get enabledByDefault;
  List<RouteSpec> get routes;                      // 页面
  List<WatermarkFieldProvider> get fields;         // 扩展点一
  List<ImageMiddleware> get middlewares;           // 扩展点二
  List<SettingSection> get settings;               // 设置页分区
  Future<void> init(AppServices services);         // 启动初始化
}
```

`FeatureRegistry` 汇总所有模块，`AppRouter`、设置页、`FieldCatalog`、`PipelineRunner`
全部从注册表取数据。新增功能 = 新增一个实现类 + `registry.register(...)` 一行。

---

## 3. 装配方案（依赖注入）

`bootstrap.dart` 的顺序是刻意固定的：

1. `SettingsStore.load()` —— 所有开关、密钥、身份信息；
2. `TemplateStore.load()` —— 内置模板（assets）+ 用户模板（SharedPreferences）；
3. `ProfileRepository.load()` —— 从 assets 加载模式 JSON；
4. `FeatureRegistry(settings)` + `register(...)` —— 注册模块（**唯一需要改的地方**）；
5. `AppServices(...)` —— 把引擎实例交给容器；容器内部再组装
   `FieldCatalog`（内置字段 + 模块字段）、`LayoutEngine`（注入 TextPainter 测量）、
   `PipelineRunner`（默认 8 中间件 + 模块中间件，按 order 排序）、`BatchPipeline`；
6. `registry.initAll(services)` —— 各模块的自初始化（失败只记日志，不影响启动）。

页面通过 `ServicesScope.of(context)` 取容器，构造函数注入具体依赖；
控制器（`CaptureController` / `ImportController`）只接收 `AppServices`，不自己 new 引擎。

---

## 4. 双链路数据流

### 拍摄

```
快门
 ├─ freezeContext(): NTP 时间 / 冻结坐标 / 地址 / 天气 / 在线状态  ← 一次锁定，之后只读
 ├─ camera.takePicture() → 临时文件
 ├─ PipelineJob(source=camera, template, profile, capture, provenance)
 ├─ PipelineRunner: 解码 → 转正 → 降采样 → 查重 → 绘制 → 编码 → EXIF/XMP
 ├─ （可选）保存原图到 original/camera
 └─ LedgerStore.append(台账)
```

### 导入

```
系统相册 / SAF / ACTION_SEND
 ├─ 读原图 EXIF（DateTimeOriginal / GPS / Make / Orientation）
 ├─ 网格预览：统一套模板 或 单张换模板
 ├─ 批量：逐张建 Job（source=gallery/folder/share，时间口径=originalOnly）
 ├─ 管线同上（无原图 GPS → 水印显示「无原始定位」；天气默认不显示）
 ├─ 成品命名：原名_wm.jpg，按 日期/import 分目录（原图绝不覆盖）
 └─ 台账 + 失败重试（带阶段名与原因）
```

---

## 5. 硬性约束的落点

| 约束 | 保证位置 |
| --- | --- |
| 禁止手动输入时间/经纬度 | 全工程没有任何坐标/时间的输入控件；`ProfileConfig.manualEntryForbidden` 恒为 true |
| 水印必须画在像素上 | `DrawWatermarkMiddleware` + `CanvasWatermarkRenderer`；EXIF 只是"同步留痕" |
| 像素与元数据双重留痕 | 像素：渲染器；元数据：`MetadataWriteMiddleware` 写 `UserComment` + XMP |
| 离线/在线、拍摄/导入必须区分 | `Provenance.badgeText` + 角标 + `source_badge` 字段；离线时时间后缀强制标注 |
| 原图不覆盖 | 成品固定 `原名_wm.jpg` 另存；原图仅可选复制到 `original/` |
| 防二次叠加 | `DedupeMiddleware` 检测 QY1 戳记 / XMP 命名空间 |
| 不编造地址与天气 | `GeocodingEngine`/`WeatherEngine` 失败返回 null，对应字段直接不可用 |
| 无水印图不得伪造为现场取证 | `Provenance.source` 写入戳记，`AttestationService` 交叉校验来源与时间口径 |
| 无广告、无付费弹窗 | 无任何广告 SDK / 内购依赖（见 `pubspec.yaml`） |

---

## 6. 哈希口径（三份留痕如何闭环）

1. **内容指纹 `fp`**：第一遍渲染（不含哈希小字）编码后的 SHA256，画在画面上；
2. **像素流哈希 `sha`**：最终 JPEG 去掉 EXIF/XMP 段后的 SHA256，写入 `UserComment` 与 XMP；
3. **台账 `sha256`**：与 ② 同口径，落在 `ledger/ledger_YYYY-MM-DD.jsonl`，导出为 XLSX。

校验时用同一口径重算 ②：任何像素改动（重压缩、裁剪、P 图）都会导致不一致；
只改元数据的攻击虽然不影响 ②，但会与台账 ③ 的原始记录对不上，可交叉发现。
这也是为什么口径必须是"去元数据的像素流"，而不是"整文件哈希"——
否则写入哈希这个动作本身就会改变哈希，永远无法自洽。

---

## 7. 成品去向：应用目录 + 系统相册双写

成品先落在应用私有外部目录（`QingyangWatermark/日期/camera|import`），这是**唯一事实源**：
相册页扫它、校验读它、台账记它的路径。落盘成功后再复制一份进系统相册的独立相册
（默认 `Pictures/青阳水印相机/`），让系统图库、微信、文件管理器可以直接取用。

* 引擎：`GalleryExportEngine` / `MediaStoreGalleryExportEngine`
  （MethodChannel `com.qingyang.watermark/gallery` → `MainActivity.saveToGallery`）。
* Android 10+ 走 `MediaStore` + `RELATIVE_PATH` + `IS_PENDING`（先占位后落盘，
  避免相册里出现半张图）；Android 9 及以下写公共 `Pictures` 目录后由
  `MediaScannerConnection` 登记，否则重启后相册里看不到。
* 相册名经 `AlbumPolicy.normalize` 归一化：`/ \ : * ? " < > |` 与控制字符替换为
  `_`，去首尾点号、压连续空白、截到 40 字、空名回退默认——相册名会拼进真实路径，
  不过滤就会写进别的目录或直接失败。
* 相册写入失败**不回滚**成品与台账：状态里写明原因（缺权限 / 磁盘拒绝），
  相册详情页提供"存入系统相册"手动重试。
* 关掉「同时存入系统相册」后不产生任何副本，等价于完全离线 + 仅私有目录。

---

## 8. 远程更新（应用内自更新）

设置页「更新」分区：查 GitHub Releases → 判断版本 → 下载 → 校验 SHA256 → 交给系统安装器。

* 查：`UpdateEngine.check()` 请求 `api.github.com/repos/<repo>/releases/latest`
  （10s 超时、带 UA、403 判为限流、404 判为无发布记录），用 `AppVersion` 逐段比较
  `tag_name` 与系统 `versionName`；同号预发布版低于正式版，不会把 beta 推给现场。
* 装：`ApkInstaller` 自己下载字节（只有这样才拿得到哈希），与发布附带的
  `SHA256SUMS.txt` 比对，**不一致直接丢弃、不安装**；一致才写进 `PackageInstaller`
  会话，由系统安装界面完成确认（不静默安装、不申请 INSTALL_PACKAGES 系统权限）。
* 安装回调：`PackageInstaller` 提交后回一条 `STATUS_PENDING_USER_ACTION` 广播，
  由清单里 `exported="false"` 的 `InstallResultReceiver` 拉起系统确认界面——
  少了这一步的表现是"调用成功但屏幕没反应"。
* 隐私：`自动检查更新` 默认开但**24 小时节流**，冷启动最多一天一次；关掉后
  `UpdateService.checkIfDue()` 直接返回 null，不发任何请求。手动点「检查更新」
  属于用户明确操作，不受该开关限制。
* 更新源可在设置里改成 `owner/repo`（分叉部署或私有分发时用），留空回退默认仓库。

---

## 9. 构建环境注意事项（`scripts/bootstrap_android.sh`）

仓库不提交 `android/`，平台目录在构建前由脚本现生成。踩过的坑记在这里，改动脚本前先读：

| 现象 | 根因 | 现在的做法 |
| --- | --- | --- |
| `Unexpected tokens (use ';' to separate expressions on the same line)` | 用 Groovy 正则 `applicationId ` 去改 Kotlin DSL 的 `applicationId = `，把 kts 改成了 Groovy 语法 | 包名不再 sed：`flutter create --org com.qingyang --project-name watermark` 直接生成 `com.qingyang.watermark`，`namespace`/`applicationId`/MainActivity 包路径天然一致 |
| `'fun Project.android(...)' is deprecated ...` 被当作 error | AGP 9 把 Kotlin DSL 的 `android {}` 访问器标成 `DeprecationLevel.ERROR`；一旦再追加第二个 `android {}` 块，连模板自带的那个也会解析到废弃重载 | 脚本不再注入 Gradle 签名配置；根构建脚本整体改为 Groovy（只做仓库/输出目录/子工程编排，不引用 AGP DSL 类型） |
| `Unresolved reference 'util'` | kts 里 `java` 被 `JavaPluginExtension` 遮蔽，`java.util.Properties` 无法解析 | 不再在 Gradle 里读 `key.properties`；签名统一交给 `sign_apk.sh`（`zipalign -p -f 4` + `apksigner`，v1/v2） |
| `:file_picker:checkReleaseAarMetadata` 要求 compileSdk ≥ 36 | 部分插件自身仍声明 `android-34`，而 `flutter_plugin_android_lifecycle` 要求依赖方编译在 36 以上 | 根脚本在 `subprojects` 里统一抬 `compileSdk` 到 36（并打印被抬高的模块） |
| `Cannot run Project.afterEvaluate(Closure) when the project is already evaluated` | `evaluationDependsOn(":app")` 会立即评估工程，之后再对同一工程注册 `afterEvaluate` 会抛错 | compileSdk 覆盖块必须排在 `evaluationDependsOn(":app")` **之前** |
| `:camera_android_camerax:lintVitalAnalyzeRelease` 崩溃（`java.util.List.removeLast`） | lint 的 `CommentDetector` 在 CI 的 JDK/AGP 组合下的自身 bug | 关闭所有 `lintVital*` 任务；构建门禁在 Dart 侧（`flutter analyze` + `flutter test`） |
| `:app:compileReleaseKotlin` → `Unclosed comment` | Kotlin 支持**嵌套**块注释，`MainActivity.kt` 的 KDoc 里写了 `image/*`，等于又开了一层 `/*` | Kotlin 注释正文里不要出现 `/*`，改写成「ACTION_SEND（image 类型）」 |

另外两条约定：

* **签名只有一条链路**：Gradle 侧一律用默认调试签名，产物在构建末尾由 `scripts/sign_apk.sh`
  重签；未配置 `KEYSTORE_BASE64` 时脚本跳过重签，产物保持调试签名（可安装、不适合分发）。
* **版本号来源唯一**：`release.yml` 用标签版本号作 `--build-name`、流水线序号作
  `--build-number`，产物名 `qingyang-watermark-vX.Y.Z.apk` 与 `SHA256SUMS.txt` 一并发布。
