$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe'
$project = Split-Path -Parent $PSScriptRoot
$stdout = Join-Path $env:TEMP 'study_game_v2-ranch-off-smoke.stdout.txt'
$stderr = Join-Path $env:TEMP 'study_game_v2-ranch-off-smoke.stderr.txt'

Set-Content -LiteralPath $stdout -Value ''
Set-Content -LiteralPath $stderr -Value ''
$process = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', '.', '--quit-after', '120', 'res://tests/RanchOffSmoke.tscn') -WorkingDirectory $project -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru

$output = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
Write-Output $output
if ($output.Contains("Invalid access to property or key 'size' on a base object of type 'Nil'")) {
	exit 1
}
if ($process.ExitCode -eq 0 -and $output.Contains('ranch-off smoke success')) {
	exit 0
}
throw 'Ranch smoke did not report a clean completion marker.'
