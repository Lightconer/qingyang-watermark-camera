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
    <!-- 远程更新：把下载好的 APK 交给 PackageInstaller 安装（用户仍需在系统界面确认） -->
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
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
    <!-- 方位角是可选能力：没有磁力计/旋转矢量的设备照样装、照样拍，
         只是水印不画方位角那一行（required=false 才不会在商店里被过滤掉）。 -->
    <uses-feature android:name="android.hardware.sensor.compass" android:required="false" />

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

        <!-- PackageInstaller 需要用户确认时会回这条广播，由接收器拉起系统确认界面 -->
        <receiver
            android:name=".InstallResultReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="com.qingyang.watermark.INSTALL_RESULT" />
            </intent-filter>
        </receiver>

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

// 关闭 release 的 lintVital 任务：
//   1) 构建门禁在 Dart 侧（flutter analyze + flutter test），Android lint 不参与；
//   2) camera_android_camerax 在 CI 的 JDK/AGP 组合下会让 lint 的 CommentDetector
//      崩溃（java.util.List.removeLast 不存在），属 lint 自身 bug，不该阻断出包。
subprojects {
    tasks.configureEach { t ->
        if (t.name.startsWith("lintVital")) {
            t.enabled = false
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

import android.Manifest
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * 宿主 Activity：只做六件事
 * 1. 暴露设备型号与版本号（水印字段 / 远程更新的当前版本）；
 * 2. 接收 ACTION_SEND（image 类型）分享，把图片复制到缓存目录，供 Dart 侧导入；
 * 3. 把成品写入系统相册的独立相册（MediaStore）；
 * 4. 把下载好的更新包交给 PackageInstaller 安装；
 * 5. 上报相机朝向（方位角），无传感器时明确回报不支持；
 * 6. 保证单实例（singleTop），避免分享时重复启动。
 */
class MainActivity : FlutterActivity() {
    private val sharedPaths = mutableListOf<String>()

    // ---- 方位角（指南针）----
    // 优先用 TYPE_ROTATION_VECTOR（厂商融合了磁力计 + 陀螺仪 + 加速度计），
    // 它比裸磁力计稳、不需要用户"8 字校准"；没有融合传感器的老设备再退回
    // 加速度计 + 磁力计的组合。
    private val sensorManager by lazy {
        getSystemService(SENSOR_SERVICE) as SensorManager
    }
    private var compassSink: EventChannel.EventSink? = null
    private var compassListening = false
    private var lastHeadingDegrees: Double? = null
    private var lastHeadingAccuracy: Double? = null
    private var lastCompassEmitAt = 0L
    private var gravityValues: FloatArray? = null
    private var magneticValues: FloatArray? = null
    private val rotationMatrix = FloatArray(9)
    private val orientationValues = FloatArray(3)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.qingyang.watermark/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "model" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    "version" -> result.success(versionName())
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.qingyang.watermark/gallery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "缺少图片路径", null)
                        } else {
                            val album = call.argument<String>("album") ?: "青阳水印相机"
                            val name = call.argument<String>("name") ?: File(path).name
                            try {
                                val uri = saveToGallery(path, album, name)
                                if (uri == null) {
                                    result.error("permission_required", "缺少写入相册的权限", null)
                                } else {
                                    result.success(uri)
                                }
                            } catch (error: Exception) {
                                result.error("io_error", error.message ?: "写入相册失败", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.qingyang.watermark/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "缺少安装包路径", null)
                        } else {
                            try {
                                result.success(startInstall(path))
                            } catch (error: Exception) {
                                result.error("install_failed", error.message ?: "无法启动安装", null)
                            }
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "缺少链接", null)
                        } else {
                            try {
                                startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (error: Exception) {
                                result.error("open_failed", error.message ?: "无法打开链接", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        registerCompassChannels(flutterEngine)
        handleIntent(intent)
    }

    /** 朝向通道：MethodChannel 负责能力探测与一次性读数，EventChannel 负责连续上报。 */
    private fun registerCompassChannels(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.qingyang.watermark/compass"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCompass" -> result.success(hasCompassSensor())
                "read" -> {
                    // 已经有值就直接给；没有就先挂上监听，让 Dart 侧的流去等第一帧。
                    if (lastHeadingDegrees == null) startCompassListening()
                    result.success(lastHeadingPayload())
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.qingyang.watermark/compassStream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                compassSink = events
                startCompassListening()
            }

            override fun onCancel(arguments: Any?) {
                compassSink = null
                stopCompassListening()
            }
        })
    }

    private fun hasCompassSensor(): Boolean {
        val rotation = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotation != null) return true
        return sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null &&
            sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null
    }

    private fun startCompassListening() {
        if (compassListening) return
        val rotation = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotation != null) {
            sensorManager.registerListener(compassListener, rotation, SensorManager.SENSOR_DELAY_UI)
        } else {
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let {
                sensorManager.registerListener(compassListener, it, SensorManager.SENSOR_DELAY_UI)
            }
            sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let {
                sensorManager.registerListener(compassListener, it, SensorManager.SENSOR_DELAY_UI)
            }
        }
        compassListening = true
    }

    private fun stopCompassListening() {
        if (!compassListening) return
        sensorManager.unregisterListener(compassListener)
        compassListening = false
        gravityValues = null
        magneticValues = null
    }

    private val compassListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            when (event.sensor.type) {
                Sensor.TYPE_ROTATION_VECTOR -> {
                    SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                    SensorManager.getOrientation(rotationMatrix, orientationValues)
                    emitHeading(
                        Math.toDegrees(orientationValues[0].toDouble()),
                        accuracyDegrees(event.accuracy)
                    )
                }
                Sensor.TYPE_ACCELEROMETER -> {
                    gravityValues = lowPass(event.values.clone(), gravityValues)
                    emitFromAccelAndMag()
                }
                Sensor.TYPE_MAGNETIC_FIELD -> {
                    magneticValues = lowPass(event.values.clone(), magneticValues)
                    emitFromAccelAndMag()
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    /** 低通滤波：手机在手里是会抖的，原始磁场读数直接上屏会变成"乱跳的罗盘"。 */
    private fun lowPass(input: FloatArray, output: FloatArray?): FloatArray {
        if (output == null) return input.copyOf()
        val alpha = 0.15f
        for (index in input.indices) {
            output[index] += alpha * (input[index] - output[index])
        }
        return output
    }

    private fun emitFromAccelAndMag() {
        val gravity = gravityValues ?: return
        val magnetic = magneticValues ?: return
        if (!SensorManager.getRotationMatrix(rotationMatrix, null, gravity, magnetic)) return
        SensorManager.getOrientation(rotationMatrix, orientationValues)
        emitHeading(Math.toDegrees(orientationValues[0].toDouble()), lastHeadingAccuracy)
    }

    /**
     * 上报朝向。传感器 50Hz 上报全部塞给 Dart 会拖垮预览帧率，
     * 这里做两级节流：至少间隔 120ms，且变化不足 1 度不重复发。
     */
    private fun emitHeading(degrees: Double, accuracy: Double?) {
        var normalized = degrees % 360.0
        if (normalized < 0) normalized += 360.0
        val previous = lastHeadingDegrees
        val delta = if (previous == null) 360.0 else {
            val raw = Math.abs(normalized - previous)
            Math.min(raw, 360.0 - raw)
        }
        val now = SystemClock.elapsedRealtime()
        lastHeadingAccuracy = accuracy
        if (previous != null && now - lastCompassEmitAt < 120 && delta < 1.0) return
        lastCompassEmitAt = now
        lastHeadingDegrees = normalized
        compassSink?.success(lastHeadingPayload())
    }

    private fun lastHeadingPayload(): Map<String, Any>? {
        val degrees = lastHeadingDegrees ?: return null
        val payload = HashMap<String, Any>()
        payload["degrees"] = degrees
        lastHeadingAccuracy?.let { payload["accuracy"] = it }
        return payload
    }

    /** 传感器精度等级换算成度数：HIGH 约正负 5 度。 */
    private fun accuracyDegrees(status: Int): Double? = when (status) {
        SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 5.0
        SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 15.0
        SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 30.0
        else -> 45.0
    }

    override fun onDestroy() {
        stopCompassListening()
        super.onDestroy()
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

    /**
     * 把图片放进系统相册的独立相册（Pictures/相册名/）。
     * 返回 content uri（Android 10+）或绝对路径（9 及以下）；缺权限返回 null。
     */
    private fun saveToGallery(sourcePath: String, album: String, name: String): String? {
        val source = File(sourcePath)
        if (!source.exists()) throw IllegalStateException("原文件不存在")

        val safeAlbum = album
            .replace("/", "_")
            .replace("\\", "_")
            .trim()
            .ifEmpty { "青阳水印相机" }
        val mime = if (name.endsWith(".png", ignoreCase = true)) "image/png" else "image/jpeg"

        // Android 9 及以下：写公共 Pictures 目录后交给 MediaScanner 登记，
        // 否则重启后相册里会看不到这张图。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val granted = checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) return null
            val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val dir = File(pictures, safeAlbum)
            if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("无法创建相册目录")
            val target = uniqueFile(dir, name)
            source.inputStream().use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
            return target.absolutePath
        }

        // Android 10+：走 MediaStore，先 IS_PENDING=1 再落盘，写完立即置 0，
        // 避免相册里出现写了一半的图片。
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/" + safeAlbum,
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("系统拒绝写入相册")
        try {
            val stream = contentResolver.openOutputStream(uri)
                ?: throw IllegalStateException("无法打开相册写入流")
            stream.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            }
        } catch (error: Exception) {
            // 写失败要清掉占位记录，否则相册里会留下一条空条目
            contentResolver.delete(uri, null, null)
            throw error
        }
        val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
        contentResolver.update(uri, done, null, null)
        return uri.toString()
    }

    /** 版本名：取 PackageManager 的真实值，发版改 versionName 后自动跟着变。 */
    private fun versionName(): String {
        return try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "0.0.0"
        } catch (_: Exception) {
            "0.0.0"
        }
    }

    /**
     * 用 PackageInstaller 会话安装 APK：不把文件抛给别的应用、也不依赖 FileProvider，
     * 系统用自己的安装界面走完确认流程（用户仍需手动点"安装"）。
     */
    private fun startInstall(apkPath: String): Int {
        val file = File(apkPath)
        if (!file.exists()) throw IllegalStateException("安装包不存在")
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            file.inputStream().use { input ->
                session.openWrite("base.apk", 0, file.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val status = Intent(InstallResultReceiver.ACTION).setPackage(packageName)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pending = PendingIntent.getBroadcast(this, sessionId, status, flags)
            session.commit(pending.intentSender)
        }
        return sessionId
    }

    /** 同名时追加序号，绝不覆盖相册里已有的图。 */
    private fun uniqueFile(dir: File, name: String): File {
        val base = name.substringBeforeLast('.', name)
        val ext = if (name.contains('.')) name.substringAfterLast('.') else "jpg"
        var candidate = File(dir, name)
        var index = 1
        while (candidate.exists()) {
            candidate = File(dir, base + "_" + index + "." + ext)
            index++
        }
        return candidate
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
echo "[bootstrap] MainActivity.kt 已写入（设备型号 / 版本号 / ACTION_SEND / 相册写入 / 安装 / 方位角）"

cat > "$KOTLIN_DIR/InstallResultReceiver.kt" <<'RECEIVER_EOF'
package com.qingyang.watermark

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * PackageInstaller 的回调接收器。
 *
 * 会话提交后系统不会直接弹确认框，而是回一条 STATUS_PENDING_USER_ACTION 广播，
 * 由接收器把系统给的确认 Intent 拉起来。缺少这一步的表现是：
 * 调用成功但屏幕上什么都不发生。清单里必须声明 exported="false"，
 * 广播由本应用自己发出的 PendingIntent 触发，不需要对外开放。
 */
class InstallResultReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) return
        val confirm = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
        confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        confirm?.let { context.startActivity(it) }
    }

    companion object {
        const val ACTION = "com.qingyang.watermark.INSTALL_RESULT"
    }
}
RECEIVER_EOF
echo "[bootstrap] InstallResultReceiver.kt 已写入（安装确认回调）"

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
