#!/usr/bin/env bash
# 青阳水印相机 · Android 平台目录现场生成器
#
# 仓库不提交 android/ 目录：CI 与本地都在构建前运行本脚本，
# 由 `flutter create` 生成平台骨架，再注入应用名、包名、权限、意图入口与签名配置。
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
PROJECT_NAME="qingyang_watermark"
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

# ---------------------------------------------------------------- 包名
GRADLE_GROOVY="android/app/build.gradle"
GRADLE_KTS="android/app/build.gradle.kts"

patch_gradle_common() {
  local file="$1"
  # applicationId
  if grep -qE '^\s*applicationId ' "$file"; then
    replace_in_file "$file" "s#^\([[:space:]]*\)applicationId .*#\1applicationId \"$APP_ID\"#"
  fi
  if grep -qE '^\s*applicationId = ' "$file"; then
    replace_in_file "$file" "s#^\([[:space:]]*\)applicationId = .*#\1applicationId = \"$APP_ID\"#"
  fi
  # namespace
  if grep -qE '^\s*namespace ' "$file"; then
    replace_in_file "$file" "s#^\([[:space:]]*\)namespace .*#\1namespace \"$APP_ID\"#"
  fi
  if grep -qE '^\s*namespace = ' "$file"; then
    replace_in_file "$file" "s#^\([[:space:]]*\)namespace = .*#\1namespace = \"$APP_ID\"#"
  fi
  # minSdk：camera / permission_handler 需要 21+，这里统一起到 24
  if grep -q 'flutter.minSdkVersion' "$file"; then
    replace_in_file "$file" 's#flutter.minSdkVersion#24#g'
  fi
  if grep -q 'minSdk = flutter.minSdkVersion' "$file"; then
    replace_in_file "$file" 's#minSdk = flutter.minSdkVersion#minSdk = 24#g'
  fi
}

if [ -f "$GRADLE_GROOVY" ]; then
  patch_gradle_common "$GRADLE_GROOVY"
  cat >> "$GRADLE_GROOVY" <<'GRADLE_EOF'

// ---------------------------------------------------------------------------
// 由 scripts/bootstrap_android.sh 注入
// 签名密钥不入库：从环境变量写入 android/key.properties 后再读取。
// 未配置时保持 Flutter 默认的调试签名，并在日志里告警。
// ---------------------------------------------------------------------------
def qyKeyFile = rootProject.file('key.properties')
def qyKeyProps = new Properties()
if (qyKeyFile.exists()) {
    qyKeyProps.load(new FileInputStream(qyKeyFile))
}

android {
    signingConfigs {
        if (qyKeyFile.exists()) {
            release {
                storeFile file(qyKeyProps['storeFile'])
                storePassword qyKeyProps['storePassword']
                keyAlias qyKeyProps['keyAlias']
                keyPassword qyKeyProps['keyPassword']
            }
        }
    }
    buildTypes {
        release {
            if (qyKeyFile.exists()) {
                signingConfig signingConfigs.release
            } else {
                logger.warn('[qingyang] 未找到 key.properties，release 将使用调试签名')
            }
        }
    }
}
GRADLE_EOF
  echo "[bootstrap] build.gradle 已注入包名与签名配置"
fi

if [ -f "$GRADLE_KTS" ]; then
  patch_gradle_common "$GRADLE_KTS"
  cat >> "$GRADLE_KTS" <<'KTS_EOF'

// ---------------------------------------------------------------------------
// 由 scripts/bootstrap_android.sh 注入（Kotlin DSL）
// 签名密钥不入库：未配置时回退调试签名。
// ---------------------------------------------------------------------------
val qyKeyFile = rootProject.file("key.properties")
val qyKeyProps = java.util.Properties()
if (qyKeyFile.exists()) {
    qyKeyProps.load(java.io.FileInputStream(qyKeyFile))
}

android {
    signingConfigs {
        if (qyKeyFile.exists()) {
            create("release") {
                storeFile = file(qyKeyProps["storeFile"] as String)
                storePassword = qyKeyProps["storePassword"] as String
                keyAlias = qyKeyProps["keyAlias"] as String
                keyPassword = qyKeyProps["keyPassword"] as String
            }
        }
    }
    buildTypes {
        if (qyKeyFile.exists()) {
            getByName("release") {
                signingConfig = signingConfigs.getByName("release")
            }
        } else {
            logger.warn("[qingyang] 未找到 key.properties，release 将使用调试签名")
        }
    }
}
KTS_EOF
  echo "[bootstrap] build.gradle.kts 已注入包名与签名配置"
fi

# ---------------------------------------------------------------- MainActivity
KOTLIN_DIR="android/app/src/main/kotlin/com/qingyang/watermark"
rm -rf android/app/src/main/kotlin/com/qingyang/qingyang_watermark
mkdir -p "$KOTLIN_DIR"
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
 * 2. 接收 ACTION_SEND image/*，把分享进来的图片复制到缓存目录，供 Dart 侧导入；
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
