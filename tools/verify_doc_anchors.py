#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
docs/reference/ 索引锚点校验器

AGENTS.md / CLAUDE.md 要求"commit 前检查索引与代码一致性"，本脚本把它变成一条命令。

校验对象：docs/reference/*.md 里形如 `some_file.gd:123 symbol_name` 的锚点。
判定规则：symbol 必须出现在 该文件:第123行 的 ±3 行窗口内。
  - 只有 `file.gd:123` 而不带符号 → 只校验行号未超出文件长度（弱校验）
  - 带符号 → 强校验（这是我们真正想守住的）

用法：
    python tools/verify_doc_anchors.py              # 全量，只报错
    python tools/verify_doc_anchors.py --verbose    # 连通过的也列出来
    python tools/verify_doc_anchors.py --doc code-index.md
    python tools/verify_doc_anchors.py --section 无线电通讯   # 只校验某段
    python tools/verify_doc_anchors.py --fix        # 按符号保守刷新可定位的行号

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
SCAN_FILES = ['AGENTS.md', 'CLAUDE.md']

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
    """Return (lookup, all_paths), avoiding ambiguous basename guesses."""
    index = {}
    by_base = {}
    all_paths = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.endswith('.gd'):
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, root).replace('\\', '/')
                all_paths.append(path)
                index[rel] = path
                index['scripts/' + rel] = path
                by_base.setdefault(fn, []).append(path)
    for base, paths in by_base.items():
        if len(paths) == 1:
            index[base] = paths[0]
    return index, all_paths


def resolve_script(script_lookup, fname):
    key = fname.replace('\\', '/')
    return script_lookup.get(key) or script_lookup.get(key.lstrip('./'))


def declaration_lines(lines, symbol):
    """Find declaration-like occurrences before falling back to ordinary uses."""
    escaped = re.escape(symbol)
    declaration = re.compile(
        r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
        r'(?:(?:static|abstract)\s+)?'
        r'(?:func|var|const|signal|class_name)\s+' + escaped + r'\b')
    enum_member = re.compile(r'^\s*' + escaped + r'\s*(?:=|,)')
    exact = [i + 1 for i, line in enumerate(lines)
             if declaration.search(line) or enum_member.search(line)]
    if exact:
        return exact
    word = re.compile(r'\b' + escaped + r'\b')
    return [i + 1 for i, line in enumerate(lines) if word.search(line)]


def nearest_line(candidates, old_line):
    if not candidates:
        return None
    return min(candidates, key=lambda n: abs(n - old_line))


def find_fix_target(current_path, old_line, symbol, all_paths, cache):
    """Prefer the referenced file; relocate only on a unique declaration elsewhere."""
    if current_path:
        if current_path not in cache:
            cache[current_path] = read_lines(current_path)
        candidate = nearest_line(declaration_lines(cache[current_path], symbol), old_line)
        if candidate is not None:
            return current_path, candidate

    escaped = re.escape(symbol)
    declaration = re.compile(
        r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
        r'(?:(?:static|abstract)\s+)?'
        r'(?:func|var|const|signal|class_name)\s+' + escaped + r'\b')
    enum_member = re.compile(r'^\s*' + escaped + r'\s*(?:=|,)')
    found = []
    for path in all_paths:
        if path not in cache:
            cache[path] = read_lines(path)
        for i, line in enumerate(cache[path]):
            if declaration.search(line) or enum_member.search(line):
                found.append((path, i + 1))
    if len(found) == 1:
        return found[0]
    return None


def display_path_for_fix(old_name, new_path):
    rel = os.path.relpath(new_path, 'scripts').replace('\\', '/')
    old = old_name.replace('\\', '/')
    if old.startswith('scripts/'):
        return 'scripts/' + rel
    if '/' in old or os.path.basename(old) != os.path.basename(rel):
        return rel
    return old


def apply_fixes(fixes):
    """Bulk mechanical rewrite of anchors proven locatable by symbol."""
    by_doc = {}
    for fix in fixes:
        by_doc.setdefault(fix['doc_path'], []).append(fix)

    for doc_path, doc_fixes in by_doc.items():
        mapping = {}
        for fix in doc_fixes:
            key = (fix['fname'], fix['old_line'], fix['symbol'])
            mapping[key] = (fix['new_fname'], fix['new_line'])

        text = io.open(doc_path, encoding='utf-8').read()
        out_lines = []
        for line in text.split('\n'):
            replacements = []
            for kind, match, owner, old_line, sym in anchors_in_line(line):
                target = mapping.get((owner, old_line, sym))
                if not target:
                    continue
                if kind == 'full':
                    replacement = match.group(0).replace(
                        owner + ':' + str(old_line),
                        target[0] + ':' + str(target[1]), 1)
                else:
                    replacement = match.group(0).replace(
                        ':' + str(old_line), ':' + str(target[1]), 1)
                    if target[0] != owner:
                        replacement = replacement.replace(
                            ':' + str(target[1]),
                            target[0] + ':' + str(target[1]), 1)
                replacements.append((match.start(), match.end(), replacement))

            for start, end, replacement in reversed(replacements):
                line = line[:start] + replacement + line[end:]
            out_lines.append(line)

        with io.open(doc_path, 'w', encoding='utf-8', newline='') as f:
            f.write('\n'.join(out_lines))


def read_lines(path):
    with io.open(path, encoding='utf-8') as f:
        return f.read().split('\n')


# script-index.md 是表格：第一列 `| \`path/file.gd\` |`，行内锚点写成裸 `:123 symbol`。
# 这类行要先认出"本行属于哪个文件"，再解析裸行号。
ROW_FILE_RE = re.compile(r'^\|\s*`([A-Za-z_0-9/]+\.gd)`')
BARE_RE = re.compile(r'`:(\d+)`(?:\s*`?([A-Za-z_][A-Za-z_0-9]*)`?)?')


def anchors_in_line(line):
    """Yield full anchors and shorthand anchors with their owning script.

    A shorthand such as ```:456` next_func``` inherits the nearest preceding
    full anchor on the same line. Script-index table rows may instead declare
    the owner in their first column.
    """
    full_matches = list(ANCHOR_RE.finditer(line))
    out = []
    for match in full_matches:
        sym = match.group(3)
        if sym in NOT_SYMBOLS:
            sym = None
        out.append(('full', match, match.group(1), int(match.group(2)), sym))

    row = ROW_FILE_RE.match(line)
    row_owner = row.group(1) if row else None
    for match in BARE_RE.finditer(line):
        if any(match.start() < full.end() and match.end() > full.start()
               for full in full_matches):
            continue
        owner = row_owner
        for full in full_matches:
            if full.end() <= match.start():
                owner = full.group(1)
            else:
                break
        if not owner:
            continue
        sym = match.group(2)
        if sym in NOT_SYMBOLS:
            sym = None
        out.append(('bare', match, owner, int(match.group(1)), sym))
    return sorted(out, key=lambda item: item[1].start())


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
        for _kind, _match, owner, anchor_line, sym in anchors_in_line(line):
            out.append((line_no, owner, anchor_line, sym))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--doc', help='只校验某个文档（文件名）')
    ap.add_argument('--section', help='只校验含该标题的段落')
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--fix', action='store_true',
                    help='只机械刷新能按符号定位的行号；多义/缺失项继续报错')
    args = ap.parse_args()

    if not os.path.isdir(REF_DIR):
        print('找不到 %s —— 请在项目根目录运行' % REF_DIR)
        return 2

    scripts, all_script_paths = build_script_index()
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
    fixes = []

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
            path = resolve_script(scripts, fname)
            if path is None:
                if args.fix and sym:
                    target = find_fix_target(None, ln, sym, all_script_paths, cache)
                    if target:
                        new_path, new_line = target
                        fixes.append({
                            'doc_path': doc_path, 'fname': fname, 'old_line': ln,
                            'symbol': sym,
                            'new_fname': display_path_for_fix(fname, new_path),
                            'new_line': new_line,
                        })
                        continue
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
                if args.fix:
                    target = find_fix_target(path, ln, sym, all_script_paths, cache)
                    if target:
                        new_path, new_line = target
                        fixes.append({
                            'doc_path': doc_path, 'fname': fname, 'old_line': ln,
                            'symbol': sym,
                            'new_fname': display_path_for_fix(fname, new_path),
                            'new_line': new_line,
                        })
                        continue
                actual = lines[ln - 1].strip()[:60]
                stale.append((doc, doc_line,
                              '%s:%d 附近无 %r  → 实际: %s' % (fname, ln, sym, actual)))
            elif args.verbose:
                print('  OK  %s:%d  %s:%d %s' % (doc, doc_line, fname, ln, sym))

    print('扫描 %d 份文档、锚点 %d 个（其中 %d 个未带符号，仅弱校验）'
          % (len(docs), total, weak))
    print('（docs/changelogs/ 刻意不扫：历史快照，行号描述的是当时的代码）')

    if fixes:
        apply_fixes(fixes)
        print('已按唯一/就近符号机械刷新 %d 个锚点；多义项保持不动。' % len(fixes))

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
