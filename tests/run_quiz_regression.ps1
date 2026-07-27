$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe'
$project = Split-Path -Parent $PSScriptRoot
$stdout = Join-Path $env:TEMP 'study_game_v2-quiz-regression.stdout.txt'
$stderr = Join-Path $env:TEMP 'study_game_v2-quiz-regression.stderr.txt'

Set-Content -LiteralPath $stdout -Value ''
Set-Content -LiteralPath $stderr -Value ''
$process = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', '.', '--quit-after', '120', 'res://tests/QuizRegression.tscn') -WorkingDirectory $project -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru

$output = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
Write-Output $output
if ($process.ExitCode -eq 0 -and $output.Contains('quiz regression success')) {
	exit 0
}
if ($process.ExitCode -eq 0 -and $output.Contains('quiz regression failure:')) {
	exit 1
}
throw 'Quiz regression did not report a completion marker.'
