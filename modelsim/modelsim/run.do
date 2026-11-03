# =============================================================================
# run.do - ModelSim script cho tb_fir32_dual_compare
# Cach dung (thu muc hien tai phai chua cac file .v va .hex):
#     set TEST main ; do run.do     ;# bai test 2 tone (fir_input.hex)
#     set TEST sat  ; do run.do     ;# bai test saturation (fir_input_sat.hex)
# Khong set TEST thi mac dinh la "main".
# Testbench tu in PASS/FAIL trong Transcript.
# =============================================================================

if {![info exists TEST]} { set TEST main }
if {$TEST eq "main"} { set IN fir_input.hex } else { set IN fir_input_${TEST}.hex }

quit -sim
if {[file exists work]} { vdel -lib work -all }

# 1. Tao thu vien work va bien dich
vlib work
vlog fir32_highpass_direct.v fir32_highpass_converted.v tb_fir32_dual_compare.v

# 2. Khoi chay mo phong, truyen ten file qua plusargs
vsim -voptargs=+acc work.tb_fir32_dual_compare \
     +IN=$IN \
     +EXP_D=fir_expected_${TEST}_direct.hex \
     +EXP_C=fir_expected_${TEST}_converted.hex \
     +OUT_D=fir_out_${TEST}_direct.txt \
     +OUT_C=fir_out_${TEST}_converted.txt

# 3. Waveform
add wave -divider "Clock / Reset"
add wave -noupdate /tb_fir32_dual_compare/clk
add wave -noupdate /tb_fir32_dual_compare/rst_n

add wave -divider "Input / Output"
add wave -noupdate -format Analog-Step -height 100 -min -32768 -max 32767 -radix decimal /tb_fir32_dual_compare/x_in
add wave -noupdate -format Analog-Step -height 100 -min -32768 -max 32767 -radix decimal /tb_fir32_dual_compare/y_out_direct
add wave -noupdate -format Analog-Step -height 100 -min -32768 -max 32767 -radix decimal /tb_fir32_dual_compare/y_out_converted

# 4. Chay den khi testbench $stop, roi zoom vua toan bo waveform
run -all
wave zoom full
