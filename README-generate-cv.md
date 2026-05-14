# CV Build Automation (PowerShell)

This repository includes a production-ready script: `generate-cv.ps1`.
It compiles `resume.tex` to PDF using `xelatex`, with validation, dependency handling, cleanup, and actionable diagnostics.

## Requirements

- Windows 10/11 or Windows Server
- PowerShell 5.1+ or PowerShell 7+
- `resume.tex` present at repository root
- Write permissions in the output directory
- A TeX distribution providing `xelatex`:
  - Preferred: MiKTeX
  - Alternative: TeX Live

## Expected Folder Structure

```text
repo-root/
├─ resume.tex
├─ generate-cv.ps1
├─ logs/
│  ├─ build.log
│  └─ error.log
└─ resume.pdf (or OutputDir/resume.pdf)
```

## Automatic Dependency Installation

If `xelatex` is missing and you run with `-InstallDependencies`, the script:

1. Detects package managers in this order:
   - Winget
   - Chocolatey
   - Scoop
2. Asks for confirmation before any installation.
3. Attempts MiKTeX first, then TeX Live if needed.
4. Refreshes `PATH` and re-validates `xelatex`.

## Manual Installation

If you prefer manual setup, install one of:

- MiKTeX: <https://miktex.org/download>
- TeX Live: <https://www.tug.org/texlive/windows.html>

Then verify:

```powershell
xelatex --version
```

## Usage Examples

```powershell
# Basic build
.\generate-cv.ps1

# Build with auto-install flow (with confirmations)
.\generate-cv.ps1 -InstallDependencies

# Build to custom output dir and open the PDF
.\generate-cv.ps1 -OutputDir .\dist -OpenPdf

# Build with additional output
.\generate-cv.ps1 -Verbose

# Build and remove temporary artifacts
.\generate-cv.ps1 -Clean

# Show integrated help
.\generate-cv.ps1 -Help
```

## Troubleshooting

### `xelatex` not found

- Run with `-InstallDependencies`, or install MiKTeX/TeX Live manually.
- Restart terminal and run `xelatex --version`.

### PDF is locked

- Close Adobe Reader / browser tabs / preview apps using `resume.pdf`.
- Retry build.

### Missing package or file

- Check `logs/error.log` and `logs/build.log`.
- For MiKTeX users, allow package-on-the-fly installation.

### Font or encoding errors

- Ensure required fonts are present in the repository.
- Confirm `resume.tex` uses UTF-8.

### Access denied

- Ensure write permissions in output path.
- If needed, launch PowerShell as Administrator.

## Common Error Categories Detected

The script highlights likely root causes when LaTeX fails:

- Missing packages (`.sty`)
- Missing images/assets
- Encoding issues
- Missing fonts
- Broken references
- LaTeX syntax/control sequence errors

## Logging

Persistent logs are written to:

- `logs/build.log` (full compile output)
- `logs/error.log` (error-focused diagnostics)

These logs help with CI, support tickets, and local debugging.
