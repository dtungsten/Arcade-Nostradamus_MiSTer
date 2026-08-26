$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work = Join-Path $PSScriptRoot 'work'

Push-Location $repo
try {
  if (-not (Test-Path $work)) {
    & vlib $work
  }
  & vlog -work $work -sv `
    sim/highscore/CaveHighScoreRamModel.sv `
    rtl/cave/CaveTrueDualPortRam.sv `
    rtl/cave/highscore/CaveHighScoreManager.sv `
    sim/highscore/CaveHighScoreManager_tb.sv
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  & vsim -c -lib $work CaveHighScoreManager_tb -do 'run -all; quit -f'
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  & vlog -work $work -sv `
    rtl/cave/CaveNvramUploadPrefetch.sv `
    sim/highscore/CaveNvramUploadPrefetch_tb.sv
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  & vsim -c -lib $work CaveNvramUploadPrefetch_tb -do 'run -all; quit -f'
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  & vlog -work $work -sv `
    rtl/cave/CaveSyncReadMem.sv `
    rtl/cave/CaveNvramWriteBackCache.sv `
    rtl/cave/CaveAsyncMemArbiters.sv `
    rtl/cave/CaveNvramUploadPrefetch.sv `
    sim/highscore/CaveNvramUploadIntegration_tb.sv
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  & vsim -c -lib $work CaveNvramUploadIntegration_tb -do 'run -all; quit -f'
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
