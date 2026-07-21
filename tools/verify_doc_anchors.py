#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
docs/reference/ 索引锚点校验器

CLAUDE.md 要求"commit 前检查索引与代码一致性"，本脚本把它变成一条命令。

校验对象：docs/reference/*.md 里形如 `some_file.gd:123 symbol_name` 的锚点。
判定规则：symbol 必须出现在 该文件:第123行 的 ±3 行窗口内。
  - 只有 `file.gd:123` 而不带符号 → 只校验行号未超出文件长度（弱校验）
  - 带符号 → 强校验（这是我们真正想守住的）

用法：
    python tools/verify_doc_anchors.py              # 全量，只报错
    python tools/verify_doc_anchors.py --verbose    # 连通过的也列出来
    python tools/verify_doc_anchors.py --doc code-index.md
    python tools/verify_doc_anchors.py --section 无线电通讯   # 只校验某段

退出码：0 = 全部一致；1 = 存在腐烂锚点。

⚠ 已知：code-index.md 顶部有 2026-04-22 大重构的过期警告，`aircraft.gd:xxx` /
`ai_controller.gd:xxx` 系列锚点大面积失效（代码已拆到子模块）。那批属于历史欠债，
本脚本会如实报出来 —— 修一段就少一段，不要因为数字大就忽略新增的腐烂。
"""

import argparse
import io
import os
import re
import sys

# Windows 控制台默认 cp936（gbk），打印 ✓ / 中文会抛 UnicodeEncodeError，
# 让"其实全绿"的一次运行以非零退出码收场 —— 假失败比真失败更浪费时间。
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

REF_DIR = os.path.join('docs', 'reference')
WINDOW = 3   # 符号允许偏离锚点行的行数

# 扫描范围。docs/changelogs/ 【刻意不扫】—— 它是"某次改动当时做了什么"的历史快照，
# 里面的行号描述的是【当时】的代码，改它等于篡改历史（见 specs/_INDEX.md 分层约定表）。
SCAN_DIRS = [
    os.path.join('docs', 'reference'),
    os.path.join('docs', 'systems'),
    os.path.join('docs', 'architecture'),
    os.path.join('docs', 'planning'),
    os.path.join('docs', 'specs'),
]
SCAN_FILES = ['CLAUDE.md']

# docs/specs/ 【禁止出现行号】（specs/_INDEX.md 硬约定：spec 是权威源，行号易腐烂，
# 指针一律放 docs/reference/）。这里出现行号本身就是违规，不管它当下准不准。
NO_LINENO_DIRS = [os.path.join('docs', 'specs')]

# `file.gd:123` 后面可选跟一个符号名（符号可能被反引号包着，如 `:295` `_pick_enemy_type`）
ANCHOR_RE = re.compile(
    r'`?([A-Za-z_0-9/]+\.gd):(\d+)`?(?:\s*`?([A-Za-z_][A-Za-z_0-9]*)`?)?')

# 这些词跟在行号后面时不是符号名，是中文说明的一部分或表格分隔
NOT_SYMBOLS = {
    'x', 'X', 'and', 'or', 'the', 'to', 'in', 'at', 'of',
}


def build_script_index(root='scripts'):
    index = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.endswith('.gd'):
                index.setdefault(fn, os.path.join(dirpath, fn))
    return index


def read_lines(path):
    with io.open(path, encoding='utf-8') as f:
        return f.read().split('\n')


# script-index.md 是表格：第一列 `| \`path/file.gd\` |`，行内锚点写成裸 `:123 symbol`。
# 这类行要先认出"本行属于哪个文件"，再解析裸行号。
ROW_FILE_RE = re.compile(r'^\|\s*`([A-Za-z_0-9/]+\.gd)`')
BARE_RE = re.compile(r'`:(\d+)`(?:\s*`?([A-Za-z_][A-Za-z_0-9]*)`?)?')


def collect_anchors(doc_path, section=None):
    text = io.open(doc_path, encoding='utf-8').read()
    if section:
        if section not in text:
            return []
        start = text.index(section)
        # 只在【同级或更高级】标题处收尾：section 以几个 # 开头，就找几个及以下的 #
        level = len(section) - len(section.lstrip('#'))
        level = max(level, 1)
        rest = text[start + len(section):]
        m = re.search(r'\n#{1,%d} ' % level, rest)
        text = text[start:start + len(section) + (m.start() if m else len(rest))]

    out = []
    for line_no, line in enumerate(text.split('\n'), 1):
        # 1) 完整形式 file.gd:123 symbol
        for m in ANCHOR_RE.finditer(line):
            sym = m.group(3)
            if sym in NOT_SYMBOLS:
                sym = None
            out.append((line_no, m.group(1), int(m.group(2)), sym))
        # 2) 表格行内的裸 `:123 symbol` —— 归属本行第一列声明的文件
        row = ROW_FILE_RE.match(line)
        if row:
            owner = row.group(1)
            for m in BARE_RE.finditer(line):
                sym = m.group(2)
                if sym in NOT_SYMBOLS:
                    sym = None
                out.append((line_no, owner, int(m.group(1)), sym))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--doc', help='只校验某个文档（文件名）')
    ap.add_argument('--section', help='只校验含该标题的段落')
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    if not os.path.isdir(REF_DIR):
        print('找不到 %s —— 请在项目根目录运行' % REF_DIR)
        return 2

    scripts = build_script_index()
    cache = {}

    docs = []
    for d in SCAN_DIRS:
        if not os.path.isdir(d):
            continue
        for dp, _dn, fns in os.walk(d):
            for fn in sorted(fns):
                if fn.endswith('.md'):
                    docs.append(os.path.join(dp, fn))
    for f in SCAN_FILES:
        if os.path.isfile(f):
            docs.append(f)

    if args.doc:
        docs = [d for d in docs if os.path.basename(d) == os.path.basename(args.doc)]
        if not docs:
            print('没有匹配的文档：%s' % args.doc)
            return 2

    total = 0
    stale = []
    weak = 0
    layering = []

    for doc_path in docs:
        doc = os.path.relpath(doc_path).replace('\\', '/')
        in_spec = any(doc_path.replace('\\', '/').startswith(d.replace('\\', '/'))
                      for d in NO_LINENO_DIRS)
        for doc_line, fname, ln, sym in collect_anchors(doc_path, args.section):
            total += 1
            if in_spec:
                layering.append((doc, doc_line,
                                 'spec 内禁止写行号（%s:%d）—— 指针请放 docs/reference/'
                                 % (fname, ln)))
                continue
            base = os.path.basename(fname)
            path = scripts.get(base)
            if path is None:
                stale.append((doc, doc_line, '文件不存在: %s' % fname))
                continue
            if path not in cache:
                cache[path] = read_lines(path)
            lines = cache[path]
            if ln > len(lines):
                stale.append((doc, doc_line,
                              '%s:%d 超出文件长度 (%d 行)' % (fname, ln, len(lines))))
                continue
            if not sym:
                weak += 1
                continue
            window = '\n'.join(lines[max(0, ln - 1 - WINDOW): ln + WINDOW])
            if sym not in window:
                actual = lines[ln - 1].strip()[:60]
                stale.append((doc, doc_line,
                              '%s:%d 附近无 %r  → 实际: %s' % (fname, ln, sym, actual)))
            elif args.verbose:
                print('  OK  %s:%d  %s:%d %s' % (doc, doc_line, fname, ln, sym))

    print('扫描 %d 份文档、锚点 %d 个（其中 %d 个未带符号，仅弱校验）'
          % (len(docs), total, weak))
    print('（docs/changelogs/ 刻意不扫：历史快照，行号描述的是当时的代码）')

    if layering:
        print('\n分层违规 %d 个（spec 里不该出现行号）：' % len(layering))
        for doc, doc_line, msg in layering:
            print('  %s L%-5d %s' % (doc, doc_line, msg))

    if stale:
        print('\n腐烂锚点 %d 个：' % len(stale))
        cur = None
        for doc, doc_line, msg in stale:
            if doc != cur:
                print('\n[%s]' % doc)
                cur = doc
            print('  L%-5d %s' % (doc_line, msg))
        print('\n修法：用 grep -n 查符号的真实行号，回填对应文档。')
        return 1

    print('全部锚点与代码一致 ✓')
    return 0


if __name__ == '__main__':
    sys.exit(main())
