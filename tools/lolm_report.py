#!/usr/bin/env python3
# 对局数据分段判读：按"面板请求刷新率"切成对局段(60Hz)/高刷段(>=120Hz)，逐段统计帧距、频率、温控、亮度
# 帧距来自 SurfaceFlinger 层上屏时刻；GPU 真实频率来自 kgsl 的 18 档驻留时间加权
# 用法：python lolm_report.py [目录]
import os
import statistics
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '04_日志与分析', '对局采样_20261124')
SYS_CSV = os.path.join(BASE, 'y700_lolm_sample.csv')
FPS_CSV = os.path.join(BASE, 'y700_lolm_fps.csv')
GPU_LOG = os.path.join(BASE, 'y700_lolm_gpustats.log')
FREQ_TXT = os.path.join(BASE, 'gpu_available_frequencies.txt')


def rows(path):
    if not os.path.exists(path):
        return []
    out = []
    with open(path, encoding='utf-8', errors='ignore') as f:
        head = [h.strip() for h in f.readline().strip().split(',')]
        for line in f:
            p = line.rstrip('\n').split(',')
            if len(p) < len(head):
                continue
            d = dict(zip(head, p))
            try:
                d['epoch'] = float(d['epoch'])
            except ValueError:
                continue
            out.append(d)
    return out


def num(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d


sysr = rows(SYS_CSV)
fpsr = rows(FPS_CSV)
if not sysr:
    print('没读到主采样数据：', SYS_CSV)
    sys.exit(1)

# 切段（连续同类型合成一段，段带序号；帧距按【段实例】时间区间归桶，
# 早期版本按类型归桶会让同名段共用一份统计，已修）
segs = []
for r in sysr:
    key = '高刷段' if num(r.get('refresh_req')) >= 120 else '对局段'
    if not segs or segs[-1]['key'] != key:
        segs.append({'key': key, 'rows': [], 't0': r['epoch'], 't1': r['epoch']})
    segs[-1]['rows'].append(r)
    segs[-1]['t1'] = r['epoch']
for s in segs:
    s['fps'] = [x for x in fpsr if s['t0'] - 2 <= x['epoch'] <= s['t1'] + 2]

print('采样窗口：主表 %d 行 / 帧距表 %d 行 / 跨 %.1f 分钟'
      % (len(sysr), len(fpsr), (sysr[-1]['epoch'] - sysr[0]['epoch']) / 60))
print()

for i, s in enumerate(segs, 1):
    rs = s['rows']
    if len(rs) < 4:
        continue
    fr = s['fps']
    pers = [num(x['refresh_hz']) / 1e6 for x in fr if num(x['refresh_hz']) > 1e5]
    per = statistics.median(pers) if pers else 1000.0 / max(1.0, num(rs[0]['refresh_req']))
    p50 = [num(x['p50_ms']) for x in fr if num(x['p50_ms']) > 0]
    wg = [num(x['worst_ms']) for x in fr if num(x['worst_ms']) > 0]
    drop = sum(1 for x in fr
               if num(x['p95_ms']) > (num(x['refresh_hz']) / 1e6 if num(x['refresh_hz']) > 1e5 else per) * 1.5)
    print('== 段%d %s ==  %.1f 分钟，主表 %d 点 / 帧距 %d 点'
          % (i, s['key'], (s['t1'] - s['t0']) / 60, len(rs), len(fr)))
    if p50:
        print('   帧距 中位 %.2f ms（面板周期 %.2f） 最差 %.0f ms  掉同步窗口 %d/%d  ⇒ 实测 %.0f fps'
              % (statistics.median(p50), per, max(wg) if wg else 0, drop, len(fr),
                 1000.0 / statistics.median(p50)))
    else:
        print('   帧距：该段无有效数据')
    big = [num(r['cpu7']) / 1e3 for r in rs] + [num(r['cpu6']) / 1e3 for r in rs]
    print('   CPU 大核均值 %.0f / 峰值 %.0f MHz   小核均值 %.0f MHz'
          % (statistics.mean(big), max(big), statistics.mean([num(r['cpu0']) / 1e3 for r in rs])))
    gb = [100.0 * num(r['gpu_busy']) / num(r['gpu_total']) for r in rs if num(r['gpu_total']) > 0]
    if gb:
        print('   GPU 占用均值 %.0f%%（峰 %.0f%%）' % (statistics.mean(gb), max(gb)))
    ts = [num(r['thermal_status']) for r in rs]
    sk = [num(r['skin2']) for r in rs if num(r['skin2']) > 0]
    bt = [num(r['batt_temp']) / 10 for r in rs if num(r['batt_temp']) > 0]
    print('   热档 max=%d  壳温 %.1f→%.1f ℃  电池 %.1f→%.1f ℃（skin 第一档 48℃）'
          % (max(ts), sk[0] if sk else 0, sk[-1] if sk else 0, bt[0] if bt else 0, bt[-1] if bt else 0))
    br = [int(num(r['brightness'])) for r in rs if num(r['brightness']) > 0]
    print('   亮度 %s→%s（段内变化 %d 次）  电量 %s%%→%s%%'
          % (br[0] if br else '-', br[-1] if br else '-',
             sum(1 for a, b in zip(br, br[1:]) if a != b),
             rs[0].get('batt_level'), rs[-1].get('batt_level')))
    print()

if os.path.exists(FREQ_TXT) and os.path.exists(GPU_LOG):
    freqs = [int(x) for x in open(FREQ_TXT, encoding='utf-8').read().split()]
    g = []
    with open(GPU_LOG, encoding='utf-8', errors='ignore') as f:
        for line in f:
            q = line.split()
            if len(q) >= 2 + len(freqs):
                g.append((num(q[0]), num(q[1]), [num(x) for x in q[2:2 + len(freqs)]]))
    if len(g) >= 2:
        acc = den = top = 0.0
        for i in range(1, len(g)):
            dt = [max(0.0, a - b) for a, b in zip(g[i][2], g[i - 1][2])]
            tot = sum(dt)
            if tot <= 0:
                continue
            acc += sum(d * f for d, f in zip(dt, freqs))
            den += tot
            top += dt[0]
        print('== GPU 真实频率（18 档驻留加权，全窗口）==')
        print('   加权均值 %.0f MHz   最高档 1200MHz 驻留占比 %.2f%%   占用 %.0f%%→%.0f%%'
              % (acc / den / 1e6, 100.0 * top / den, g[1][1], g[-1][1]))
        print()

print('判读要点：')
print('   1) 帧距中位 == 面板周期 ⇒ 满帧；大于周期 ⇒ 在丢帧，看掉同步窗口计数')
print('   2) 热档离开 0 时对照同段 CPU 大核均值是否跳水，即可判定温控是否真插手')
print('   3) 段内亮度变化 > 3 次 ⇒ 游戏空间"锁定亮度"未生效')
print('   4) GPU 加权均值远低于 1200MHz 上限而占用已 80% ⇒ 升频保守，不是算力不够')
