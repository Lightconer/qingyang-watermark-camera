#!/usr/bin/env python3
"""APK 结构体检：发版前的最后一道闸。

`apksigner verify` 只校验证书与签名块，不关心 zip 内部布局；
而「解析包时出现问题」有一半来自布局：
  * resources.arsc 被压缩或未 4 字节对齐 -> INSTALL_PARSE_FAILED_RESOURCES_ARSC_COMPRESSED
  * native 库被压缩 -> Android 10+ 直接拒绝（extractNativeLibs=false 时）
  * 缺少 v1 签名 -> 部分国产 ROM 安装器判定包损坏

用法：
    python3 scripts/verify_apk.py <apk> [<apk> ...]
全部检查通过退出码为 0；任何一项失败退出码为 1。
"""

import struct
import sys
import zipfile

# 必须保持未压缩且 4 字节对齐的条目（Android 11+ 的安装器强校验）。
ALIGNED_ENTRIES = {"resources.arsc"}
SO_PREFIX = "lib/"
SIGN_BLOCK_MAGIC = b"APK Sig Block 42"


class Report:
    def __init__(self, path):
        self.path = path
        self.errors = []
        self.infos = []

    def fail(self, msg):
        self.errors.append(msg)

    def info(self, msg):
        self.infos.append(msg)


def signing_block_present(zf, raw):
    """在中央目录之前查找 APK Signing Block（v2/v3 的位置）。"""
    try:
        cd_offset = zf.start_dir
    except AttributeError:  # pragma: no cover - 极老 Python
        return None
    # 签名块紧贴中央目录之前，末尾 16 字节是 size + magic。
    tail_start = cd_offset - 16
    if tail_start < 0:
        return None
    tail = raw[tail_start:cd_offset]
    return SIGN_BLOCK_MAGIC in tail


def check(path):
    rep = Report(path)
    try:
        raw = open(path, "rb").read()
    except OSError as exc:
        rep.fail(f"无法读取文件：{exc}")
        return rep

    if len(raw) < 1024:
        rep.fail("文件过小，几乎可以确定是下载不完整")
        return rep

    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        rep.fail("不是合法的 zip 包（下载被截断或文件损坏）")
        return rep

    with zf:
        bad = zf.testzip()
        if bad is not None:
            rep.fail(f"zip 条目 CRC 校验失败：{bad}")

        names = set(zf.namelist())
        if "AndroidManifest.xml" not in names:
            rep.fail("缺少 AndroidManifest.xml，安装器无法解析")

        # ---- resources.arsc ----
        for entry in ALIGNED_ENTRIES:
            if entry not in names:
                if entry == "resources.arsc":
                    rep.fail("缺少 resources.arsc")
                continue
            info = zf.getinfo(entry)
            if info.compress_type != zipfile.ZIP_STORED:
                rep.fail(f"{entry} 被压缩（compress_type={info.compress_type}），"
                         "Android 11+ 会报资源解析失败")
            # local header 才是安装器读取的位置
            offset = info.header_offset
            name_len = struct.unpack("<H", raw[offset + 26:offset + 28])[0]
            extra_len = struct.unpack("<H", raw[offset + 28:offset + 30])[0]
            data_offset = offset + 30 + name_len + extra_len
            if data_offset % 4 != 0:
                rep.fail(f"{entry} 未 4 字节对齐（offset={data_offset}）")

        # ---- native 库 ----
        sos = [n for n in names if n.startswith(SO_PREFIX) and n.endswith(".so")]
        if not sos:
            rep.fail("没有任何 native 库，Flutter 引擎缺失")
        compressed = [n for n in sos if zf.getinfo(n).compress_type != zipfile.ZIP_STORED]
        if compressed:
            rep.fail(f"{len(compressed)} 个 .so 被压缩（应为 STORED），"
                     f"例如 {compressed[0]}")

        abis = sorted({n.split("/")[1] for n in sos if n.count("/") >= 2})
        rep.info(f"ABI: {', '.join(abis) if abis else '无'}")

        # native 库对齐粒度：16 KB 页是新机型的要求，4 KB 是旧标准。
        # 只报告不判错——build-tools 太老时回退 4 KB 是预期行为。
        so_offsets = []
        for name in sos:
            info = zf.getinfo(name)
            offset = info.header_offset
            name_len = struct.unpack("<H", raw[offset + 26:offset + 28])[0]
            extra_len = struct.unpack("<H", raw[offset + 28:offset + 30])[0]
            so_offsets.append(offset + 30 + name_len + extra_len)
        if so_offsets:
            if all(o % 16384 == 0 for o in so_offsets):
                rep.info("native 库对齐：16 KB")
            elif all(o % 4096 == 0 for o in so_offsets):
                rep.info("native 库对齐：4 KB（16 KB 页设备可能装不上）")
            else:
                rep.fail("native 库未按 4 KB 对齐，安装器可能拒绝")

        # ---- 签名 ----
        has_v1 = any(
            n.startswith("META-INF/") and n.upper().endswith((".RSA", ".DSA", ".EC"))
            for n in names
        )
        if not has_v1:
            rep.fail("缺少 v1 签名（META-INF/*.RSA），国产 ROM 可能报「解析包失败」")

        block = signing_block_present(zf, raw)
        if block is None:
            rep.fail("找不到 APK Signing Block（v2/v3 签名块）")
        elif not block:
            rep.fail("缺少 v2/v3 签名，Android 7+ 会拒绝安装")

        # ---- 体量与条目 ----
        biggest = max(zf.infolist(), key=lambda i: i.file_size)
        if biggest.file_size > 200 * 1024 * 1024:
            rep.fail(f"单条目解压后有 {biggest.file_size / 1048576:.1f} MB，"
                     "超出安装器常见上限")
        rep.info(f"条目 {len(names)} 个，最大 {biggest.filename}"
                 f"（{biggest.file_size / 1048576:.1f} MB）")

    # EOCD 存在即认为中央目录完整；zipfile 能打开已说明这点，这里只报体积。
    rep.info(f"体积 {len(raw) / 1048576:.1f} MB")
    return rep


def main(argv):
    if len(argv) < 2:
        print("用法：python3 scripts/verify_apk.py <apk> [<apk> ...]", file=sys.stderr)
        return 2

    reports = [check(path) for path in argv[1:]]
    failed = 0
    for rep in reports:
        print(f"\n=== {rep.path} ===")
        for line in rep.infos:
            print(f"  · {line}")
        if rep.errors:
            failed += 1
            for line in rep.errors:
                print(f"  ✗ {line}")
        else:
            print("  ✓ 结构检查通过")

    if failed:
        # stdout 默认带缓冲、stderr 不带，CI 里两者合并时汇总会跑到明细前面，
        # 让人先看到"禁止发布"却不知道是哪个包出的错。先 flush 再报。
        sys.stdout.flush()
        print(f"\n{failed} 个包未通过结构检查，禁止发布", file=sys.stderr)
        return 1
    print("\n全部通过结构检查")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
