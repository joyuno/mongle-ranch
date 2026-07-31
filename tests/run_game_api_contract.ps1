$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe'
$project = Split-Path -Parent $PSScriptRoot
$stdout = Join-Path $env:TEMP 'study_game_v2-game-api-contract.stdout.txt'
$stderr = Join-Path $env:TEMP 'study_game_v2-game-api-contract.stderr.txt'

Set-Content -LiteralPath $stdout -Value ''
Set-Content -LiteralPath $stderr -Value ''
$process = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', '.', '--quit-after', '60', '--script', 'res://tests/game_api_contract.gd') -WorkingDirectory $project -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru

$output = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
Write-Output $output
if ($process.ExitCode -eq 0 -and $output -match '--- \d+ passed, 0 failed ---') {
	exit 0
}
throw 'game_api_contract did not report a clean completion marker.'
