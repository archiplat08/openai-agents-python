# Examples Auto-Run Script for Windows PowerShell
# Automatically discovers and runs example scripts in the repository

param(
    [string]$ExamplesDir = "examples",
    [string]$PythonCmd = "python",
    [int]$TimeoutSeconds = 30,
    [switch]$FailFast,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$Script:PassCount = 0
$Script:FailCount = 0
$Script:SkipCount = 0
$Script:Results = @()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        "SKIP"    { "Cyan" }
        default   { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-PythonAvailable {
    try {
        $version = & $PythonCmd --version 2>&1
        Write-Log "Using Python: $version"
        return $true
    } catch {
        Write-Log "Python not found at '$PythonCmd'" "ERROR"
        return $false
    }
}

function Get-ExampleFiles {
    param([string]$Directory)
    
    if (-not (Test-Path $Directory)) {
        Write-Log "Examples directory '$Directory' not found" "WARN"
        return @()
    }
    
    return Get-ChildItem -Path $Directory -Filter "*.py" -Recurse |
        Where-Object { $_.Name -notlike "_*" } |
        Sort-Object FullName
}

function Should-SkipExample {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return $true }
    
    # Skip files with skip markers
    if ($content -match "# skip-auto-run" -or $content -match "# noqa: auto-run") {
        return $true
    }
    
    # Skip files that require interactive input
    if ($content -match "input\(" -and $content -notmatch "# auto-run-ok") {
        return $true
    }
    
    return $false
}

function Invoke-ExampleScript {
    param([string]$FilePath)
    
    $relativePath = Resolve-Path -Relative $FilePath
    
    if (Should-SkipExample $FilePath) {
        Write-Log "SKIP: $relativePath" "SKIP"
        $Script:SkipCount++
        $Script:Results += [PSCustomObject]@{ File = $relativePath; Status = "SKIP"; Duration = 0; Error = "" }
        return
    }
    
    Write-Log "Running: $relativePath"
    $startTime = Get-Date
    
    try {
        $job = Start-Job -ScriptBlock {
            param($python, $file)
            & $python $file 2>&1
        } -ArgumentList $PythonCmd, $FilePath
        
        $completed = Wait-Job $job -Timeout $TimeoutSeconds
        
        if ($null -eq $completed) {
            Stop-Job $job
            Remove-Job $job -Force
            throw "Timed out after $TimeoutSeconds seconds"
        }
        
        $output = Receive-Job $job
        $exitCode = $job.State
        Remove-Job $job -Force
        
        $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        
        if ($job.State -eq "Failed" -or ($output -match "Error" -and $output -match "Traceback")) {
            throw ($output -join "`n")
        }
        
        if ($Verbose) {
            Write-Host $output
        }
        
        Write-Log "PASS: $relativePath (${duration}s)" "SUCCESS"
        $Script:PassCount++
        $Script:Results += [PSCustomObject]@{ File = $relativePath; Status = "PASS"; Duration = $duration; Error = "" }
        
    } catch {
        $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        $errorMsg = $_.Exception.Message
        Write-Log "FAIL: $relativePath - $errorMsg" "ERROR"
        $Script:FailCount++
        $Script:Results += [PSCustomObject]@{ File = $relativePath; Status = "FAIL"; Duration = $duration; Error = $errorMsg }
        
        if ($FailFast) {
            Write-Log "Stopping due to -FailFast flag" "WARN"
            exit 1
        }
    }
}

function Write-Summary {
    $total = $Script:PassCount + $Script:FailCount + $Script:SkipCount
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor DarkGray
    Write-Log "Results: $total total | $($Script:PassCount) passed | $($Script:FailCount) failed | $($Script:SkipCount) skipped"
    
    if ($Script:FailCount -gt 0) {
        Write-Host ""
        Write-Log "Failed examples:" "ERROR"
        $Script:Results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
            Write-Host "  - $($_.File): $($_.Error)" -ForegroundColor Red
        }
    }
    Write-Host "=" * 60 -ForegroundColor DarkGray
}

# Main execution
Write-Log "Starting examples auto-run"
Write-Log "Examples directory: $ExamplesDir"

if (-not (Test-PythonAvailable)) {
    exit 1
}

$examples = Get-ExampleFiles -Directory $ExamplesDir

if ($examples.Count -eq 0) {
    Write-Log "No example files found in '$ExamplesDir'" "WARN"
    exit 0
}

Write-Log "Found $($examples.Count) example file(s)"

foreach ($example in $examples) {
    Invoke-ExampleScript -FilePath $example.FullName
}

Write-Summary

if ($Script:FailCount -gt 0) {
    exit 1
}

exit 0
