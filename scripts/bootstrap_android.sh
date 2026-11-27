#!/usr/bin/env bash
# 青阳水印相机 · Android 平台目录现场生成器
#
# 仓库不提交 android/ 目录：CI 与本地都在构建前运行本脚本，
# 由 `flutter create` 生成平台骨架，再注入应用名、权限、意图入口。
#
# 包名不从外部 sed 打补丁：--org com.qingyang + --project-name watermark
# 生成出来就是 com.qingyang.watermark，namespace / applicationId / MainActivity
# 的包路径三者天然一致，也就不需要（也不应该）去改 Gradle DSL——
# Kotlin DSL 与 Groovy DSL 语法不同，改错一个字整个构建就编译不过。
#
# 签名也不在 Gradle 里做：release 产物统一交给 scripts/sign_apk.sh
# 用 zipalign + apksigner 重签，未配置 keystore 时该脚本自动跳过。
#
# 用法：bash scripts/bootstrap_android.sh
# 可选环境变量：
#   KEYSTORE_BASE64    base64 编码的 keystore（未配置则回退调试签名）
#   KEYSTORE_PASSWORD  证书库口令
#   KEY_ALIAS          key 别名
#   KEY_PASSWORD       key 口令
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="青阳水印相机"
APP_ID="com.qingyang.watermark"
PROJECT_NAME="watermark"
ORG="com.qingyang"

require_flutter() {
  if ! command -v flutter >/dev/null 2>&1; then
    echo "[bootstrap] 未找到 flutter，请先安装 Flutter stable 并加入 PATH" >&2
    exit 1
  fi
}

replace_in_file() {
  # $1=file $2=sed-expr
  local file="$1"
  local expr="$2"
  sed "$expr" "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

echo "[bootstrap] flutter: $(flutter --version | head -n 1)"
require_flutter

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[bootstrap] 在临时目录生成平台骨架…"
flutter create \
  --platforms=android \
  --org "$ORG" \
  --project-name "$PROJECT_NAME" \
  --description "青阳水印相机" \
  "$TMP_DIR/proj" >/dev/null

rm -rf android
cp -r "$TMP_DIR/proj/android" android
echo "[bootstrap] android/ 已生成"

# ---------------------------------------------------------------- 清单文件
MANIFEST="android/app/src/main/AndroidManifest.xml"
cat > "$MANIFEST" <<'MANIFEST_EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- 相机与定位：取证链路必需 -->
    <uses-permission android:name="android.permission.CAMERA" />
    <!-- 录制带水印视频时需要录音；仅拍照不触发 -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION" />

    <!-- 网络：NTP 授时 / 逆地理 / 天气，均为独立开关，可全部关闭 -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <!-- 存储：Android 13+ 走 Photo Picker 不需要媒体权限，仅旧系统保留读权限 -->
    <uses-permission
        android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />

    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
    <uses-feature android:name="android.hardware.location.gps" android:required="false" />

    <application
        android:label="青阳水印相机"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:requestLegacyExternalStorage="false">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">

            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />

            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

            <!-- 第三个导入入口：从任意图库 ACTION_SEND image/* 分享进来 -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="image/*" />
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
MANIFEST_EOF
echo "[bootstrap] AndroidManifest 已注入（应用名 / 权限 / ACTION_SEND）"

# ---------------------------------------------------------------- Gradle
# 只做一件事：把 minSdk 抬到 24（camera / permission_handler 的下限）。
# 这是纯 token 替换，Groovy DSL(`minSdkVersion 24`) 与 Kotlin DSL(`minSdk = 24`)
# 都成立，不引入任何新语法，避免脚本把构建脚本改坏。
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] || continue
  if grep -q 'flutter\.minSdkVersion' "$f"; then
    replace_in_file "$f" 's#flutter\.minSdkVersion#24#g'
    echo "[bootstrap] $(basename "$f")：minSdk 已抬到 24"
  fi
done

# ---------------------------------------------------------------- 根构建脚本
# `flutter create` 生成的根脚本是 Kotlin DSL。这里整体改写成 Groovy：
#   1) 根脚本只做仓库、输出目录与子工程编排，不碰 AGP 的任何 DSL 类型，
#      可以安全地用动态语言写；
#   2) AGP 9 把 `Project.android(Action<BaseAppModuleExtension>)` 的 Kotlin DSL
#      访问器标成了 DeprecationLevel.ERROR，Kotlin 版根脚本稍有不慎就编译不过；
#   3) 需要给所有插件子工程统一抬高 compileSdk（见下），Groovy 的动态属性
#      赋值比在 Kotlin DSL 里引用 AGP 扩展类更稳。
#
# 统一 compileSdk 的原因：部分插件（如 file_picker 8.x）自身仍声明 android-34，
# 而 flutter_plugin_android_lifecycle 要求依赖方编译在 36 以上，
# 否则会在 `:xxx:checkReleaseAarMetadata` 上直接失败。
rm -f android/build.gradle.kts
cat > android/build.gradle <<'ROOT_GRADLE_EOF'
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory.value(
    rootProject.layout.buildDirectory.dir("../../build").get()
)

subprojects {
    project.layout.buildDirectory.value(
        rootProject.layout.buildDirectory.get().dir(project.name)
    )
}

// 必须在下面 evaluationDependsOn(":app") 之前注册：那一句会立即触发 :app 的评估，
// 已评估过的工程再调 afterEvaluate 会直接抛错。
subprojects {
    afterEvaluate { p ->
        def ext = p.extensions.findByName("android")
        if (ext != null) {
            try {
                def current = ext.compileSdk
                if (current == null || current < 36) {
                    ext.compileSdk = 36
                    p.logger.lifecycle("[qingyang] ${p.name}: compileSdk ${current} -> 36")
                }
            } catch (Exception e) {
                p.logger.warn("[qingyang] ${p.name}: 覆盖 compileSdk 失败（${e.message}）")
            }
            // AGP 8+ 要求每个模块声明 namespace，个别老插件没写，这里用 group 兜底。
            if (ext.hasProperty("namespace") && !ext.namespace) {
                def guess = p.group == null ? "" : p.group.toString()
                if (guess.contains(".") && guess != "unspecified") {
                    ext.namespace = guess
                    p.logger.lifecycle("[qingyang] ${p.name}: namespace 兜底为 ${guess}")
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete) {
    delete(rootProject.layout.buildDirectory)
}
ROOT_GRADLE_EOF
echo "[bootstrap] android/build.gradle 已写入（Groovy，统一插件 compileSdk=36）"

# 打印实际生效的 DSL / AGP 版本，便于构建失败时定位（不参与构建逻辑）
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && echo "[bootstrap] 使用 $f"
done
if [ -f android/settings.gradle.kts ]; then
  grep -E 'com\.android\.application|org\.jetbrains\.kotlin\.android' android/settings.gradle.kts \
    | sed 's/^[[:space:]]*/[bootstrap] AGP/Kotlin 插件：/' || true
elif [ -f android/settings.gradle ]; then
  grep -E 'com\.android\.application|org\.jetbrains\.kotlin\.android' android/settings.gradle \
    | sed 's/^[[:space:]]*/[bootstrap] AGP/Kotlin 插件：/' || true
fi

# ---------------------------------------------------------------- MainActivity
KOTLIN_DIR="android/app/src/main/kotlin/com/qingyang/watermark"
rm -rf android/app/src/main/kotlin/com/qingyang/qingyang_watermark 2>/dev/null || true
mkdir -p "$KOTLIN_DIR"
# 注意：Kotlin 支持嵌套块注释，注释正文里不能再出现 /*，
# 之前写成 "ACTION_SEND image/*" 会让整段 KDoc 变成未闭合注释。
cat > "$KOTLIN_DIR/MainActivity.kt" <<'KOTLIN_EOF'
package com.qingyang.watermark

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * 宿主 Activity：只做三件事
 * 1. 暴露设备型号（水印"设备型号"字段）；
 * 2. 接收 ACTION_SEND（image 类型）分享，把图片复制到缓存目录，供 Dart 侧导入；
 * 3. 保证单实例（singleTop），避免分享时重复启动。
 */
class MainActivity : FlutterActivity() {
    private val sharedPaths = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.qingyang.watermark/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "model" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.qingyang.watermark/intent")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedImages" -> {
                        result.success(ArrayList(sharedPaths))
                        sharedPaths.clear()
                    }
                    else -> result.notImplemented()
                }
            }

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND) return
        val mime = intent.type ?: return
        if (!mime.startsWith("image/")) return
        val uri = streamUri(intent) ?: return
        copyToCache(uri)
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun copyToCache(uri: Uri) {
        try {
            val target = File(cacheDir, "shared_${System.currentTimeMillis()}.jpg")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            sharedPaths.add(target.absolutePath)
        } catch (_: Exception) {
            // 分享失败不影响主流程
        }
    }
}
KOTLIN_EOF
echo "[bootstrap] MainActivity.kt 已写入（设备型号 / ACTION_SEND）"

# ---------------------------------------------------------------- 签名
if [ -n "${KEYSTORE_BASE64:-}" ]; then
  echo "[bootstrap] 检测到 KEYSTORE_BASE64，写入签名证书"
  echo "$KEYSTORE_BASE64" | base64 -d > android/app/release.jks
  cat > android/key.properties <<PROPS_EOF
storeFile=release.jks
storePassword=${KEYSTORE_PASSWORD:-}
keyAlias=${KEY_ALIAS:-}
keyPassword=${KEY_PASSWORD:-}
PROPS_EOF
  echo "[bootstrap] key.properties 已生成（内容不入库）"
else
  rm -f android/key.properties
  echo "[bootstrap] 警告：未配置 KEYSTORE_BASE64，release 将回退调试签名"
fi

# ---------------------------------------------------------------- 收尾
if [ -f android/local.properties ]; then
  echo "[bootstrap] local.properties 已存在（SDK 路径由本机/CI 提供）"
fi

echo "[bootstrap] 完成：$APP_NAME / $APP_ID"
echo "[bootstrap] 下一步：flutter pub get && flutter build apk --release"
