derive_pll_clocks
derive_clock_uncertainty

# Define clock group for pll_video
set_clock_groups -exclusive \
  -group [get_clocks {emu|pll_video|pll_video_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]

# Static game selector crossing into the CPU clock domain. The 4-bit payload is
# captured after the synchronized load toggle; only the CDC launch/capture arcs
# are cut here.
set_false_path \
  -from [get_registers {*|Cave:cave|gameIndexReg*}] \
  -to [get_registers {*|Cave:cave|gameIndexCpuReg*}]

set_false_path \
  -from [get_registers {*|Cave:cave|gameIndexCpuLoadToggle*}] \
  -to [get_registers {*|Cave:cave|gameIndexCpuToggleSync0*}]

# MemSys readiness is monotonic after ROM copy and is synchronized before it
# releases the 32 MHz CPU/sound reset. Cut only the intentional metastability
# capture stage; the second synchronizer stage and reset consumers remain timed.
set_false_path \
  -from [get_registers -nowarn {*|Cave:cave|MemSys:memSys|readyEnableReg}] \
  -to [get_registers -nowarn {*|Cave:cave|CaveCpuResetBridge:cpuResetBridge|memReadySync0}]

# The latched game index is a static board/profile selector after ROM load or
# menu fallback. It feeds several 96 MHz decode/memory paths, but it is not a
# cycle-by-cycle datapath.
set_false_path \
  -from [get_registers -nowarn {*|Cave:cave|gameIndexReg[*]}]

# Program ROM traffic crosses only between related zero-phase PLL outputs.
# CaveProgramRomReadFreezer registers both directions on intervening clk_sys
# falling edges, so TimeQuest must check those half-cycle paths normally.
