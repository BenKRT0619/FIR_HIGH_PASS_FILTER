%% fir_design_dual.m
% Thiet ke 2 bo loc FIR 32-tap High-pass (Q15) theo 2 luong:
%   (A) Direct     : ham ly tuong Type-IV x cua so Hamming
%   (B) Conversion : lay he so LP tu fir32_lowpass_ref.v, nhan (-1)^n
% Xuat 3 file hex (uppercase, 4 chu so, bu 2 16-bit, 1 tu / dong):
%   fir_coeff_direct.hex (32), fir_coeff_converted.hex (32), fir_input.hex (1000)
%   + fir_input_sat.hex (1000), fir_expected_{main,sat}_{direct,converted}.hex/.txt (1002)
%
% Yeu cau : Signal Processing Toolbox (freqz), MATLAB R2018b+ (xline)
% Chay    : dat file nay cung thu muc voi fir32_lowpass_ref.v roi nhan Run.
%           Cac file ket qua duoc ghi vao cung thu muc voi script.

clear; clc; close all;

%% 1. Tham so
N_TAPS    = 32;
N_SAMPLES = 1000;
FS_HZ     = 2000;                 % tan so lay mau (slide p.93)
F_LP_HZ   = 0.2 * FS_HZ;          % 400 Hz  (LP trong Verilog = 0.2*Fs)
F_HP_HZ   = FS_HZ/2 - F_LP_HZ;    % 600 Hz  (cat HP bu)
F_STOP_HZ = 200;                  % tone test vung chan
F_PASS_HZ = 800;                  % tone test vung thong
A_STOP    = 0.4;                  % bien do tone, tranh clip Q15
A_PASS    = 0.4;
SCALE_Q15 = 2^15;

% Duong dan: script va file Verilog
script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir), script_dir = pwd; end
verilog_path = fullfile(script_dir, 'fir32_lowpass_ref.v');
out_dir      = script_dir;

%% 2. Luong A - Direct: ly tuong Type-IV x Hamming
n = 0:N_TAPS-1;
t = n - (N_TAPS-1)/2;                       % ban nguyen (N chan)
omega_hp = 2*pi*F_HP_HZ/FS_HZ;
h_ideal  = cos(omega_hp*t) ./ (pi*t);       % (cos(wc*t)-cos(pi*t))/(pi*t), cos(pi*t)=0
w_hamming = 0.54 - 0.46*cos(2*pi*n/(N_TAPS-1));
h_direct_real = h_ideal .* w_hamming;
q_direct = quantize_q15(h_direct_real);

%% 3. Luong B - Conversion: trich he so tu Verilog, nhan (-1)^n
q_lp_ref = extract_verilog_coefficients(verilog_path, N_TAPS);   % int Q15 co dau
h_lp_real = q_lp_ref / SCALE_Q15;                                % ve so thuc
sign_alt  = (-1).^n;                                             % (-1)^n
h_conv_real = h_lp_real .* sign_alt;
q_converted = quantize_q15(h_conv_real);

%% 4. Tin hieu test: 2 tone, dung 1000 mau
ns = 0:N_SAMPLES-1;
x_float = A_STOP*sin(2*pi*F_STOP_HZ*ns/FS_HZ) + A_PASS*sin(2*pi*F_PASS_HZ*ns/FS_HZ);
if max(abs(x_float)) >= 1.0
    error('Stimulus vuot dai Q15 co dau');
end
q_input = quantize_q15(x_float);

%% 5. Kiem tra cau truc tuyen tinh pha
assert(isequal(q_lp_ref,   q_lp_ref(end:-1:1)),     'LP reference khong doi xung');
assert(isequal(q_direct,   -q_direct(end:-1:1)),    'Direct HP khong phai Type IV');
assert(isequal(q_converted, -q_converted(end:-1:1)),'Converted HP khong phai Type IV');

%% 6. Ghi file hex (%04X, bu 2 16-bit)
write_hex(fullfile(out_dir, 'fir_coeff_direct.hex'),    q_direct,    N_TAPS);
write_hex(fullfile(out_dir, 'fir_coeff_converted.hex'), q_converted, N_TAPS);
write_hex(fullfile(out_dir, 'fir_input.hex'),           q_input,     N_SAMPLES);

% Doc lai va doi chieu
assert(isequal(read_hex_verify(fullfile(out_dir,'fir_coeff_direct.hex'),    N_TAPS),    q_direct));
assert(isequal(read_hex_verify(fullfile(out_dir,'fir_coeff_converted.hex'), N_TAPS),    q_converted));
assert(isequal(read_hex_verify(fullfile(out_dir,'fir_input.hex'),           N_SAMPLES), q_input));

%% 7. Mo phong MAC tuong duong RTL (Q15xQ15 -> Q30, >>>15, bao hoa)
[y_direct, sat_direct] = simulate_rtl_mac(q_input, q_direct);
[y_conv,   sat_conv]   = simulate_rtl_mac(q_input, q_converted);

%% 7b. Vector saturation + file expected cho testbench (khop 100% voi Python)
LAT = 2;                                   % do tre RTL (clk)
q_input_sat = build_saturation_input(q_direct, q_converted, N_TAPS, N_SAMPLES);
write_hex(fullfile(out_dir, 'fir_input_sat.hex'), q_input_sat, N_SAMPLES);
assert(isequal(read_hex_verify(fullfile(out_dir,'fir_input_sat.hex'), N_SAMPLES), q_input_sat));
[y_direct_s, ~] = simulate_rtl_mac(q_input_sat, q_direct);
[y_conv_s,   ~] = simulate_rtl_mac(q_input_sat, q_converted);
write_expected(out_dir, 'main', 'direct',    y_direct,   LAT);
write_expected(out_dir, 'main', 'converted', y_conv,     LAT);
write_expected(out_dir, 'sat',  'direct',    y_direct_s, LAT);
write_expected(out_dir, 'sat',  'converted', y_conv_s,   LAT);

%% 8. Bao cao kiem chung
freqs = [F_STOP_HZ, F_HP_HZ, F_PASS_HZ, FS_HZ/2];
report = {
    '32-tap FIR high-pass | DSP window method vs spectrum conversion'
    sprintf('Fs = %g Hz', FS_HZ)
    sprintf('LP reference cutoff = %g Hz = 0.2 Fs (Verilog)', F_LP_HZ)
    sprintf('HP cutoff (both flows) = %g Hz = Fs/2 - LP cutoff', F_HP_HZ)
    sprintf('Test tones: Fstop = %g Hz; Fpass = %g Hz', F_STOP_HZ, F_PASS_HZ)
    sprintf('Samples = %d, taps = %d, window = Hamming, Q = signed Q15', N_SAMPLES, N_TAPS)
    sprintf('LP reference Q15 sum = %d (%.8f)', sum(q_lp_ref), sum(q_lp_ref)/SCALE_Q15)
    sprintf('Direct coefficient max abs = %d LSB', max(abs(q_direct)))
    sprintf('Converted coefficient max abs = %d LSB', max(abs(q_converted)))
    sprintf('Max coefficient difference = %d LSB', max(abs(q_direct - q_converted)))
    sprintf('Mean abs coefficient difference = %.4f LSB', mean(abs(q_direct - q_converted)))
    sprintf('Input Q15 range = [%d, %d]', min(q_input), max(q_input))
    sprintf('Input peak absolute value = %.8f', max(abs(q_input))/SCALE_Q15)
    sprintf('RTL-equivalent MAC: saturated outputs (direct, converted) = (%d, %d)', sat_direct, sat_conv)
    sprintf('RTL-equivalent output peak abs (direct, converted) = (%.8f, %.8f)', ...
            max(abs(y_direct))/SCALE_Q15, max(abs(y_conv))/SCALE_Q15)
};
for f = freqs
    report{end+1,1} = sprintf('|H(%g Hz)| [dB]: direct=%.4f; converted=%.4f', f, ...
        response_at_hz(q_direct, f, FS_HZ), response_at_hz(q_converted, f, FS_HZ)); %#ok<SAGROW>
end
report{end+1,1} = 'All 3 hex files verified: one uppercase 4-digit two''s-complement word per line.';

fid = fopen(fullfile(out_dir, 'validation_report.txt'), 'w');
assert(fid ~= -1, 'Khong mo duoc validation_report.txt');
fprintf(fid, '%s\n', report{:});
fclose(fid);
fprintf('%s\n', report{:});

%% 9. Ve dap ung tan so (Bode - bien do dB)
[H_d, f_d] = freqz(q_direct    / SCALE_Q15, 1, 8192, FS_HZ);
[H_c, f_c] = freqz(q_converted / SCALE_Q15, 1, 8192, FS_HZ);

fig = figure('Name', '32-tap Q15 FIR high-pass', 'Color', 'w', 'Position', [100 100 900 470]);
plot(f_d, 20*log10(max(abs(H_d), 1e-8)), 'LineWidth', 1.4); hold on;
plot(f_c, 20*log10(max(abs(H_c), 1e-8)), '--', 'LineWidth', 1.4);
xline(F_STOP_HZ, ':',  sprintf('F_{stop} = %g Hz', F_STOP_HZ), 'LabelVerticalAlignment', 'bottom');
xline(F_HP_HZ,   '--', sprintf('F_{HP} = %g Hz',   F_HP_HZ),   'LabelVerticalAlignment', 'bottom');
xline(F_PASS_HZ, ':',  sprintf('F_{pass} = %g Hz', F_PASS_HZ), 'LabelVerticalAlignment', 'bottom');
grid on; xlim([0 FS_HZ/2]); ylim([-110 5]);
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
title('32-tap Q15 FIR high-pass: two design flows');
legend('Direct Type IV', 'Converted from Verilog LP', 'Location', 'southeast');
print(fig, fullfile(out_dir, 'fir_frequency_response.png'), '-dpng', '-r180');

fprintf('\nCreated files in: %s\n', out_dir);

%% ============================ Local functions ============================

function q = quantize_q15(values)
% Nhan 2^15, lam tron, bao hoa ve [-32768, 32767], tra ve int32-valued double.
    q = round(values(:).' * 2^15);
    q = min(max(q, -32768), 32767);
end

function write_hex(path, q, expected)
% Ghi 1 tu 16-bit bu 2 / dong, dinh dang %04X (chu hoa).
    q = q(:).';
    assert(numel(q) == expected, 'write_hex: can %d gia tri, co %d', expected, numel(q));
    assert(all(q >= -32768 & q <= 32767), 'write_hex: gia tri ngoai dai int16');
    fid = fopen(path, 'w');
    assert(fid ~= -1, 'Khong mo duoc file: %s', path);
    fprintf(fid, '%04X\n', mod(q, 65536));
    fclose(fid);
end

function q = read_hex_verify(path, expected)
% Doc lai file hex, kiem tra dinh dang, doi ve so nguyen co dau.
    txt = strtrim(splitlines(fileread(path)));
    txt = txt(~cellfun(@isempty, txt));
    assert(numel(txt) == expected, '%s: can %d dong, co %d', path, expected, numel(txt));
    assert(all(cellfun(@(s) ~isempty(regexp(s, '^[0-9A-F]{4}$', 'once')), txt)), ...
           '%s: sai dinh dang 4 chu so hex hoa', path);
    u = hex2dec(txt).';
    q = u;
    q(u >= 32768) = u(u >= 32768) - 65536;
end

function q = extract_verilog_coefficients(verilog_path, n_taps)
% Trich coeff[0]..coeff[N-1] tu cac dong: assign coeff[i] = 16'hXXXX;
    assert(isfile(verilog_path), 'Khong tim thay file Verilog: %s', verilog_path);
    raw = fileread(verilog_path);
    pattern = 'assign\s+coeff\s*\[\s*(\d+)\s*\]\s*=\s*16\s*''\s*[hH]\s*([0-9a-fA-F]{1,4})\s*;';
    tok = regexp(raw, pattern, 'tokens');
    if numel(tok) ~= n_taps
        error('Expected %d coeff assignments, found %d', n_taps, numel(tok));
    end
    q = zeros(1, n_taps);
    seen = false(1, n_taps);
    for k = 1:numel(tok)
        idx = str2double(tok{k}{1});
        if idx < 0 || idx >= n_taps || seen(idx+1)
            error('Duplicate or out-of-range coeff index: %d', idx);
        end
        seen(idx+1) = true;
        u16 = hex2dec(tok{k}{2});
        if u16 >= 2^15, u16 = u16 - 2^16; end
        q(idx+1) = u16;
    end
    if ~all(seen), error('Coeff array has missing indices'); end
end

function dB = response_at_hz(q, f_hz, fs_hz)
% |H(f)| [dB] tai dung tan so f_hz, tu he so Q15.
    h = q(:).' / 2^15;
    n = 0:numel(h)-1;
    v = sum(h .* exp(-1j*2*pi*f_hz*n/fs_hz));
    dB = 20*log10(max(abs(v), 1e-15));
end

function [y, sat_count] = simulate_rtl_mac(x_q15, h_q15)
% Q15xQ15 -> Q30, cong tich luy, >>>15 (dich so hoc = floor), bao hoa nhu RTL.
    acc = conv(x_q15(:).', h_q15(:).');          % do chinh xac double du cho Q30 x 32 tap
    acc = acc(1:numel(x_q15));
    shifted = floor(acc / 2^15);
    sat_count = nnz(shifted < -32768 | shifted > 32767);
    y = min(max(shifted, -32768), 32767);
end

function x = build_saturation_input(q_d, q_c, n_taps, n_samples)
% 1000 mau full-scale tat dinh (khong dung RNG) ep y_out cham +32767 va -32768.
% Cuc dai y[n] khi x[n-k] = +32767 neu h[k]>=0 nguoc lai -32768 (theo thu tu thoi gian: dao nguoc).
    z = zeros(1, n_taps);
    parts = {z};
    for h = {q_d, q_c}
        hh  = h{1};
        pos = 32767*(hh >= 0) - 32768*(hh < 0);
        neg = -pos - 1;
        parts = [parts, {fliplr(pos), z, fliplr(neg), z}]; %#ok<AGROW>
    end
    parts = [parts, {repmat([32767 -32768], 1, 32), -32768*ones(1,40), 32767*ones(1,40)}];
    head  = [parts{:}];
    k     = 0:(n_samples - numel(head) - 1);
    s     = mod(k*37 + k.*k*11, 7);
    fill  = 32767*(s < 3) - 32768*(s >= 3);
    x = [head, fill];
    assert(numel(x) == n_samples, 'sat vector sai do dai');
end

function write_expected(out_dir, test, flow, y, lat)
% LAT so 0 (pipeline fill) + N dau ra -> 1002 dong, ghi ca .hex (cho TB) va .txt (so thap phan)
    full = [zeros(1, lat), y(:).'];
    base = fullfile(out_dir, sprintf('fir_expected_%s_%s', test, flow));
    write_hex([base '.hex'], full, numel(full));
    fid = fopen([base '.txt'], 'w');
    assert(fid ~= -1, 'Khong mo duoc %s.txt', base);
    fprintf(fid, '%d\n', full);
    fclose(fid);
end

%% ===================== 10. VISUALIZATION =====================

% Chuyen du lieu Q15 ve dang so thuc
x_plot = q_input / SCALE_Q15;

y_direct_plot = y_direct / SCALE_Q15;
y_conv_plot   = y_conv / SCALE_Q15;

h_direct_plot = q_direct / SCALE_Q15;
h_conv_plot   = q_converted / SCALE_Q15;

% Truc thoi gian (ms)
time_ms = (0:N_SAMPLES-1) / FS_HZ * 1000;

% FFT
NFFT = 2^nextpow2(N_SAMPLES);
f_axis = (0:NFFT/2) * FS_HZ / NFFT;

X = fft(x_plot, NFFT);
Y_direct = fft(y_direct_plot, NFFT);
Y_conv = fft(y_conv_plot, NFFT);

% Pho bien do mot phia
X_mag = abs(X(1:NFFT/2+1)) / N_SAMPLES;
Y_direct_mag = abs(Y_direct(1:NFFT/2+1)) / N_SAMPLES;
Y_conv_mag = abs(Y_conv(1:NFFT/2+1)) / N_SAMPLES;

if numel(X_mag) > 2
    X_mag(2:end-1) = 2 * X_mag(2:end-1);
    Y_direct_mag(2:end-1) = 2 * Y_direct_mag(2:end-1);
    Y_conv_mag(2:end-1) = 2 * Y_conv_mag(2:end-1);
end

% Tao thu muc luu hinh

plot_dir = fullfile(out_dir, 'plots');

if ~exist(plot_dir, 'dir')
    mkdir(plot_dir);
end


%% 10.1. Gop tat ca bieu do vao mot Figure

fig = figure('Name', 'FIR High Pass Analysis', ...
             'Color', 'w', ...
             'Position', [100 50 1200 850]);

sgtitle('FIR HIGH PASS FILTER ANALYSIS', ...
        'FontSize', 16, 'FontWeight', 'bold');


% ---------------------------------------------------------
% 1. Tin hieu dau vao theo thoi gian
% ---------------------------------------------------------
subplot(3,2,1);

plot(time_ms, x_plot, 'b', 'LineWidth', 1.1);
grid on;

title('Input Signal');
xlabel('Time (ms)');
ylabel('Amplitude');

xlim([0 time_ms(end)]);


% ---------------------------------------------------------
% 2. Pho tan so tin hieu dau vao
% ---------------------------------------------------------
subplot(3,2,2);

plot(f_axis, X_mag, 'b', 'LineWidth', 1.1);
hold on;

xline(F_HP_HZ, '--r', 'Cutoff');

grid on;

title('Input Frequency Spectrum');
xlabel('Frequency (Hz)');
ylabel('Magnitude');

xlim([0 FS_HZ/2]);


% ---------------------------------------------------------
% 3. He so bo loc FIR
% ---------------------------------------------------------
subplot(3,2,3);

stem(0:N_TAPS-1, h_direct_plot, 'b', 'filled');
hold on;

stem(0:N_TAPS-1, h_conv_plot, 'r--');

grid on;

title('FIR Coefficients');
xlabel('Coefficient Index');
ylabel('Amplitude');

legend('Direct', 'Converted');


% ---------------------------------------------------------
% 4. Tin hieu dau ra sau khi loc
% ---------------------------------------------------------
subplot(3,2,4);

plot(time_ms, y_direct_plot, 'b', 'LineWidth', 1.1);
hold on;

plot(time_ms, y_conv_plot, 'r--', 'LineWidth', 1.1);

grid on;

title('Output Signal');
xlabel('Time (ms)');
ylabel('Amplitude');

legend('Direct', 'Converted');

xlim([0 time_ms(end)]);


% ---------------------------------------------------------
% 5. So sanh pho tan so truoc va sau khi loc
% ---------------------------------------------------------
subplot(3,2,[5 6]);

plot(f_axis, X_mag, 'k', 'LineWidth', 1.2);
hold on;

plot(f_axis, Y_direct_mag, 'b', 'LineWidth', 1.2);

plot(f_axis, Y_conv_mag, 'r--', 'LineWidth', 1.2);

xline(F_HP_HZ, '--g', 'Cutoff');

grid on;

title('Frequency Spectrum Before and After Filtering');
xlabel('Frequency (Hz)');
ylabel('Magnitude');

legend('Input', 'Direct Output', 'Converted Output');

xlim([0 FS_HZ/2]);


%% 10.2. Luu toan bo bieu do trong mot anh

print(fig, fullfile(plot_dir, 'fir_complete_analysis.png'), ...
      '-dpng', '-r200');


%% 10.3. Hien thi thong so

w_hamming = hamming_window_custom(N_TAPS).';

h_direct_real = h_ideal .* w_hamming;
q_direct = quantize_q15(h_direct_real);

%% Ve rieng cua so Hamming 32 diem
fig_hamming = figure( ...
    'Name', 'Hamming Window - 32 taps', ...
    'Color', 'w', ...
    'Position', [150 150 520 420]);

plot(n, w_hamming, '-o', ...
    'Color', [0.95 0.42 0.08], ...
    'LineWidth', 1.3, ...
    'MarkerSize', 4, ...
    'MarkerFaceColor', [0.95 0.42 0.08]);

grid on;
box on;

xlim([0 N_TAPS-1]);
ylim([0 1.05]);

xticks(0:5:30);
yticks(0:0.2:1);

xlabel('n');
ylabel('w[n]');
title('(b) Cửa sổ Hamming w[n]');

print(fig_hamming, ...
    fullfile(out_dir, 'hamming_window.png'), ...
    '-dpng', '-r200');