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
| 用户报「解析包时出现问题」，而我们这边构建全绿 | 三个成因：包下载被截断（54 MB universal 包在国内网络极易断）、**只有 v2/v3 缺 v1**（minSdk 24 时 AGP 默认不生成 v1，且旧脚本只在配置证书时才重签）、native 库对齐粒度 | 见第 10 节：分 ABI 拆包瘦身 + 无条件重签补齐 v1 + 发布前结构体检 |

另外两条约定：

* **签名只有一条链路**：Gradle 侧一律用默认调试签名，产物在构建末尾由 `scripts/sign_apk.sh`
  **无条件重签**；未配置 `KEYSTORE_BASE64` 时改用 AGP 刚用过的调试证书重签（补齐 v1，
  但证书每次构建都不同，跨版本覆盖安装会失败——必须配置四个签名 Secret）。
* **版本号来源唯一**：`release.yml` 用标签版本号作 `--build-name`、流水线序号作
  `--build-number`，产物名 `qingyang-watermark-vX.Y.Z-<abi>.apk` 与 `SHA256SUMS.txt` 一并发布。

---

## 10. 安装包体积与安装成功率（v1.4.0）

「解析包时出现问题」在国产 ROM 上并不是一个根因，而是一组根因共用的提示语。
这一节把四个成因逐个消掉。

### 10.1 分 ABI 拆包：54 MB → 19 MB

`flutter build apk` 默认产出 universal 包，把 `arm64-v8a` / `armeabi-v7a` / `x86_64`
三套引擎全塞进去。一部 arm64 手机实际只会用到其中一套，另外两套（约 30 MB）纯属陪跑。
但包越大，国内网络下载中断的概率越高，而**下载不完整正是这个报错最常见的成因**。

v1.4.0 起 `scripts/build_release.sh` 用 `--split-per-abi` 出两个包（下表为
v1.4.0 线上实测体积，非估算）：

| 产物 | 覆盖 | 体积 |
| --- | --- | --- |
| `...-arm64-v8a.apk` | 2016 年后的绝大多数手机 | 19.26 MB |
| `...-armeabi-v7a.apk` | 32 位老设备 / 低端机 | 17.24 MB |

`x86_64` 直接丢弃（只有模拟器会用）。代价是发布页有两只包，必须让用户选对——
而"让用户选"本身就是失败源，所以应用内更新会自动按 `Build.SUPPORTED_ABIS` 选包
（`core/policy/abi_policy.dart`，规则见本节）。

### 10.2 签名与对齐：把三种"结构性坏包"挡在发布前

**先记根因，因为它不是猜出来的**：v1.0.0～v1.3.0 的所有发布产物都是**纯 v2/v3、缺 v1**。
原因是 `minSdk 24` 时 AGP 认为 v1 只服务 Android 7 以下，默认**不生成 v1**；而旧版
`sign_apk.sh` 只在配置了 `KEYSTORE_BASE64` 时才重签补 v1——这个仓库一直没配 Secret，
于是脚本每次都走"跳过重签"分支，把缺 v1 的包原样发了出去。荣耀等国产 ROM 的安装器
发现包里没有 `META-INF/*.RSA` 就判「包损坏」，这正是用户报的那句提示。
CI 第一次跑新增的结构体检时直接红在「缺少 v1 签名」，反证了这条链路。

所以修复的第一原则是：**重签不能是可选分支**。现在无论有没有发布证书都重签一遍：
有证书用发布证书，没有就用 AGP 刚用过的调试证书（`~/.android/debug.keystore`，
`androiddebugkey` / `android`）。后者能装上，但证书每次构建都不同，见下方告警。

`scripts/sign_apk.sh` 现在的签名参数：

* `--v1-signing-enabled true`：**缺 v1 的包，部分国产 ROM 的安装器直接判"包损坏"**。
* `--v2-signing-enabled true`、`--v3-signing-enabled true`：Android 7+ / 9+ 的主通道，
  三者可以共存，不影响老设备。
* 不开 v4：v4 需要同目录的 `.idsig` 文件，侧载场景反而容易缺件。
* `--min-sdk-version 24 --max-sdk-version 36` 显式传入：让 apksigner 自己读清单，
  万一读到错的 minSdk 会选错 v1 摘要算法。
* 对齐：`zipalign -P 16 -p -f 4` 先**真跑一次**，失败再退 `-p -f 4`。不去解析
  `zipalign -h` 的用法文本判断支持性——不同 build-tools 写法不一致，猜错的代价是
  新机装不上还查不出原因。v1.4.0 在 CI 上 `-P 16` 失败回退，但结构体检显示产物
  native 库本来就是 **16 KB 对齐**（AGP 8.9+ 自己摆好的），最终以体检报告为准。

签完立刻 `apksigner verify --min-sdk-version 24`，验不过就 `exit 1`——
自己都不认的包不允许进 Release。

> ⚠️ **仍未解决的人工项**：仓库尚未配置 `KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` /
> `KEY_ALIAS` / `KEY_PASSWORD` 四个 Secret。CI 每次现生成调试证书，意味着
> **v1.4.0 能装，但下一版无法覆盖安装**（系统报「与已安装应用签名不一致」，
> 极易与「解析包时出现问题」混淆）。发下一版前必须配置固定证书。

### 10.3 发布前结构体检（`scripts/verify_apk.py`）

`apksigner verify` 只校验证书与签名块，不关心 zip 内部布局。而下面任何一条都会让
安装器报同一句"解析包时出现问题"：

| 检查项 | 不通过的后果 |
| --- | --- |
| `resources.arsc` 必须 `STORED` 且 4 字节对齐 | Android 11+ 报 `INSTALL_PARSE_FAILED_RESOURCES_ARSC_COMPRESSED` |
| `lib/**/*.so` 必须 `STORED` | `extractNativeLibs=false` 时安装器直接拒绝 |
| 存在 `META-INF/*.RSA` | 缺 v1 签名，国产 ROM 判包损坏 |
| 中央目录前存在 `APK Sig Block 42` | 缺 v2/v3，Android 7+ 拒绝安装 |
| `zip.testzip()` 通过、单条目 < 200 MB | 下载截断 / 结构损坏 |

体检脚本在 `build_release.sh` 末尾执行，非 0 退出即整条流水线红。

### 10.4 应用内更新也要防"坏包"

`NativeApkInstaller.downloadAndInstall` 现在有三道闸：

1. **长度比对**：`received != contentLength` 直接删包，提示"下载不完整"，
   而不是把半截包交给安装器；
2. **哈希比对**：与 `SHA256SUMS.txt` 不一致即丢弃（清单取不到也停止安装，
   不再"查不到就跳过校验"）；
3. **解析预检**：`PackageManager.getPackageArchiveInfo()` 先让系统解析一遍，
   返回 null 就说明包本身有问题——当场删掉并说明原因，
   不让用户对着系统那句没有线索的「解析包时出现问题」发懵。

### 10.5 运行期资源占用

| 措施 | 位置 | 效果 |
| --- | --- | --- |
| 前后台生命周期释放相机、定位、指南针、授时轮询 | `CaptureController.didChangeAppLifecycleState` | 后台不再持有预览纹理与 GPS 唤醒锁；只在 `paused` 动手，避免下拉通知栏就闪黑 |
| 九宫格缩略图按 512 px 解码 | `gallery_page.dart` | 一张 4000×3000 全尺寸解码要 48 MB 堆，缩略图只需 0.8 MB |
| 详情页限宽 2048 px 解码 | 同上 | 48 MB → 12 MB |
| `ImageCache` 上限压到 48 MB / 60 张 | `main.dart` | 默认 100 MB 对中端机偏大，容易和相机缓冲抢内存 |

---

## 11. 设备与机型适配（v1.3.0）

现场拍照类应用最容易被投诉的不是功能少，而是"在我这台机器上不对"。这一节记录三类
差异的收敛方式。

### 11.1 预览与成片的画幅对齐（`core/layout/frame_fit.dart`）

问题：取景框尺寸由**屏幕**决定（19.5:9 / 20:9 / 平板 4:3），成片尺寸由**传感器**决定
（通常 4:3）。如果水印按"屏幕尺寸"排版，同一套模板在不同手机上位置和字号都会不同，
预览与成片也对不上。

做法：

1. 水印排版永远使用**成片坐标系**（`LayoutEngine.compute(size: fit.photo)`）；
2. `FrameFit` 计算成片在取景框里的落位（`contain` 或 `cover`），并提供 `toBox`/`toPhoto`
   双向映射；
3. 预览层 `canvas.translate/fit.scale` 后按成片坐标绘制，`LayoutEngine` 不需要知道屏幕多大。

`FrameFit` 是纯 Dart（只依赖 `LayoutSize`/`LayoutRect`），所以能在单测里覆盖留边、
裁切、坐标互转与零尺寸退化，不必上真机。

### 11.2 取景模式：留边 / 铺满

`settings.previewFill` 控制：

| 模式 | 几何 | 适用场景 | 代价 |
| --- | --- | --- | --- |
| 留边（默认，`contain`） | 取景框按照片比例居中，四周用渐变底填充 | 取证、验收——屏幕上看到的范围就是成片范围 | 屏占比低一些 |
| 铺满（`cover`） | 取景框被照片填满，边缘裁掉 | 打卡、宣传——画面更饱满 | 成片边缘比预览多一点 |

两种模式下**水印位置都以成片为准**，所以铺满时如果水印落在被裁掉的边缘，预览里看到的
位置就是它在成片里的位置——不会出现"预览里有、成片里偏了"。

### 11.3 方位角（`core/policy/heading.dart` + `engines/sensor/compass_engine.dart`）

* 传感器走原生 `SensorManager`：优先 `TYPE_ROTATION_VECTOR`（厂商融合，免"8 字校准"），
  老设备退回加速度计 + 磁力计；两者都没有时 `hasCompass` 直接返回 false。
* 通信分两条通道：`MethodChannel .../compass`（`hasCompass` / `read`）负责探测与一次性读数，
  `EventChannel .../compassStream` 负责连续上报。
* 原生侧做两级节流（≥120ms 且变化 ≥1°），避免 50Hz 传感器事件把预览帧率拖下去。
* 文案口径收在 `HeadingPolicy`：`八方位` / `十六方位` / `仅角度`，纯函数可单测。
* **降级原则**：没有传感器 → `heading` 字段 `isAvailable` 为 false，整行不绘制；
  绝不按 0°（正北）或上一次读数编造。传感器精度差于 ±25° 时补「（精度低）」。
* 朝向在**快门瞬间冻结**，与时间、坐标一样进入 `CaptureContext`，转身不会改变水印。

### 11.4 设备能力探测与按钮降级

| 能力 | 探测方式 | 不可用时 |
| --- | --- | --- |
| 闪光灯 | 仅后置摄像头视为可用；`setFlashMode` 抛错则永久降级 | 按钮置灰 + tooltip「此摄像头无闪光灯」 |
| 变焦 | `getMaxZoomLevel()`，异常按 1x | 滑条换成「此设备不支持变焦」文案 |
| 多摄像头 | `availableCameras().length` | 切换按钮置灰 |
| 指南针 | 原生 `hasCompass` | 状态栏显示「无指南针」，字段不绘制 |

相机初始化失败按原因分类给出处置建议（缺权限 / 被占用 / 无摄像头），而不是把
插件抛出的英文原文丢给用户。

### 11.5 水印位置与角标

`WatermarkPosition` 四种：`bottomBar` / `bottomLeft` / `bottomRight` / `topBar`。

角标（现场拍摄 / 导入 · 非现场取证）的落位规则：

* 通栏：角标在底板内右上角，且其宽度**先**从可用文本宽度里扣掉，长文本不会压到角标底下；
* 浮块：角标移到底板**外侧上方**，与底板同侧对齐，不覆盖第一行文字。

