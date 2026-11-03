#!/usr/bin/env python3
# compare_txt.py
# So sanh 1 file Golden Model MATLAB voi 1 file output RTL ModelSim.
# Mac dinh: main_direct. Sua 2 ten file ben duoi neu can so sanh cap khac.

from pathlib import Path
import math
import csv

# ====== CAU HINH FILE ======
GOLDEN_FILE = "fir_expected_main_direct.txt"  # MATLAB
RTL_FILE = "fir_out_main_direct.txt"          # ModelSim

REPORT_FILE = "comparison_report.txt"
CSV_FILE = "comparison_details.csv"
PLOT_FILE = "comparison_plot.png"


def read_integer_file(filename):
    path = Path(filename)
    if not path.is_file():
        raise FileNotFoundError(f"Khong tim thay file: {path.resolve()}")

    values = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        # Cho phep dong comment bat dau bang # hoac //
        if line.startswith("#") or line.startswith("//"):
            continue
        try:
            values.append(int(line, 0))
        except ValueError:
            # int(..., 0) khong doc duoc so co dau +/-, thap phan co so 0 dau
            try:
                values.append(int(line, 10))
            except ValueError:
                raise ValueError(
                    f"Du lieu khong hop le tai {filename}, dong {line_number}: {line!r}"
                )
    return values


def main():
    golden = read_integer_file(GOLDEN_FILE)
    rtl = read_integer_file(RTL_FILE)

    if not golden or not rtl:
        raise ValueError("Mot trong hai file khong co mau du lieu.")

    print("===== KIEM TRA SO LUONG MAU =====")
    print(f"MATLAB : {len(golden)} mau")
    print(f"ModelSim: {len(rtl)} mau")

    if len(golden) != len(rtl):
        raise ValueError(
            "So luong mau khong bang nhau. Hay kiem tra LAT, reset, "
            "so mau flush pipeline va cach ghi file truoc khi so sanh."
        )

    errors = [r - g for g, r in zip(golden, rtl)]
    abs_errors = [abs(e) for e in errors]
    n = len(errors)

    exact = sum(e == 0 for e in errors)
    max_error = max(abs_errors)
    mae = sum(abs_errors) / n
    rmse = math.sqrt(sum(e * e for e in errors) / n)
    mismatch_indices = [i for i, e in enumerate(errors) if e != 0]

    # Ghi bang chi tiet tung mau
    with open(CSV_FILE, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow([
            "Sample_Index_0_based", "MATLAB_Golden", "ModelSim_RTL",
            "Error_RTL_minus_MATLAB", "Absolute_Error"
        ])
        for i, (g, r, e) in enumerate(zip(golden, rtl, errors)):
            writer.writerow([i, g, r, e, abs(e)])

    # Tao bao cao text
    lines = [
        "BAO CAO SO SANH MATLAB GOLDEN MODEL VS MODELSIM RTL",
        "=" * 58,
        f"File MATLAB : {GOLDEN_FILE}",
        f"File ModelSim: {RTL_FILE}",
        f"So mau      : {n}",
        f"So mau trung khop: {exact}",
        f"So mau khac nhau : {n - exact}",
        f"Tien le trung khop: {100.0 * exact / n:.6f}%",
        f"Max Error   : {max_error}",
        f"MAE         : {mae:.8f}",
        f"RMSE        : {rmse:.8f}",
        "",
        "KET LUAN:",
        "TRUNG KHOP HOAN TOAN" if max_error == 0 else
        "CO SAI LECH - can kiem tra cac mau khac nhau.",
        "",
        "MOT SO MAU KHAC NHAU (toi da 20 mau):"
    ]

    if mismatch_indices:
        for i in mismatch_indices[:20]:
            lines.append(
                f"Index {i}: MATLAB={golden[i]}, ModelSim={rtl[i]}, "
                f"Error={errors[i]}"
            )
    else:
        lines.append("Khong co mau nao khac nhau.")

    Path(REPORT_FILE).write_text("\n".join(lines), encoding="utf-8")

    print("\n===== KET QUA SO SANH =====")
    print(f"So mau trung khop : {exact}/{n}")
    print(f"So mau khac nhau  : {n - exact}")
    print(f'Ty le trung khop  : {100.0 * exact / n:.6f}%')
    print(f"Max Error         : {max_error}")
    print(f"MAE               : {mae:.8f}")
    print(f"RMSE              : {rmse:.8f}")
    print("\nDa tao:")
    print(f"- {REPORT_FILE}")
    print(f"- {CSV_FILE}")

    # Ve do thi neu da cai matplotlib; phan so sanh van chay duoc neu chua cai.
    try:
        import matplotlib.pyplot as plt

        indices = range(n)

        plt.figure(figsize=(12, 5))
        plt.plot(indices, golden, label="MATLAB Golden", linewidth=1)
        plt.plot(indices, rtl, "--", label="ModelSim RTL", linewidth=1)
        plt.xlabel("Sample index")
        plt.ylabel("Output (integer Q15)")
        plt.title("MATLAB Golden Model vs ModelSim RTL")
        plt.grid(True)
        plt.legend()
        plt.tight_layout()
        plt.savefig(PLOT_FILE, dpi=150)
        plt.close()

        plt.figure(figsize=(12, 4))
        plt.plot(indices, errors, label="RTL - MATLAB", linewidth=1)
        plt.axhline(0, linewidth=0.8)
        plt.xlabel("Sample index")
        plt.ylabel("Error")
        plt.title("Sample-by-sample error")
        plt.grid(True)
        plt.legend()
        plt.tight_layout()
        error_plot = "comparison_error.png"
        plt.savefig(error_plot, dpi=150)
        plt.close()

        print(f"- {PLOT_FILE}")
        print(f"- {error_plot}")
    except ImportError:
        print("\nChua cai matplotlib nen bo qua viec ve do thi.")
        print("Neu muon ve do thi, chay: py -m pip install matplotlib")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"\nERROR: {exc}")
        raise SystemExit(1)
