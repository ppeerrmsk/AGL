#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
"谁是玩家机" 引用持有者校验器（SEAM-019 的自动化抗体）

背景：survivor_mode 里一批子系统在初始化时接收 player_aircraft 并**缓存**成自己的字段。
玩家切控（1-4 切槽）/ 换帅（长机阵亡自动接管）/ 进化换机之后，
`_set_player_aircraft()` 必须把这些缓存**逐个重定向**到新机，否则旧机被击落 queue_free 后
持有者就攥着一个已释放实例。GDScript 读已 free 对象常常"看起来能跑"，
所以问题会潜伏到某处把它当强类型参数传出去才炸。

  实证（2026-07-20 玩家闪退）：
  Invalid type in function 'spawn' in base 'RefCounted (CarrierStrikeGroup)'.
  The Object-derived class of argument 4 (previously freed) is not a subclass ...
  —— arg 4 来自 survivor_spawner 缓存的 player_aircraft，切控后从未被重定向。

本脚本把"加新持有者时记得去 chokepoint 登记"从人的自觉变成一条命令。

判定规则：
  在 SOURCE 里找所有把 `player_aircraft` 作为**裸引用**交出去的语句
  （`x.setup(..., player_aircraft, ...)` / `x.field = player_aircraft`），
  取出接收方标识符 x，然后要求 x 出现在 `_set_player_aircraft()` 函数体里。
  漏登记 → 退出码 1。

  `player_aircraft.position` 这类**读属性**不算交出引用，自动跳过。
  无状态工具函数（SurvivorData / EvolutionSystem ...）不持有引用，
  列在 NON_HOLDERS 里豁免 —— 每一条都是一次显式裁定，不是默默忽略。

用法：
    python tools/verify_player_ref_holders.py            # 只报问题
    python tools/verify_player_ref_holders.py --verbose  # 连通过的持有者也列出来
    python tools/verify_player_ref_holders.py --list     # 只打印识别到的持有者清单

退出码：0 = 所有持有者都已登记；1 = 存在漏登记。
"""

import argparse
import io
import os
import re
import sys

# Windows 控制台默认 cp936，中文输出会变乱码（verify_doc_anchors.py 也踩过）
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

SOURCE = os.path.join('scripts', 'survivor', 'survivor_mode.gd')
PLAYER_VAR = 'player_aircraft'
CHOKEPOINT = '_set_player_aircraft'

# 无状态调用：把 player_aircraft 当**参数**用完就丢，不存字段 → 不需要重定向。
# 加新豁免前请先确认对方真的没有 `xxx = <那个参数>` 之类的落库操作。
NON_HOLDERS = {
    'SurvivorData':          '静态计算函数（recompute_category_bonuses），不存引用',
    'SurvivorPlayableSetup': '静态装配函数（apply / deep_dup_weapons），不存引用',
    'EvolutionSystem':       '静态进化函数（evolve），不存引用',
    'SquadFactory':          '静态注册函数（register_leader），引用落到 Squad 由 set_leader 维护',
    'MapBoundary':           '静态查询（get_player_start），不接收 player_aircraft',
    'AOEBroadcast':          '静态范围结算（apply_status_in_radius），source 参数不落库',
    'radar_targets':         '字典 .get() 查表，player_aircraft 是 key 不是被持有的引用',
    'AircraftPhysics':       '静态物理 accessor（effective_max_speed_kmh 等）传参算 float 即返回，不存引用',
    'afterburner_charge':    'try_activate(leader) 传参即用不存字段；窗口成员为 6s 激活快照'
                             '（带 is_instance_valid 守卫、到期清空），刻意不追换帅'
                             '（spec afterburner-mode §3.2）',
    'AircraftWeapons':       '静态武器函数（_spawn_loyal_wingman_drone 等）传参即用不存字段；'
                             'drone 的编队引用落到 Squad/formation_leader（既有编队体系自带'
                             '失效处理）；签名 drone 跟随生成时的 ACE 与既有忠诚僚机语义一致'
                             '（spec aircraft-signature-skills §4 生成层）',
    '_friendly_asset_aggro': 'tick 只在当次 1 Hz 调度中读取当前玩家机位置，不缓存引用',
}

# 接收方标识符：允许 `_foo` / `foo` / `Foo`，但不吃掉链式调用的中间段
RECEIVER = r'([A-Za-z_][A-Za-z0-9_]*)'
# x.field = player_aircraft  （行尾，不能跟 `.` 或其它运算）
ASSIGN_RE = re.compile(
    RECEIVER + r'\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*' + PLAYER_VAR + r'\s*(?:#.*)?$')
# 裸 player_aircraft（后面不跟 `.`，那是读属性不是交出引用）
BARE_RE = re.compile(r'\b' + PLAYER_VAR + r'\b(?!\s*\.)')
# 调用点：`X.method(` —— 用于从"最近的未闭合左括号"往前回溯接收方
CALLSITE_RE = re.compile(RECEIVER + r'\.([A-Za-z_][A-Za-z0-9_]*)\s*$')


def read_lines(path):
    with io.open(path, 'r', encoding='utf-8') as f:
        return f.read().split('\n')


def join_logical_lines(lines):
    """把跨行的函数调用拼成一条逻辑行，返回 [(起始行号, 拼接后文本)]。

    survivor_mode 里 `_zone_mission.setup(self, _zone_data, player_aircraft,\\n ...)`
    这种多行调用如果不拼，正则会漏掉后续行上的 player_aircraft。
    """
    out = []
    i = 0
    while i < len(lines):
        start = i
        buf = lines[i]
        # 括号不平衡就继续吃下一行（够用即可，不做完整 GDScript 解析）
        while buf.count('(') > buf.count(')') and i + 1 < len(lines):
            i += 1
            buf += ' ' + lines[i].strip()
        out.append((start + 1, buf))
        i += 1
    return out


def find_chokepoint_body(lines):
    """抓 `func _set_player_aircraft(...)` 的函数体（到下一个顶层 func 为止）。"""
    start = None
    for idx, ln in enumerate(lines):
        if re.match(r'^func\s+' + CHOKEPOINT + r'\s*\(', ln):
            start = idx
            break
    if start is None:
        return None, None
    end = len(lines)
    for idx in range(start + 1, len(lines)):
        if re.match(r'^func\s+', lines[idx]):
            end = idx
            break
    # ⚠ 必须剥掉注释再匹配。这里的注释常常会提到被重定向对象的名字
    # （例如解释"AudioManager._engine_host 也是缓存"），不剥的话删掉真正那行代码后
    # 注释仍会让脚本判定"已登记" —— 故意破坏测试正是这么抓到这个洞的。
    body = []
    for ln in lines[start:end]:
        stripped = ln.strip()
        if stripped.startswith('#'):
            continue
        body.append(ln.split('#')[0])
    return '\n'.join(body), (start + 1, end)


def enclosing_call_receiver(text, pos):
    """从 text[pos] 处（player_aircraft 的位置）往左找**最近的未闭合左括号**，
    再取该括号前的 `X.method` 中的 X。

    必须这样回溯而不是用正则一把梭：`_tactical_map.setup(_map_boundary.get_world_rect(),
    player_aircraft, ...)` 的参数里自带一对括号，`\\([^()]*` 那种写法会直接漏掉它 ——
    漏检比误报危险得多，因为它让脚本静默地给出"全绿"。
    """
    depth = 0
    for i in range(pos - 1, -1, -1):
        ch = text[i]
        if ch == ')':
            depth += 1
        elif ch == '(':
            if depth == 0:
                m = CALLSITE_RE.search(text[:i])
                return m.group(1) if m else None
            depth -= 1
    return None


def collect_holders(lines, choke_span):
    """返回 {接收方: [(行号, 语句片段), ...]}，跳过 chokepoint 自身函数体。"""
    holders = {}
    choke_lo, choke_hi = choke_span
    for lineno, text in join_logical_lines(lines):
        if choke_lo <= lineno <= choke_hi:
            continue          # chokepoint 内部当然全是重定向，不是"持有者声明"
        stripped = text.strip()
        if stripped.startswith('#'):
            continue          # 注释里的示例（map_boundary.gd 顶部就有一条）
        if PLAYER_VAR not in stripped:
            continue
        recv = None
        m = ASSIGN_RE.search(stripped)
        if m:
            recv = m.group(1)
        else:
            bare = BARE_RE.search(stripped)
            if bare:
                recv = enclosing_call_receiver(stripped, bare.start())
        if recv is None or recv == PLAYER_VAR:
            continue
        holders.setdefault(recv, []).append((lineno, stripped[:100]))
    return holders


def member_fields(lines):
    """顶层成员字段名集合（`^var xxx`）。用于把局部变量/循环变量区分出来 ——
    它们生命周期在函数内，chokepoint 无从登记，报出来只会变噪音。"""
    out = set()
    for ln in lines:
        m = re.match(r'^var\s+([A-Za-z_][A-Za-z0-9_]*)', ln)
        if m:
            out.add(m.group(1))
        m = re.match(r'^@onready\s+var\s+([A-Za-z_][A-Za-z0-9_]*)', ln)
        if m:
            out.add(m.group(1))
    return out


def main():
    ap = argparse.ArgumentParser(description='校验 player_aircraft 缓存持有者是否都在 chokepoint 登记')
    ap.add_argument('--verbose', action='store_true', help='连通过的持有者也列出来')
    ap.add_argument('--list', action='store_true', help='只打印识别到的持有者清单，不判定')
    args = ap.parse_args()

    if not os.path.isfile(SOURCE):
        print('找不到 %s —— 请在项目根目录运行' % SOURCE)
        return 1

    lines = read_lines(SOURCE)
    choke_body, choke_span = find_chokepoint_body(lines)
    if choke_body is None:
        print('✗ 在 %s 里找不到 func %s() —— chokepoint 被改名或删了？' % (SOURCE, CHOKEPOINT))
        print('  这本身就是重大变更：SEAM-019 的整套防线都建立在它之上，请先确认改动意图。')
        return 1

    holders = collect_holders(lines, choke_span)

    if args.list:
        print('识别到 %d 个接收 %s 的接收方：' % (len(holders), PLAYER_VAR))
        for recv in sorted(holders):
            tag = '（豁免）' if recv in NON_HOLDERS else ''
            print('  %-24s %s' % (recv, tag))
            for lineno, snippet in holders[recv]:
                print('      L%-5d %s' % (lineno, snippet))
        return 0

    fields = member_fields(lines)
    missing = []
    exempt = []
    locals_ = []
    ok = []
    for recv in sorted(holders):
        if recv in NON_HOLDERS:
            exempt.append(recv)
        # 必须是 `recv.xxx`（写字段/调方法）或 `recv = ...`（整体重指）才算登记。
        # 不能用裸标识符匹配：chokepoint 的形参恰好叫 `ac`，会把 `ac.set_formation_target(...)`
        # 这类局部变量误判成"已登记"。
        elif re.search(r'\b' + re.escape(recv) + r'\s*(?:\.|=[^=])', choke_body):
            ok.append(recv)
        elif recv not in fields and not recv[0].isupper():
            locals_.append(recv)   # 局部/循环变量，chokepoint 无从登记
        else:
            missing.append(recv)

    print('扫描 %s：识别接收方 %d 个（已登记 %d / 豁免 %d / 局部变量 %d / 漏登记 %d）'
          % (SOURCE, len(holders), len(ok), len(exempt), len(locals_), len(missing)))

    if args.verbose:
        for recv in ok:
            print('  OK   %s' % recv)
        for recv in exempt:
            print('  豁免 %-22s %s' % (recv, NON_HOLDERS[recv]))
        for recv in locals_:
            print('  局部 %-22s 生命周期在函数内，chokepoint 无从登记' % recv)

    if missing:
        print('\n漏登记 %d 个 —— 切控/换帅后它们会攥住已释放的旧玩家机：' % len(missing))
        for recv in missing:
            print('\n[%s]' % recv)
            for lineno, snippet in holders[recv]:
                print('  %s:%d  %s' % (SOURCE, lineno, snippet))
        print('\n修法（二选一）：')
        print('  a) 在 func %s() 里加一行重定向，例如 `if %s: %s.<字段> = ac`'
              % (CHOKEPOINT, missing[0], missing[0]))
        print('  b) 确认它其实不存引用（纯参数传递）→ 加进本脚本的 NON_HOLDERS 并写明理由')
        print('背景见 docs/architecture/known-seams.md · SEAM-019')
        return 1

    print('所有缓存持有者都已在 %s 登记 ✓' % CHOKEPOINT)
    return 0


if __name__ == '__main__':
    sys.exit(main())
