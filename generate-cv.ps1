[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Clean,
    [string]$OutputDir = ".",
    [switch]$OpenPdf,
    [switch]$InstallDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:MainTex = Join-Path $script:RepoRoot 'resume.tex'
$script:DefaultOutputDir = Resolve-Path -Path $script:RepoRoot
$script:LogsDir = Join-Path $script:RepoRoot 'logs'
$script:BuildLog = Join-Path $script:LogsDir 'build.log'
$script:ErrorLog = Join-Path $script:LogsDir 'error.log'
$script:PdfName = 'resume.pdf'

function Write-Color {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Green', 'Yellow', 'Red', 'Cyan', 'Gray')]
        [string]$Color = 'Gray'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Show-Usage {
    @"
Usage:
  .\generate-cv.ps1 [-OutputDir <path>] [-Clean] [-OpenPdf] [-InstallDependencies] [-Help] [-Verbose] [-Debug]

Options:
  -Help                 Show this help and exit.
  -OutputDir <path>     Output directory for generated PDF and logs. Default: repository root.
  -Clean                Remove temporary LaTeX artifacts (.aux, .log, .toc, .out, .synctex.gz).
  -OpenPdf              Open the resulting PDF after successful compilation.
  -InstallDependencies  If xelatex is missing, allow automatic installation flow.
  -Verbose              Common PowerShell parameter for additional execution details.
  -Debug                Common PowerShell parameter for stack traces on failures.

Examples:
  .\generate-cv.ps1
  .\generate-cv.ps1 -OutputDir .\dist -OpenPdf
  .\generate-cv.ps1 -InstallDependencies -Verbose
  .\generate-cv.ps1 -Clean
"@ | Write-Host
}

function Initialize-Logging {
    if (-not (Test-Path $script:LogsDir)) {
        New-Item -ItemType Directory -Path $script:LogsDir | Out-Null
    }
    "[$(Get-Date -Format o)] Build started" | Out-File -FilePath $script:BuildLog -Encoding UTF8
    "[$(Get-Date -Format o)] Errors" | Out-File -FilePath $script:ErrorLog -Encoding UTF8
}

function Write-BuildLog {
    param([string]$Text)
    $Text | Out-File -FilePath $script:BuildLog -Append -Encoding UTF8
}

function Write-ErrorLog {
    param([string]$Text)
    $Text | Out-File -FilePath $script:ErrorLog -Append -Encoding UTF8
}

function Test-IsWindows {
    if (-not $IsWindows -and [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'This script only supports Windows.'
    }
}

function Test-ExecutionPolicy {
    $policy = Get-ExecutionPolicy -Scope Process
    if ($policy -eq 'Restricted') {
        throw 'PowerShell execution policy is Restricted. Run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
    }
}

function Test-PathSafety {
    param([Parameter(Mandatory)] [string]$PathToCheck)
    $invalidPattern = '[<>:"|?*]'
    if ($PathToCheck -match $invalidPattern) {
        throw "Path contains problematic characters: $PathToCheck"
    }
}

function Test-WriteAccess {
    param([Parameter(Mandatory)] [string]$Directory)
    $probe = Join-Path $Directory (".write-test-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    try {
        'test' | Set-Content -Path $probe -Encoding UTF8
        Remove-Item -Path $probe -Force -ErrorAction SilentlyContinue
    }
    catch {
        throw "Write access test failed for directory: $Directory"
    }
}

function Get-Tool {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -ErrorAction SilentlyContinue
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Question)
    $answer = Read-Host "$Question [Y/N]"
    return $answer -match '^(Y|y)$'
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($machine -and $user) {
        $env:Path = "$machine;$user"
    }
}

function Install-TexDistribution {
    param([switch]$AskInstall)

    $winget = Get-Tool -Name 'winget'
    $choco = Get-Tool -Name 'choco'
    $scoop = Get-Tool -Name 'scoop'

    if (-not $winget -and -not $choco -and -not $scoop) {
        throw 'No supported package manager found (winget/choco/scoop). Install one and retry.'
    }

    $installers = @()
    if ($winget) { $installers += 'winget' }
    if ($choco) { $installers += 'choco' }
    if ($scoop) { $installers += 'scoop' }

    foreach ($installer in $installers) {
        switch ($installer) {
            'winget' {
                if ($AskInstall -and -not (Confirm-Action -Question 'xelatex no está instalado. ¿Deseas instalar MiKTeX automáticamente usando winget?')) { continue }
                Write-Color -Message 'Installing MiKTeX with winget...' -Color Cyan
                Start-Process -FilePath 'winget' -ArgumentList @('install', '--id', 'MiKTeX.MiKTeX', '-e', '--accept-source-agreements', '--accept-package-agreements') -Wait -NoNewWindow
                Refresh-Path
                if (Get-Tool -Name 'xelatex') { return }
                Write-Color -Message 'MiKTeX installation via winget did not expose xelatex. Trying TeX Live...' -Color Yellow
                Start-Process -FilePath 'winget' -ArgumentList @('install', '--id', 'TeXLive.TeXLive', '-e', '--accept-source-agreements', '--accept-package-agreements') -Wait -NoNewWindow
                Refresh-Path
                if (Get-Tool -Name 'xelatex') { return }
            }
            'choco' {
                if ($AskInstall -and -not (Confirm-Action -Question 'xelatex no está instalado. ¿Deseas instalar MiKTeX automáticamente usando Chocolatey?')) { continue }
                Write-Color -Message 'Installing MiKTeX with Chocolatey...' -Color Cyan
                Start-Process -FilePath 'choco' -ArgumentList @('install', 'miktex', '-y') -Wait -NoNewWindow
                Refresh-Path
                if (Get-Tool -Name 'xelatex') { return }
                Write-Color -Message 'MiKTeX failed with Chocolatey. Trying TeX Live...' -Color Yellow
                Start-Process -FilePath 'choco' -ArgumentList @('install', 'texlive', '-y') -Wait -NoNewWindow
                Refresh-Path
                if (Get-Tool -Name 'xelatex') { return }
            }
            'scoop' {
                if ($AskInstall -and -not (Confirm-Action -Question 'xelatex no está instalado. ¿Deseas instalar MiKTeX automáticamente usando Scoop?')) { continue }
                Write-Color -Message 'Installing MiKTeX with Scoop...' -Color Cyan
                Start-Process -FilePath 'scoop' -ArgumentList @('install', 'miktex') -Wait -NoNewWindow
                Refresh-Path
                if (Get-Tool -Name 'xelatex') { return }
                Write-Color -Message 'MiKTeX failed with Scoop. Trying TeX Live...' -Color Yellow
                Start-Process -FilePath 'scoop' -ArgumentList @('install', 'texlive') -Wait -NoNewWindow
                Refresh-Path
                if (Get-Tool -Name 'xelatex') { return }
            }
        }
    }
    throw 'Unable to install xelatex automatically. Check package manager logs and install manually.'
}

function Test-PdfLock {
    param([Parameter(Mandatory)] [string]$PdfPath)
    if (-not (Test-Path $PdfPath)) { return }
    try {
        $stream = [System.IO.File]::Open($PdfPath, 'Open', 'ReadWrite', 'None')
        $stream.Close()
    }
    catch {
        throw "The PDF appears locked by another process: $PdfPath. Close PDF viewers and retry."
    }
}

function Invoke-LatexBuild {
    param(
        [string]$TexFile,
        [string]$TargetDir,
        [int]$Runs = 2
    )

    $texFileName = Split-Path -Leaf $TexFile

    for ($i = 1; $i -le $Runs; $i++) {
        Write-Progress -Activity 'Compiling resume' -Status "xelatex pass $i of $Runs" -PercentComplete (($i / $Runs) * 100)
        $args = @('-interaction=nonstopmode', '-file-line-error', '-halt-on-error', "-output-directory=$TargetDir", $texFileName)
        Write-BuildLog "Running: xelatex $($args -join ' ')"
        $output = & xelatex @args 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = ($output | Out-String)
        Write-BuildLog $outputText

        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            Write-Host $outputText
        }

        if ($exitCode -ne 0) {
            Analyze-LatexErrors -BuildOutput $outputText
            throw "xelatex failed on pass $i with exit code $exitCode"
        }
    }
    Write-Progress -Activity 'Compiling resume' -Completed
}

function Analyze-LatexErrors {
    param([Parameter(Mandatory)] [string]$BuildOutput)
    $patterns = @{
        'Missing package' = 'LaTeX Error: File `.*\.sty'' not found|! LaTeX Error: File'
        'Missing image' = 'File: .* not found|Cannot determine size of graphic'
        'Encoding issue' = 'inputenc Error|Unicode character .* not set up'
        'Missing font' = 'fontspec error|The font .* cannot be found'
        'Broken references' = 'There were undefined references|Rerun to get cross-references right'
        'Syntax error' = '! Undefined control sequence|Runaway argument|Missing \$ inserted'
    }

    foreach ($label in $patterns.Keys) {
        if ($BuildOutput -match $patterns[$label]) {
            $msg = "Detected possible issue: $label"
            Write-Color -Message $msg -Color Yellow
            Write-ErrorLog $msg
        }
    }

    Write-ErrorLog $BuildOutput
}

function Invoke-Clean {
    param([string]$Directory)
    if (-not (Confirm-Action -Question 'Do you want to remove temporary LaTeX artifacts now?')) {
        Write-Color -Message 'Cleanup skipped by user.' -Color Yellow
        return
    }

    $extensions = @('*.aux', '*.log', '*.toc', '*.out', '*.synctex.gz')
    foreach ($pattern in $extensions) {
        Get-ChildItem -Path $Directory -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Color -Message 'Temporary files cleaned.' -Color Green
}

try {
    if ($Help) {
        Show-Usage
        exit 0
    }

    Initialize-Logging
    Test-IsWindows
    Test-ExecutionPolicy

    if (-not (Test-Path $script:RepoRoot)) { throw "Repository directory does not exist: $script:RepoRoot" }
    if (-not (Test-Path $script:MainTex)) { throw "Missing required file: $script:MainTex" }

    $texInfo = Get-Item $script:MainTex
    if ($texInfo.Length -eq 0) { throw 'resume.tex is empty.' }

    Test-PathSafety -PathToCheck $script:RepoRoot
    Test-PathSafety -PathToCheck $OutputDir

    $resolvedOutputDir = Resolve-Path -Path $OutputDir -ErrorAction SilentlyContinue
    if (-not $resolvedOutputDir) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        $resolvedOutputDir = Resolve-Path -Path $OutputDir
    }
    $resolvedOutputDir = $resolvedOutputDir.Path

    Test-WriteAccess -Directory $resolvedOutputDir

    if (-not $env:TEMP -or -not $env:Path) {
        throw 'Required environment variables are missing (TEMP and/or Path).'
    }

    $pdfPath = Join-Path $resolvedOutputDir $script:PdfName
    Test-PdfLock -PdfPath $pdfPath

    if (Test-Path $pdfPath) {
        if (-not (Confirm-Action -Question "Output PDF already exists at $pdfPath. Overwrite?")) {
            throw 'Build cancelled by user (overwrite not approved).'
        }
    }

    if (-not (Get-Tool -Name 'xelatex')) {
        Write-Color -Message 'xelatex is not installed or not available in PATH.' -Color Yellow
        if ($InstallDependencies) {
            Install-TexDistribution -AskInstall
        }
        else {
            throw 'xelatex missing. Re-run with -InstallDependencies or install MiKTeX/TeX Live manually.'
        }
    }

    if (-not (Get-Tool -Name 'xelatex')) {
        throw 'xelatex is still unavailable after installation attempt.'
    }

    Push-Location $script:RepoRoot
    try {
        Invoke-LatexBuild -TexFile $script:MainTex -TargetDir $resolvedOutputDir -Runs 2
    }
    finally {
        Pop-Location
    }

    if ($Clean) {
        Invoke-Clean -Directory $resolvedOutputDir
    }

    if ($OpenPdf) {
        Start-Process -FilePath $pdfPath
    }

    Write-Color -Message "PDF generated successfully: $pdfPath" -Color Green
    exit 0
}
catch {
    Write-Color -Message "Build failed: $($_.Exception.Message)" -Color Red
    Write-ErrorLog "[$(Get-Date -Format o)] $($_.Exception.Message)"
    if ($PSBoundParameters.ContainsKey('Debug') -or $DebugPreference -ne 'SilentlyContinue') {
        Write-Color -Message $_.ScriptStackTrace -Color Yellow
        Write-ErrorLog $_.ScriptStackTrace
    }
    exit 1
}
finally {
    Write-BuildLog "[$(Get-Date -Format o)] Build finished"
}
