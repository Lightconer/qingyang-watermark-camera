import '../models/photo_metadata.dart';
import '../models/profile_config.dart';
import '../models/types.dart';

enum PolicySeverity { notice, warn, block }

class PolicyIssue {
  const PolicyIssue({
    required this.code,
    required this.message,
    required this.severity,
  });

  final String code;
  final String message;
  final PolicySeverity severity;

  bool get isBlocking => severity == PolicySeverity.block;

  @override
  String toString() => '[$code] $message';
}

class PolicyReport {
  const PolicyReport(this.issues);

  final List<PolicyIssue> issues;

  bool get hasBlocking => issues.any((issue) => issue.isBlocking);
  bool get hasWarning =>
      issues.any((issue) => issue.severity == PolicySeverity.warn);
  bool get isClean => issues.isEmpty;

  List<String> get messages =>
      issues.map((issue) => issue.message).toList(growable: false);

  PolicyReport merge(PolicyReport other) =>
      PolicyReport([...issues, ...other.issues]);

  static const PolicyReport clean = PolicyReport(<PolicyIssue>[]);
}

/// 时间口径规则。离线时只允许系统时间，但必须在画面上标注"离线采集，时间为本地系统时间"。
class TimePolicyEvaluator {
  const TimePolicyEvaluator();

  PolicyReport evaluate({
    required ProfileConfig profile,
    required bool isImport,
    required CaptureContext capture,
    required PhotoMetadata original,
  }) {
    final issues = <PolicyIssue>[];

    if (isImport) {
      switch (profile.timePolicy) {
        case TimePolicyKind.originalOnly:
          if (original.takenAt == null) {
            issues.add(const PolicyIssue(
              code: 'time.original_missing',
              message: '原图无拍摄时间，水印标注"无原始时间"，不使用当前时间替代',
              severity: PolicySeverity.notice,
            ));
          }
          break;
        case TimePolicyKind.trustedRequired:
        case TimePolicyKind.anyAvailable:
          if (original.takenAt == null) {
            issues.add(const PolicyIssue(
              code: 'time.original_missing',
              message: '原图无拍摄时间',
              severity: PolicySeverity.notice,
            ));
          }
          break;
      }
      return PolicyReport(issues);
    }

    switch (profile.timePolicy) {
      case TimePolicyKind.trustedRequired:
        if (capture.timeAuthority != TimeAuthority.ntp) {
          issues.add(const PolicyIssue(
            code: 'time.ntp_unavailable',
            message: '未取得 NTP 授时，本次使用本地系统时间并已在画面标注',
            severity: PolicySeverity.warn,
          ));
        }
        break;
      case TimePolicyKind.originalOnly:
        // 拍摄链路不应使用该口径；出现即说明配置有误。
        issues.add(const PolicyIssue(
          code: 'time.policy_mismatch',
          message: '当前模式的时间口径仅适用于导入链路',
          severity: PolicySeverity.warn,
        ));
        break;
      case TimePolicyKind.anyAvailable:
        if (capture.timeAuthority == TimeAuthority.missing) {
          issues.add(const PolicyIssue(
            code: 'time.missing',
            message: '无可用时间，水印标注"时间未知"',
            severity: PolicySeverity.notice,
          ));
        }
        break;
    }
    return PolicyReport(issues);
  }
}

/// 坐标口径规则。任何模式都不允许手动输入坐标；导入链路只认原图 EXIF GPS。
class CoordPolicyEvaluator {
  const CoordPolicyEvaluator();

  PolicyReport evaluate({
    required ProfileConfig profile,
    required bool isImport,
    required CaptureContext capture,
    required PhotoMetadata original,
  }) {
    final issues = <PolicyIssue>[];

    if (isImport) {
      switch (profile.coordPolicy) {
        case CoordPolicyKind.originalOnly:
          if (!original.hasGps) {
            issues.add(const PolicyIssue(
              code: 'coord.no_original',
              message: '原图无 GPS 信息，水印显示"无原始定位"',
              severity: PolicySeverity.notice,
            ));
          }
          break;
        case CoordPolicyKind.deviceFixRequired:
          issues.add(const PolicyIssue(
            code: 'coord.policy_mismatch',
            message: '导入链路不可要求设备定位',
            severity: PolicySeverity.warn,
          ));
          break;
        case CoordPolicyKind.optional:
          if (!original.hasGps) {
            issues.add(const PolicyIssue(
              code: 'coord.no_original',
              message: '原图无 GPS 信息',
              severity: PolicySeverity.notice,
            ));
          }
          break;
      }
      return PolicyReport(issues);
    }

    switch (profile.coordPolicy) {
      case CoordPolicyKind.deviceFixRequired:
        if (!capture.hasPosition) {
          issues.add(const PolicyIssue(
            code: 'coord.fix_failed',
            message: '定位失败：本次拍摄水印标注"定位失败"，不写入虚假坐标',
            severity: PolicySeverity.warn,
          ));
        }
        break;
      case CoordPolicyKind.originalOnly:
        issues.add(const PolicyIssue(
          code: 'coord.policy_mismatch',
          message: '拍摄链路不可使用"仅原图定位"口径',
          severity: PolicySeverity.warn,
        ));
        break;
      case CoordPolicyKind.optional:
        if (!capture.hasPosition) {
          issues.add(const PolicyIssue(
            code: 'coord.fix_failed',
            message: '未取得定位，水印标注"定位失败"',
            severity: PolicySeverity.notice,
          ));
        }
        break;
    }
    return PolicyReport(issues);
  }
}

/// 时间排版口径：统一 `yyyy-MM-dd HH:mm:ss`，附带必要的口径标注。
class TimeText {
  const TimeText._();

  static String format(DateTime time) {
    final local = time.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  static String formatDate(DateTime time) {
    final local = time.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// 口径后缀：NTP 不标注；离线系统时间、原图时间需要标注。
  static String authoritySuffix(TimeAuthority authority) {
    switch (authority) {
      case TimeAuthority.ntp:
        return '';
      case TimeAuthority.system:
        return '（本地系统时间）';
      case TimeAuthority.originalExif:
        return '';
      case TimeAuthority.missing:
        return '（时间未知）';
    }
  }
}
