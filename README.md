# 青阳水印相机

面向乡镇外勤、自然资源卫片执法、工程巡检、现场取证的**可信经纬水印相机**（Android 优先，架构兼容鸿蒙与后续 iOS）。

* 拍摄与导入的照片都会把水印**画进像素**，同时把采集事实写进 **EXIF + XMP**，形成双重留痕；
* 拍摄时间取 **NTP 授时**，坐标在**快门瞬间冻结**，生成后不可修改；
* 导入照片**必须区分来源**，禁止把旧图伪造成现场取证图；
* 本地优先、无广告、无付费弹窗、不强制云端，可完全断网离线使用。

---

## 下载与安装

APK 由 GitHub Releases 直接提供（每次发版自动构建）。当前最新版本：
[**v1.4.0**](../../releases/tag/v1.4.0)（分架构 APK + `SHA256SUMS.txt`）。

### 该下哪个包

从 v1.4.0 起按 CPU 架构拆包——通用包会把三套 Flutter 引擎全塞进来，
54 MB 里有近 30 MB 是这台手机永远用不到的另一套 native 库。拆开后单包只有 19 MB 左右，
下载中断（也就是「解析包时出现问题」最常见的成因）的概率随之大幅下降。

| 文件 | 适用设备 | 体积（v1.4.0 实测） |
| --- | --- | --- |
| `qingyang-watermark-vX.Y.Z-arm64-v8a.apk` | **绝大多数手机**（2016 年以后的机型，首选；荣耀 Power 2 用这个） | 19.26 MB |
| `qingyang-watermark-vX.Y.Z-armeabi-v7a.apk` | 32 位老设备 / 低端机（arm64 包装不上时再用） | 17.24 MB |

拿不准就下 `arm64-v8a`。**装错了不会损坏任何数据**，系统只会提示「应用未安装」或
「解析包时出现问题」，换另一个包即可。

### 安装步骤

1. 打开 [Releases](../../releases) 页面，按上表下载对应的 `.apk`；
2. 手机允许「安装未知来源应用」（给浏览器或文件管理器授权，不是给本应用）；
3. 安装后首次启动依次授予：**精确定位** → **相机** → **存储/相册**
   （Android 13+ 走系统 Photo Picker，不需要媒体权限）；
4. 校验安装包（可选，推荐——能直接排除「下载不完整」）：

```bash
# 清单里同时列了两只架构包，只挑自己下载的那只校验即可
grep 'arm64-v8a' SHA256SUMS.txt | sha256sum -c -
# 若下的是 32 位包：grep 'armeabi-v7a' SHA256SUMS.txt | sha256sum -c -
```

### 报「解析包时出现问题」怎么办

按可能性从高到低排查：

1. **下载不完整**（最常见）。GitHub 在国内访问不稳，54 MB 的包断在一半就是这种报错。
   换成体积更小的 `arm64-v8a` 包重下，或用下载工具续传；下完先对 `SHA256SUMS.txt` 校验。
2. **装错了架构**。32 位设备装 arm64 包。换 `armeabi-v7a` 包。
3. **ROM 拦截**。荣耀 / 华为 / 小米 / OPPO 的「纯净模式」「应用管控」会静默改写安装流程：
   - 荣耀 MagicOS：设置 → 安全 → 更多安全设置 → 外部来源应用下载 → 允许对应应用；
     关掉「纯净模式」（设置 → 安全和隐私 → 纯净模式）。
   - 小米 HyperOS：设置 → 应用设置 → 授权管理 → 未知来源安装。
4. **系统版本低于 Android 7.0**。本应用最低 API 24。

自 v1.4.0 起，应用内更新会先让系统解析一遍下载好的包，坏了当场删掉并说明原因，
不会再把「解析包时出现问题」这种没有线索的提示丢给用户。

系统要求：Android 7.0（API 24）及以上；相机、GPS。
鸿蒙（HarmonyOS NEXT 之前的双框架版本）可直接安装运行。

> 当前流水线状态：`CI`（analyze + test）、`Build APK`、`Release` 均为通过。
> 发版产物在发布前会跑一遍结构体检（`scripts/verify_apk.py`）：
> `resources.arsc` 必须未压缩且 4 字节对齐、native 库必须 STORED、
> v1/v2/v3 签名必须齐全——任何一项不过，流水线直接红，不产出装不上的包。

---

## 三条流水线

| 流水线 | 触发 | 做什么 |
| --- | --- | --- |
| `ci.yml` | push `main`、PR | `bootstrap_android.sh` → `flutter analyze --no-fatal-infos --no-fatal-warnings` → `flutter test` |
| `build-apk.yml` | push `main`、PR、手动 | `scripts/build_release.sh`：分 ABI 构建 → zipalign + apksigner 重签 → 结构体检 → 上传 Actions 构件（保留 14 天） |
| `release.yml` | 推送 `v*` 标签、手动填版本号 | 同上，产物为 `qingyang-watermark-vX.Y.Z-{arm64-v8a,armeabi-v7a}.apk` 与 `SHA256SUMS.txt` → 发布 GitHub Release |

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

最省事的是跑现成脚本：自动找 `keytool`（找不到就退回 `openssl`）、生成随机强口令，
把 4 条**填好值**的 `gh secret set` 命令打印出来并存成文件：

```bash
bash scripts/setup_signing.sh             # 生成证书 + 打印命令（默认，不写 GitHub）
bash scripts/setup_signing.sh --print     # 忘了命令时重打，复用已有证书，不会换证书
bash scripts/setup_signing.sh --apply     # 生成后直接写入仓库 Secrets（需已登录 gh）
```

生成物落在 `dist/`（已被 `.gitignore` 忽略）：`release.jks`、`keystore.base64`、
`signing-secrets.txt`（4 个明文值）、`secret-commands.txt`（4 条填好值的命令，打开即可整段复制）。
**这些文件要另外离线备份**，私钥丢了就再也无法给老用户升级。

> 没有 JDK 也能用：脚本会用系统自带的 openssl 生成 PKCS12 证书（alias 固定 `qingyang`，
> 有效期到 2054 年），apksigner 按内容识别 keystore 类型，两种来源都能读。

也可以手工生成 keystore（只做一次，本地保存好）：

```bash
keytool -genkeypair -v \
  -keystore release.jks -alias qingyang \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass '<STORE_PASSWORD>' -keypass '<KEY_PASSWORD>' \
  -dname "CN=Qingyang Watermark Camera, OU=Engineering, O=Qingyang, L=Hangzhou, ST=Zhejiang, C=CN"

base64 -w0 release.jks   # 复制输出到 KEYSTORE_BASE64
```

**未配置时**：`bootstrap_android.sh` 会清理 `key.properties`；`sign_apk.sh` **不会跳过重签**，
而是改用 AGP 刚用过的调试证书（`~/.android/debug.keystore`）重签，把 v1/v2/v3 补齐。
这正是修复「解析包时出现问题」的关键：`minSdk 24` 时 AGP 默认**不生成 v1**，
而部分国产 ROM 的安装器发现包里没有 `META-INF/*.RSA` 就判「包损坏」——
v1.3.0 及以前所有发布包都踩了这个坑（详见 `docs/ARCHITECTURE.md` 第 10.2 节）。

⚠️ **务必配置这四个 Secret**：未配置时 CI 用的是 Flutter 在临时容器里现生成的调试证书，
**每次构建都不一样**。后果是用户装过一版就再也覆盖不了下一版——系统会报
「应用未安装」或「与已安装应用签名不一致」，而且这和「解析包时出现问题」很容易被混淆。
配置之后每次发布的证书指纹相同，升级才是连续的。

签名统一在构建末尾做（`zipalign` 先试 16 KB 页对齐、不支持则回退 4 KB，
再 `apksigner sign`；逐项加固的原因见 `docs/ARCHITECTURE.md` 第 10.2 节），
不在 Gradle 里配置 `signingConfigs`，这样无论平台目录是 Kotlin DSL 还是 Groovy DSL
生成，签名链路都只有一条、可复现。

### 发版前自检

```bash
bash scripts/build_release.sh 1.4.0 1     # 构建 + 签名 + 结构体检，产物在 dist/
python3 scripts/verify_apk.py dist/*.apk  # 单独体检已有产物
```

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

**方位角（对标元道经纬相机）**
读取设备方向传感器，把**相机朝向**写进水印（`方位角 东北 42°`），快门瞬间冻结；
支持八方位 / 十六方位 / 仅角度三种写法；无磁力计的设备整行不显示（不编 0°），
精度差于 ±25° 时标注「（精度低）」；可在设置里整体关闭以省电。

**机型适配**
水印永远在**成片坐标系**里排版，再映射到屏幕，所以 19.5:9、20:9、平板 4:3 下位置与字号都一致；
取景可选「按照片比例留边（默认，所见即所得）」或「裁切铺满（画面更饱满）」；
闪光灯/变焦/多摄像头/指南针逐项探测，不可用就置灰并说明原因，而不是点了没反应；
相机启动失败按「缺权限 / 被其他应用占用 / 无摄像头」分类给出处置建议。

**导入**
三个入口：系统相册多选（Android 13+ Photo Picker / iOS PHPicker）、SAF 文件夹批量、`ACTION_SEND image/*` 分享进入。
预览网格里可统一套模板、也可单张换模板；先按 EXIF Orientation 转正再绘制；原图绝不覆盖，
成品存为 `原名_wm.jpg`；长边压到 4096 以内防 OOM；批量进度、单张进度、失败重试与原因。
原图**确有 GPS** 才显示经纬度地址，否则显示「无原始定位」——**没有手动输入坐标的入口**。
导入模式默认隐藏天气；检测到已有水印/XMP 标记则跳过，防二次叠加。

**水印与存储**
字段池：时间（秒）、经纬度、**方位角**、海拔、地址、天气、设备型号、采集人、单位、项目、备注、LOGO、
SHA256 小字、溯源二维码，逐项开关；模板 JSON 化，可导入导出、多套切换；
内置 9 套场景模板（取证标准 / 精简两行 / 工程巡检 / 物业巡检 / 销售拜访 / 考勤打卡 / 执法取证 /
测绘记录 / 导入留痕）；
位置支持底部通栏/左下/右下/顶部通栏，字号、颜色、描边、行距、透明度可调（文字必带描边，强光可读）；
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
9. **方位角是磁北口径**，且依赖设备传感器质量：手机靠近金属、车内、强磁环境下会偏，
   精度差时会自动标注「（精度低）」。它用于说明「朝哪边拍」，不用于测绘定向；
   需要真北或高精度定向时请用专业罗盘/RTK 设备。

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
