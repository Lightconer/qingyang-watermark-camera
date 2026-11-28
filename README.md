# 青阳水印相机

面向乡镇外勤、自然资源卫片执法、工程巡检、现场取证的**可信经纬水印相机**（Android 优先，架构兼容鸿蒙与后续 iOS）。

* 拍摄与导入的照片都会把水印**画进像素**，同时把采集事实写进 **EXIF + XMP**，形成双重留痕；
* 拍摄时间取 **NTP 授时**，坐标在**快门瞬间冻结**，生成后不可修改；
* 导入照片**必须区分来源**，禁止把旧图伪造成现场取证图；
* 本地优先、无广告、无付费弹窗、不强制云端，可完全断网离线使用。

---

## 下载与安装

APK 由 GitHub Releases 直接提供（每次发版自动构建）。当前最新版本：
[**v1.0.0**](../../releases/tag/v1.0.0)（APK + `SHA256SUMS.txt`）。

安装步骤：

1. 打开 [Releases](../../releases) 页面，下载最新的 `qingyang-watermark-vX.Y.Z.apk`；
2. 手机允许「安装未知来源应用」；
3. 安装后首次启动依次授予：**精确定位** → **相机** → **存储/相册**（Android 13+ 走系统 Photo Picker，不需要媒体权限）；
4. 校验安装包（可选）：

```bash
sha256sum -c SHA256SUMS.txt
```

系统要求：Android 7.0（API 24）及以上；相机、GPS。鸿蒙（HarmonyOS NEXT 之前的双框架版本）可直接安装运行。

> 当前流水线状态：`CI`（analyze + test）与 `Build APK` 在 `main` 上均为通过；
> `release.yml` 已实测可用（v1.0.0 由打标签自动产出）。APK 尚未在真机上做完整
> 功能回归，相机/导入/校验三条链路建议按 `docs/ARCHITECTURE.md` 的验收点自测。

---

## 三条流水线

| 流水线 | 触发 | 做什么 |
| --- | --- | --- |
| `ci.yml` | push `main`、PR | `bootstrap_android.sh` → `flutter analyze --no-fatal-infos --no-fatal-warnings` → `flutter test` |
| `build-apk.yml` | push `main`、PR、手动 | 构建 release APK → `zipalign` + `apksigner` 重签 → 上传 Actions 构件（保留 14 天） |
| `release.yml` | 推送 `v*` 标签、手动填版本号 | 构建 → 重签 → 生成 `qingyang-watermark-vX.Y.Z.apk` 与 `SHA256SUMS.txt` → 发布 GitHub Release |

仓库**不提交 `android/` 目录**：三条流水线都会先跑 `scripts/bootstrap_android.sh`，
用 `flutter create --org com.qingyang --project-name watermark` 现场生成平台骨架
（包名 `com.qingyang.watermark` 由参数直接生成，不改 Gradle DSL，避免 Kotlin/Groovy
两种 DSL 语法差异把构建改坏），再注入应用名「青阳水印相机」、权限与 `ACTION_SEND` 入口。

---

## 两种发版方式

> 发版前把 `pubspec.yaml` 的 `version` 与 `lib/core/models/types.dart` 里
> `AppIdentity.version` 改成同一个版本号（`versionName` 由标签驱动，常量只作兜底，
> 但两者不一致会让本地自测的更新提示错乱）。


### 方式一：打标签（推荐）

```bash
git tag v1.0.1
git push origin v1.0.1
```

`release.yml` 会用标签里的版本号作为 `--build-name`，`github.run_number` 作为
`--build-number`，产出 `qingyang-watermark-v1.0.1.apk` 并发布到 Releases。

### 方式二：网页手动触发

1. 打开仓库 **Actions → Release → Run workflow**；
2. `version` 填 `1.0.1`（不带 `v`），可选填发版说明；
3. 流水线会**自动创建并推送 `v1.0.1` 标签**，然后按同样流程构建与发布。

> 手动触发时如果标签已存在会跳过创建，直接用该标签发布。

---

## 签名密钥配置

密钥**不入库**。四个仓库 Secret 一次配置，之后所有构建自动使用：

| Secret | 含义 |
| --- | --- |
| `KEYSTORE_BASE64` | keystore 文件的 base64（`base64 -w0 release.jks`） |
| `KEYSTORE_PASSWORD` | keystore 口令 |
| `KEY_ALIAS` | key 别名 |
| `KEY_PASSWORD` | key 口令 |

生成 keystore（只做一次，本地保存好）：

```bash
keytool -genkeypair -v \
  -keystore release.jks -alias qingyang \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass '<STORE_PASSWORD>' -keypass '<KEY_PASSWORD>' \
  -dname "CN=Qingyang Watermark Camera, OU=Engineering, O=Qingyang, L=Hangzhou, ST=Zhejiang, C=CN"

base64 -w0 release.jks   # 复制输出到 KEYSTORE_BASE64
```

**未配置时**：`bootstrap_android.sh` 会清理 `key.properties` 并打印
`警告：未配置 KEYSTORE_BASE64，release 将回退调试签名`；`sign_apk.sh` 检测不到证书时
自动跳过重签，产物保持 Flutter 的调试签名——可安装，但不适合正式分发。

签名统一在构建末尾做（`zipalign -p -f 4` + `apksigner sign`，v1/v2 同时开启），
不在 Gradle 里配置 `signingConfigs`，这样无论平台目录是 Kotlin DSL 还是 Groovy DSL
生成，签名链路都只有一条、可复现。

---

## 模块扩展方式

架构是「四层单向依赖 + 五个扩展点」，详见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
与 [`docs/EXTENDING.md`](docs/EXTENDING.md)。

```
app  ──▶ features  ──▶ engines  ──▶ core
```

一句话版：

| 想加什么 | 加什么文件 | 改哪一行 |
| --- | --- | --- |
| 新水印字段（图斑编号、车牌、传感器） | 一个 `WatermarkFieldProvider` 实现 | `FeatureModule.fields` |
| 新图像处理（LOGO、人脸打码、防伪纹理） | 一个 `ImageMiddleware` 实现（取一个 order 空隙） | `FeatureModule.middlewares` |
| 新元数据来源（记录仪、工单系统） | 一个 `MetadataProvider` 实现 | `MetadataEngine(providers: [...])` |
| 新模式（督查、验收） | 一个 `assets/profiles/*.json` | `assets/profiles/index.json` |
| 新业务模块（工单、文书导出） | 一个 `FeatureModule` 实现 | `registry.register(...)` |

`WatermarkRenderer`、`LayoutEngine`、相机页、导入页、设置页都不需要改。

---

## 功能要点

**拍摄**
实时预览叠加「与出图同规则」的水印；前后摄切换、闪光灯、网格线、缩放；拍照 + 短视频录制；
北斗/GPS/网络融合定位、快门冻结坐标；有网取 NTP 与逆地理，无网只写 GPS 原始经纬度并标注
「离线采集，时间为本地系统时间」；定位失败标注「定位失败」，绝不写假地址假天气。

**导入**
三个入口：系统相册多选（Android 13+ Photo Picker / iOS PHPicker）、SAF 文件夹批量、`ACTION_SEND image/*` 分享进入。
预览网格里可统一套模板、也可单张换模板；先按 EXIF Orientation 转正再绘制；原图绝不覆盖，
成品存为 `原名_wm.jpg`；长边压到 4096 以内防 OOM；批量进度、单张进度、失败重试与原因。
原图**确有 GPS** 才显示经纬度地址，否则显示「无原始定位」——**没有手动输入坐标的入口**。
导入模式默认隐藏天气；检测到已有水印/XMP 标记则跳过，防二次叠加。

**水印与存储**
字段池：时间（秒）、经纬度、海拔、地址、天气、设备型号、采集人、单位、项目、备注、LOGO、
SHA256 小字、溯源二维码，逐项开关；模板 JSON 化，可导入导出、多套切换；
位置支持底部通栏/左下/右下，字号、颜色、描边、行距、透明度可调（文字必带描边，强光可读）；
按 `日期/camera|import` 分目录，可选同时保存原图；
**成品自动存入系统相册的独立相册**（默认 `Pictures/青阳水印相机/`，相册名可改、可整体关闭），
系统图库、微信、文件管理器都能直接取用——应用私有目录仍是校验与台账的事实源。

**远程更新**
设置页「更新」：查 GitHub Releases 判断版本，有新版本时给出说明与安装包大小，
一键「下载并安装」——下载完成后先核对发布附带的 `SHA256SUMS.txt`，哈希不符直接丢弃、
不安装；校验通过才交给系统安装器（系统弹窗确认，不做静默安装）。启动时会自动查一次
（默认开、24 小时节流），关掉开关即完全不发请求；更新源可改成你自己的 `owner/repo`。

**相册与校验**
按日期、模板、来源筛选；详情页展示完整水印原始信息与哈希，并可「存入系统相册」补齐历史照片；
内置校验工具比对像素哈希与 EXIF/XMP 戳记；台账导出 XLSX（文件名、来源、拍摄时间、处理时间、
经纬度、地址、备注、哈希）。

---

## 已知限制（诚实清单）

1. **视频水印目前是「预览叠加 + sidecar 记录」**，不是逐帧烧录。逐帧烧录需要 MediaCodec/GPU
   重编码，属于下一阶段（接口 `ImageMiddleware` 已留好插入点：order 650 的视频帧中间件）。
2. **HEIC / RAW** 依赖系统转码，部分机型会失败；失败时会明确提示「请先在相册导出为 JPEG」，
   不会静默产出坏图。JPG / PNG / WebP 全链路支持。
3. **iOS 尚未接入**（`AVFoundation` 版本待做）；当前工程只生成 Android 平台目录。
4. **相册写入只做了 Android**：Android 10+ 走 `MediaStore`，9 及以下写公共 `Pictures`
   目录后 `MediaScanner` 登记。iOS 版接入时需要补 `PHPhotoLibrary`（`addOnly` 权限）实现；
   桌面/测试环境返回「不支持」，不影响成品落盘。
5. **人脸打码**中间件默认关闭，需要外部人脸检测结果（`job.options['faceRects']`）才生效。
6. 校验工具的「像素层水印」一项是**戳记推定**，不是 OCR 识别；画面内容合规性仍需人工比对。
7. **应用内更新依赖 GitHub**：需要能访问 `api.github.com` 与 `objects.githubusercontent.com`
   （国内网络可能需要代理或改用可访问的镜像/分叉仓库）。安装仍走系统安装器，用户必须手动确认；
   Android 8+ 首次会要求授予「安装未知应用」权限。
8. 像素 golden 基线未入库：`flutter test --update-goldens` 在本地生成。CI 用的是
   「同输入两次渲染字节一致 + 水印确实改变像素」的确定性回归（`test/golden/`）。

---

## 本地开发

```bash
flutter pub get
bash scripts/bootstrap_android.sh     # 生成 android/ 并注入配置
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

目录：

```
lib/app       组装层（DI / 路由 / 注册表 / 外壳 / 主题）
lib/features  业务单元（拍摄 / 导入 / 模板 / 相册 / 校验 / 台账 / 设置）
lib/engines   能力引擎（渲染 / 编解码 / 元数据 / 定位 / 授时 / 逆地理 / 天气 / 哈希 / 存储 / 媒体）
lib/core      纯 Dart 领域层（模型 / 口径 / 排版 / 校验 / EXIF 编解码 / XLSX）
test/         core 单测、engines 单测、管线端到端、渲染确定性回归
```

## 隐私

* 不收集任何用户数据，不上传照片；
* 网络能力（NTP / 逆地理 / 天气 / 云备份）是四个独立开关，全部关闭后应用完全离线可用；
* 定位只用于给水印取坐标，不落库到任何服务器；
* 无广告 SDK、无统计 SDK、无内购。

## 许可

MIT
