#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vcd_glitch_scan.py - 扫描 VCD 波形，查找复位/时钟上的毛刺。

功能（可组合使用）：
  1. 窄脉冲检测     : 1-bit 信号上宽度 < --min-width 的高/低脉冲
  2. 同刻多次变化   : 同一时间戳内同一信号变化 >1 次（delta 毛刺，需 fsdb 带 delta 信息时才会出现）
  3. 复位同步器检查 : 同一 scope 下 --rst-out(默认 rstn_sync1) 被拉低，但 --rst-in(默认 rstn_in)
                     在该时刻没有可见的下降沿且值为 1 —— 即“看不见的零宽毛刺”触发了异步复位
  4. --at T         : 打印时刻 T（可加 --window）内所有发生变化的信号，用于找毛刺的上游源头

用法示例：
  python3 vcd_glitch_scan.py dump.vcd --rst-check
  python3 vcd_glitch_scan.py dump.vcd --sig 'RSTJ|rstn' --min-width 5ns
  python3 vcd_glitch_scan.py dump.vcd --at 4565950ns --window 1ns --scope U_MAIN_BUS_APB_RSTJ
  python3 vcd_glitch_scan.py dump.vcd --bt 4565000ns --et 4567000ns --rst-check --min-width 10ns
"""
import argparse
import re
import sys
from collections import defaultdict

UNIT = {"s": 1e0, "ms": 1e-3, "us": 1e-6, "ns": 1e-9, "ps": 1e-12, "fs": 1e-15}


def parse_time(s, ts_sec):
    """'4565900ns' / '4.5us' / '123'(VCD ticks) -> VCD ticks(int)"""
    if s is None:
        return None
    m = re.fullmatch(r"\s*([\d.]+)\s*([a-z]*)\s*", s)
    if not m:
        raise ValueError("bad time: %s" % s)
    val, unit = float(m.group(1)), m.group(2)
    if not unit:
        return int(val)
    return int(round(val * UNIT[unit] / ts_sec))


def fmt_time(t, ts_sec):
    ns = t * ts_sec / 1e-9
    return "%.3fns" % ns


class Var(object):
    __slots__ = ("code", "name", "scope", "width")

    def __init__(self, code, name, scope, width):
        self.code, self.name, self.scope, self.width = code, name, scope, width

    @property
    def full(self):
        return self.scope + "." + self.name if self.scope else self.name


def read_header(f):
    """返回 (timescale_sec, {code: [Var,...]})，文件指针停在 $enddefinitions 之后"""
    ts_sec = 1e-9
    codes = defaultdict(list)
    scope = []
    buf = []
    for line in f:
        buf.extend(line.split())
        if "$end" not in buf:
            continue
        # 处理完整的 $xxx ... $end 语句
        while "$end" in buf:
            i = buf.index("$end")
            stmt, buf = buf[:i], buf[i + 1:]
            if not stmt:
                continue
            kw = stmt[0]
            if kw == "$timescale":
                m = re.fullmatch(r"(\d+)\s*([a-z]+)", "".join(stmt[1:]))
                if m:
                    ts_sec = int(m.group(1)) * UNIT[m.group(2)]
            elif kw == "$scope":
                scope.append(stmt[2] if len(stmt) > 2 else "?")
            elif kw == "$upscope":
                if scope:
                    scope.pop()
            elif kw == "$var":
                # $var wire 1 ! name [3:0] $end
                width, code, name = int(stmt[2]), stmt[3], stmt[4]
                if len(stmt) > 5:
                    name += stmt[5]
                codes[code].append(Var(code, name, ".".join(scope), width))
            elif kw == "$enddefinitions":
                return ts_sec, codes
    raise RuntimeError("no $enddefinitions found")


def iter_changes(f):
    """产生 ('T', time) 或 ('V', code, value)"""
    for line in f:
        toks = line.split()
        i = 0
        n = len(toks)
        while i < n:
            t = toks[i]
            c = t[0]
            if c == "#":
                yield ("T", int(t[1:]))
            elif c in "01xXzZ":
                yield ("V", t[1:], c.lower())
            elif c in "bBrR":
                i += 1
                yield ("V", toks[i], t[1:].lower())
            # $dumpvars/$dumpall/$end/$comment 等关键字直接跳过
            i += 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("vcd")
    ap.add_argument("--sig", default=None,
                    help="只检查全路径匹配该正则的信号（窄脉冲/同刻多变检测）")
    ap.add_argument("--scope", default=None, help="只看路径匹配该正则的信号")
    ap.add_argument("--bt", default=None, help="起始时间，如 4565000ns")
    ap.add_argument("--et", default=None, help="结束时间，如 4567000ns")
    ap.add_argument("--min-width", default=None,
                    help="窄脉冲阈值，如 5ns；不给则不做窄脉冲检测")
    ap.add_argument("--rst-check", action="store_true", help="复位同步器隐藏毛刺检查")
    ap.add_argument("--rst-in", default="rstn_in")
    ap.add_argument("--rst-out", default="rstn_sync1")
    ap.add_argument("--at", default=None, help="打印该时刻附近所有变化的信号")
    ap.add_argument("--window", default="0", help="--at 的前后窗口，如 2ns")
    ap.add_argument("--max", type=int, default=200, help="每类最多打印条数")
    args = ap.parse_args()

    f = open(args.vcd, "r", errors="replace")
    ts_sec, codes = read_header(f)

    bt = parse_time(args.bt, ts_sec)
    et = parse_time(args.et, ts_sec)
    min_w = parse_time(args.min_width, ts_sec) if args.min_width else None
    sig_re = re.compile(args.sig) if args.sig else None
    scope_re = re.compile(args.scope) if args.scope else None
    at_t = parse_time(args.at, ts_sec) if args.at else None
    at_w = parse_time(args.window, ts_sec)

    def selected(code):
        for v in codes[code]:
            if scope_re and not scope_re.search(v.full):
                continue
            if sig_re and not sig_re.search(v.full):
                continue
            return True
        return False

    # 需要做窄脉冲/同刻检测的 1-bit 信号
    watch = set(c for c in codes if codes[c][0].width == 1 and selected(c)) \
        if (min_w is not None or sig_re) else set()

    # 复位同步器: scope -> (in_code, out_code)
    rst_pairs = {}
    if args.rst_check:
        by_scope = defaultdict(dict)
        for c, vs in codes.items():
            for v in vs:
                if v.name in (args.rst_in, args.rst_out):
                    by_scope[v.scope][v.name] = c
        for sc, d in by_scope.items():
            if args.rst_in in d and args.rst_out in d:
                if scope_re and not scope_re.search(sc):
                    continue
                rst_pairs[sc] = (d[args.rst_in], d[args.rst_out])
        print("[info] 找到 %d 个复位同步器实例 (%s/%s)" %
              (len(rst_pairs), args.rst_in, args.rst_out))
    rst_codes = set()
    for a, b in rst_pairs.values():
        rst_codes.add(a)
        rst_codes.add(b)

    cur = {}                    # code -> 当前值
    last_t = {}                 # code -> 上次变化时间
    prev_v = {}                 # code -> 上次变化之前的值
    pre_prev = {}               # code -> 上一次变化前的值（窄脉冲用）
    blk = defaultdict(list)     # 当前时间戳内: code -> [新值序列]
    now = 0
    res_pulse, res_delta, res_rst, res_at = [], [], [], []

    def in_range(t):
        return (bt is None or t >= bt) and (et is None or t <= et)

    def name(code):
        return codes[code][0].full

    def flush(t):
        if not blk:
            return
        ok = in_range(t)
        # 同刻多次变化
        for c, seq in blk.items():
            if ok and c in watch and len(seq) > 1:
                res_delta.append((t, name(c), "->".join(seq)))
        # 复位同步器检查
        if ok:
            for sc, (ci, co) in rst_pairs.items():
                if co in blk and blk[co][-1] == "0" and prev_v.get(co) == "1":
                    in_seq = blk.get(ci, [])
                    if cur.get(ci) == "1" and "0" not in in_seq:
                        res_rst.append((t, sc, "%s=1 且本时刻无下降沿 -> 隐藏毛刺" % args.rst_in))
                    elif in_seq and in_seq[-1] == "1":
                        res_rst.append((t, sc, "%s 同刻 %s (delta 毛刺可见)" %
                                        (args.rst_in, "->".join(in_seq))))
        # --at
        if at_t is not None and abs(t - at_t) <= at_w:
            for c, seq in blk.items():
                for v in codes[c]:
                    if scope_re and not scope_re.search(v.full):
                        continue
                    res_at.append((t, v.full, prev_v.get(c, "?"), "->".join(seq)))
        blk.clear()

    for ev in iter_changes(f):
        if ev[0] == "T":
            flush(now)
            now = ev[1]
            if et is not None and now > et:
                break
            continue
        _, c, val = ev
        if c not in codes:
            continue
        old = cur.get(c)
        if old == val:
            continue
        need = (c in watch) or (c in rst_codes) or (at_t is not None)
        if need:
            if c not in blk:
                prev_v[c] = old            # 记录本时刻开始前的值
            blk[c].append(val)
        # 窄脉冲: v0 -> v1 (t0) -> v0 (now), 宽度 now-t0 < min_w
        if min_w is not None and c in watch and old is not None:
            t0 = last_t.get(c)
            pv = pre_prev.get(c)
            if t0 is not None and pv == val and now != t0 and \
                    now - t0 < min_w and in_range(now):
                res_pulse.append((t0, name(c), old, now - t0))
            pre_prev[c] = old
        cur[c] = val
        last_t[c] = now
    flush(now)

    def show(title, rows, fmt):
        print("\n==== %s : %d ====" % (title, len(rows)))
        for r in rows[:args.max]:
            print(fmt(r))
        if len(rows) > args.max:
            print("... (还有 %d 条，用 --max 调大)" % (len(rows) - args.max))

    if args.rst_check:
        show("复位同步器被异步复位但 rstn_in 看不到毛刺", res_rst,
             lambda r: "%16s  %s  : %s" % (fmt_time(r[0], ts_sec), r[1], r[2]))
    if min_w is not None:
        show("窄脉冲 (< %s)" % args.min_width, res_pulse,
             lambda r: "%16s  %-60s  pulse=%s width=%s" %
             (fmt_time(r[0], ts_sec), r[1], r[2], fmt_time(r[3], ts_sec)))
    if watch:
        show("同一时间戳内多次变化 (delta 毛刺)", res_delta,
             lambda r: "%16s  %-60s  %s" % (fmt_time(r[0], ts_sec), r[1], r[2]))
    if at_t is not None:
        res_at.sort()
        show("%s ±%s 内变化的信号" % (args.at, args.window), res_at,
             lambda r: "%16s  %-70s  %s -> %s" %
             (fmt_time(r[0], ts_sec), r[1], r[2], r[3]))



if __name__ == "__main__":
    main()
