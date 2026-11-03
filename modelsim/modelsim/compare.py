#!/usr/bin/env python3
"""So sanh dau ra RTL (ModelSim) voi golden model, xuat bang so lieu + hinh cho bao cao.

Chay SAU khi da chay mo phong (set TEST main / set TEST sat trong ModelSim) :
    python compare.py
Dau vao : fir_out_<test>_<flow>.txt  (RTL)   va   fir_expected_<test>_<flow>.txt (golden)
Dau ra  : compare_report.txt, rtl_vs_golden_<test>.png
"""
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
TESTS = ('main', 'sat')
FLOWS = ('direct', 'converted')
LAT = 2

lines, all_ok, ran = [], True, []
for test in TESTS:
    for flow in FLOWS:
        f_rtl = HERE / f'fir_out_{test}_{flow}.txt'
        f_exp = HERE / f'fir_expected_{test}_{flow}.txt'
        if not f_rtl.exists():
            lines.append(f'[{test}/{flow}] SKIP (chua co {f_rtl.name}, hay chay mo phong test "{test}")')
            continue
        rtl = np.loadtxt(f_rtl, dtype=np.int64)
        exp = np.loadtxt(f_exp, dtype=np.int64)
        if rtl.shape != exp.shape:
            lines.append(f'[{test}/{flow}] FAIL: RTL {rtl.size} dong, golden {exp.size} dong')
            all_ok = False
            continue
        err = rtl - exp
        bad = int(np.count_nonzero(err))
        n_hi, n_lo = int(np.count_nonzero(rtl == 32767)), int(np.count_nonzero(rtl == -32768))
        ok = bad == 0
        all_ok &= ok
        lines.append(f'[{test}/{flow}] {"PASS" if ok else "FAIL"}: {rtl.size} dong so sanh, '
                     f'{bad} dong lech, max|loi| = {int(np.abs(err).max())} LSB, '
                     f'cham +32767: {n_hi} lan, cham -32768: {n_lo} lan')
        ran.append((test, flow, rtl, exp))

# So sanh Direct vs Converted (hai luong khac nhau co chu dich, khong ky vong bang 0)
for test in TESTS:
    fd, fc = HERE / f'fir_out_{test}_direct.txt', HERE / f'fir_out_{test}_converted.txt'
    if fd.exists() and fc.exists():
        d, c = np.loadtxt(fd, dtype=np.int64), np.loadtxt(fc, dtype=np.int64)
        lines.append(f'[{test}] Direct vs Converted: RMS lech = {np.sqrt(np.mean((d-c)**2)):.2f} LSB, '
                     f'max lech = {int(np.abs(d-c).max())} LSB (do DC gain cua bo LP goc = 0.98)')

lines.append('TONG KET: ' + ('ALL PASS' if (all_ok and ran) else 'CO LOI hoac chua chay du'))
(HERE / 'compare_report.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('\n'.join(lines))

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    for test in TESTS:
        sel = [r for r in ran if r[0] == test]
        if not sel:
            continue
        fig, axes = plt.subplots(2, 1, figsize=(9, 6), sharex=True)
        for _, flow, rtl, exp in sel:
            n = np.arange(len(rtl)) - LAT                       # n = chi so mau (bu do tre)
            axes[0].plot(n, exp, lw=1.6, alpha=0.6, label=f'golden {flow}')
            axes[0].plot(n, rtl, '--', lw=0.9, label=f'RTL {flow}')
            axes[1].plot(n, rtl - exp, label=f'RTL - golden ({flow})')
        axes[0].set_ylabel('y (Q15 integer)'); axes[0].legend(fontsize=8); axes[0].grid(alpha=.3)
        axes[0].set_title(f'RTL vs golden model - test "{test}"')
        axes[1].set_ylabel('sai so (LSB)'); axes[1].set_xlabel('chi so mau n')
        axes[1].legend(fontsize=8); axes[1].grid(alpha=.3)
        fig.tight_layout()
        fig.savefig(HERE / f'rtl_vs_golden_{test}.png', dpi=160)
        plt.close(fig)
except ImportError:
    print('(bo qua ve hinh: chua cai matplotlib)')
