#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
So sanh dau ra RTL ModelSim voi Golden Model MATLAB.

Mac dinh:
    python compare.py --test all

Chi so sanh bai saturation:
    python compare.py --test sat

Chi so sanh bai main:
    python compare.py --test main

Dau vao:
    fir_out_<test>_<flow>.txt
    fir_expected_<test>_<flow>.txt

Dau ra:
    compare_report.txt
    rtl_vs_golden_<test>.png (neu co matplotlib)

Luu y:
- Cac file TXT cua testbench da bao gom LAT dong pipeline-fill va da duoc
  doi chieu theo cung thu tu voi Golden Model. Vi vay LAT chi dung de danh
  so truc hoanh tren bieu do, KHONG cat bo LAT dong khi tinh sai so.
- --test all chi PASS neu ca main/sat va ca direct/converted deu co du lieu
  va tat ca cap RTL/Gol den khop.
"""

from pathlib import Path
import argparse
import math
import sys

HERE = Path(__file__).resolve().parent
TESTS = ("main", "sat")
FLOWS = ("direct", "converted")


def load_integer_file(path: Path):
    """Doc file TXT, moi dong mot so nguyen co dau."""
    if not path.is_file():
        raise FileNotFoundError(f"Khong tim thay file: {path.name}")

    values = []
    with path.open("r", encoding="utf-8-sig") as f:
        for line_no, raw in enumerate(f, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Ho tro ca truong hop co nhieu so tren mot dong.
            for token in line.split():
                try:
                    values.append(int(token, 10))
                except ValueError as exc:
                    raise ValueError(
                        f"{path.name}, dong {line_no}: '{token}' khong phai so nguyen thap phan"
                    ) from exc

    if not values:
        raise ValueError(f"File rong hoac khong co du lieu so: {path.name}")
    return values


def calculate_metrics(rtl, golden):
    errors = [a - b for a, b in zip(rtl, golden)]
    abs_errors = [abs(e) for e in errors]
    n = len(errors)
    exact = sum(1 for e in errors if e == 0)
    max_error = max(abs_errors)
    mae = sum(abs_errors) / n
    rmse = math.sqrt(sum(e * e for e in errors) / n)
    mismatch_indices = [i for i, e in enumerate(errors) if e != 0]
    return {
        "errors": errors,
        "count": n,
        "exact": exact,
        "bad": n - exact,
        "match_rate": exact * 100.0 / n,
        "max_error": max_error,
        "mae": mae,
        "rmse": rmse,
        "mismatch_indices": mismatch_indices,
        "sat_hi_rtl": sum(1 for x in rtl if x == 32767),
        "sat_lo_rtl": sum(1 for x in rtl if x == -32768),
        "sat_hi_golden": sum(1 for x in golden if x == 32767),
        "sat_lo_golden": sum(1 for x in golden if x == -32768),
    }


def make_plot(test, records, lat):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return False

    fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
    for flow, rtl, golden, metrics in records:
        x_axis = [i - lat for i in range(len(rtl))]
        axes[0].plot(x_axis, golden, linewidth=1.5, alpha=0.8,
                     label=f"Golden {flow}")
        axes[0].plot(x_axis, rtl, "--", linewidth=1.0,
                     label=f"RTL {flow}")
        axes[1].plot(x_axis, metrics["errors"], linewidth=1.0,
                     label=f"RTL - Golden {flow}")

    axes[0].set_ylabel("y (Q15 integer)")
    axes[0].set_title(f"RTL vs Golden Model - test '{test}'")
    axes[0].grid(True, alpha=0.3)
    axes[0].legend(fontsize=8)

    axes[1].set_ylabel("Error (LSB)")
    axes[1].set_xlabel("Sample index n (pipeline latency compensated on axis)")
    axes[1].grid(True, alpha=0.3)
    axes[1].legend(fontsize=8)

    fig.tight_layout()
    output = HERE / f"rtl_vs_golden_{test}.png"
    fig.savefig(output, dpi=160)
    plt.close(fig)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Compare ModelSim RTL output against MATLAB Golden Model."
    )
    parser.add_argument(
        "--test", choices=("all", "main", "sat"), default="all",
        help="Chon bai kiem thu: all, main hoac sat (mac dinh: all)."
    )
    parser.add_argument(
        "--flow", choices=("all", "direct", "converted"), default="all",
        help="Chon luong he so can so sanh (mac dinh: all)."
    )
    parser.add_argument(
        "--lat", type=int, default=2,
        help="Do tre dung de danh so truc mau tren bieu do (mac dinh: 2)."
    )
    args = parser.parse_args()

    selected_tests = TESTS if args.test == "all" else (args.test,)
    selected_flows = FLOWS if args.flow == "all" else (args.flow,)

    report = []
    report.append("BAO CAO SO SANH RTL MODELSIM VS GOLDEN MODEL")
    report.append(f"Test: {', '.join(selected_tests)}")
    report.append(f"Flow: {', '.join(selected_flows)}")
    report.append(f"LAT (dung cho truc bieu do): {args.lat}")
    report.append("")

    all_pass = True
    compared_pairs = 0
    records_by_test = {}

    for test in selected_tests:
        report.append(f"===== TEST: {test.upper()} =====")
        records_by_test[test] = []

        for flow in selected_flows:
            rtl_path = HERE / f"fir_out_{test}_{flow}.txt"
            golden_path = HERE / f"fir_expected_{test}_{flow}.txt"

            missing = [p.name for p in (rtl_path, golden_path) if not p.is_file()]
            if missing:
                all_pass = False
                report.append(
                    f"[{test}/{flow}] ERROR: thieu file {', '.join(missing)}. "
                    f"Hay chay ModelSim voi TEST={test} truoc."
                )
                continue

            try:
                rtl = load_integer_file(rtl_path)
                golden = load_integer_file(golden_path)
            except (OSError, ValueError) as exc:
                all_pass = False
                report.append(f"[{test}/{flow}] ERROR: {exc}")
                continue

            if len(rtl) != len(golden):
                all_pass = False
                report.append(
                    f"[{test}/{flow}] FAIL: RTL co {len(rtl)} mau, "
                    f"Golden co {len(golden)} mau."
                )
                continue

            metrics = calculate_metrics(rtl, golden)
            ok = metrics["bad"] == 0

            # Bai sat phai cham duoc ca gioi han duong va am.
            sat_coverage_ok = True
            if test == "sat":
                sat_coverage_ok = (
                    metrics["sat_hi_rtl"] > 0 and metrics["sat_lo_rtl"] > 0
                )
                if not sat_coverage_ok:
                    ok = False

            all_pass = all_pass and ok
            compared_pairs += 1
            records_by_test[test].append((flow, rtl, golden, metrics))

            report.append(
                f"[{test}/{flow}] {'PASS' if ok else 'FAIL'}: "
                f"{metrics['count']} mau, {metrics['bad']} mau lech, "
                f"Max|error|={metrics['max_error']} LSB, "
                f"MAE={metrics['mae']:.6f} LSB, "
                f"RMSE={metrics['rmse']:.6f} LSB, "
                f"MatchRate={metrics['match_rate']:.4f}%"
            )
            report.append(
                f"    RTL saturation: +32767={metrics['sat_hi_rtl']}, "
                f"-32768={metrics['sat_lo_rtl']}; "
                f"Golden: +32767={metrics['sat_hi_golden']}, "
                f"-32768={metrics['sat_lo_golden']}"
            )

            if test == "sat" and not sat_coverage_ok:
                report.append(
                    "    SATURATION COVERAGE FAIL: bai sat can co it nhat "
                    "1 mau cham +32767 va 1 mau cham -32768 cho moi flow."
                )

            if metrics["mismatch_indices"]:
                report.append("    Cac mau lech dau tien (index, RTL, Golden, Error):")
                for idx in metrics["mismatch_indices"][:10]:
                    report.append(
                        f"      ({idx}, {rtl[idx]}, {golden[idx]}, "
                        f"{rtl[idx] - golden[idx]})"
                    )

        # Direct va Converted la hai bo he so khac nhau, khong yeu cau bang nhau.
        direct_record = next(
            (r for r in records_by_test[test] if r[0] == "direct"), None
        )
        converted_record = next(
            (r for r in records_by_test[test] if r[0] == "converted"), None
        )
        if direct_record and converted_record:
            d = direct_record[1]
            c = converted_record[1]
            if len(d) == len(c):
                diff = [a - b for a, b in zip(d, c)]
                rms = math.sqrt(sum(x * x for x in diff) / len(diff))
                max_diff = max(abs(x) for x in diff)
                report.append(
                    f"[{test}] Direct vs Converted (chi de tham khao): "
                    f"RMS lech={rms:.3f} LSB, Max lech={max_diff} LSB. "
                    "Khong yeu cau hai flow nay bang nhau."
                )
            else:
                report.append(
                    f"[{test}] Khong so sanh Direct/Converted: so mau khac nhau."
                )

        report.append("")

    if compared_pairs == 0:
        all_pass = False

    # Tao bieu do cho tung test co du lieu.
    plots_created = 0
    for test, records in records_by_test.items():
        if records and make_plot(test, records, args.lat):
            plots_created += 1

    report.append(
        "TONG KET: " + (
            "ALL PASS - tat ca cap du lieu duoc yeu cau deu khop."
            if all_pass and compared_pairs > 0
            else "FAIL/INCOMPLETE - co cap du lieu thieu, sai khac hoac chua du coverage."
        )
    )
    report.append(f"So cap RTL/Golden da so sanh: {compared_pairs}")
    report.append(f"So bieu do tao duoc: {plots_created}")

    report_text = "\n".join(report) + "\n"
    report_path = HERE / "compare_report.txt"
    report_path.write_text(report_text, encoding="utf-8")
    print(report_text)
    print(f"Da ghi bao cao: {report_path.name}")

    return 0 if all_pass and compared_pairs > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
