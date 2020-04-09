#ps1
param(
    [string]$CloudbaseInitRepoUrl="https://github.com/cloudbase/cloudbase-init",
    [string]$PyWin32RepoUrl="https://github.com/mhammond/pywin32",
    [string]$PyMiRepoUrl="https://github.com/cloudbase/PyMI",
    [string]$BuildDir=""
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$PIP_BUILD_NO_BINARIES_ARGS = "--no-binary :all:"

function Run-CmdWithRetry {
    param(
        $command,
        [int]$maxRetryCount=3,
        [int]$retryInterval=1
    )

    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true) {
        try {
            & $command
            break
        } catch [System.Exception] {
            $retryCount++
            if ($retryCount -ge $maxRetryCount) {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            } else {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function Download-File {
    param(
        $url,
        $dest
    )

    Write-Host "Downloading: $url"

    $webClient = New-Object System.Net.webclient
    Run-CmdWithRetry {
        $webClient.DownloadFile($url, $dest)
    }
}

function Set-VCVars {
    param(
        $Version="14.0",
        $Platform="x86_amd64"
    )

    Write-Host "Setting Visual Studio version ${Version} environment variables"

    Push-Location "$ENV:ProgramFiles (x86)\Microsoft Visual Studio ${Version}\VC\"
    try {
        cmd /c "vcvarsall.bat $platform & set" |
            ForEach-Object {
                if ($_ -match "=") {
                    $v = $_.split("=")
                    Set-Item -Force -Path "ENV:\$($v[0])" -Value "$($v[1])"
              }
            }
    } finally {
        Pop-Location
    }
}

function Run-Command {
    param(
        $cmd,
        $arguments,
        $expectedExitCode = 0
    )

    Write-Host "Executing: $cmd $arguments"

    $p = Start-Process -Wait -PassThru `
        -NoNewWindow $cmd -ArgumentList $arguments
    if ($p.ExitCode -ne $expectedExitCode) {
        throw "$cmd failed with exit code: $($p.ExitCode)"
    }
}

function Clone-Repo {
    param(
        $Url,
        $Destination
    )

    Write-Host "Cloning ${Url} to ${Destination}"

    Run-CmdWithRetry {
        try {
            Push-Location $BuildDir
            git clone $Url $Destination
            if ($LastExitCode) {
                throw "git clone ${Url} ${Destination} failed"
            }
        } finally {
            Pop-Location
        }
    }
}

function Install-PythonRequirements {
    param([string]$SourcePath,
          [switch]$BuildWithoutBinaries
    )

    Write-Host "Installing Python requirements from ${SourcePath}"

    $cmdArgs = @("-m", "pip", "install")
    if ($BuildWithoutBinaries) {
        $cmdArgs += $PIP_BUILD_NO_BINARIES_ARGS
    }
    $cmdArgs += @("-r", ".\requirements.txt")

    Run-CmdWithRetry {
        try {
            Push-Location (Join-Path $BuildDir $SourcePath)
            Run-Command -Cmd "python" -Arguments $cmdArgs
        } finally {
            Pop-Location
        }
    }
}

function Install-PythonPackage {
    param([string]$SourcePath,
          [switch]$BuildWithoutBinaries
    )

    Write-Host "Installing Python package from ${SourcePath}"

    $cmdArgs = @("-m", "pip", "install")
    if ($BuildWithoutBinaries) {
        $cmdArgs += $PIP_BUILD_NO_BINARIES_ARGS
    }
    $cmdArgs += "."

    Run-CmdWithRetry {
        try {
            Push-Location (Join-Path $BuildDir $SourcePath)
            Run-Command -Cmd "python" -Arguments $cmdArgs
        } finally {
            Pop-Location
        }
    }
}

function Prepare-BuildDir {
    Write-Host "Creating / Cleaning up build directory ${BuildDir}"

    if ($BuildDir -and (Test-Path $BuildDir)) {
        Remove-Item -Recurse -Force $BuildDir
    }
    New-Item -Type Directory -Path $BuildDir -Force | Out-Null
}

function Setup-PythonPip {
    $env:PIP_CONSTRAINT = ""
    $env:PIP_NO_BINARY = ""

    # Update pip. Not needed for latest version of Python 3.7.
    # Download-File "https://bootstrap.pypa.io/get-pip.py" "${BuildDir}/get-pip.py"
    # Run-CmdWithRetry {
    #    python "${BuildDir}/get-pip.py"
    #    if ($LastExitCode) {
    #        throw "Failed to run 'python get-pip.py'"
    #    }
    #}

    # Cloudbase-Init Python requirements should respect the OpenStack upper constraints
    Clone-Repo "https://github.com/openstack/requirements" "requirements"
    $constraintsFilePath = Join-Path $BuildDir "requirements/upper-constraints.txt"

    $env:PIP_CONSTRAINT = $constraintsFilePath
}

function Install-PyWin32FromSource {
    param($Url)

    $sourcePath = "pywin32"

    Clone-Repo $Url $sourceFolder
    Install-PythonPackage -SourcePath $sourcePath -BuildWithoutBinaries
}

function Install-PyMI {
    param($Url)

    $sourcePath = "PyMI"

    Clone-Repo $Url $sourcePath
    Install-PythonRequirements -SourcePath $sourcePath -BuildWithoutBinaries
    Install-PythonPackage -SourcePath $sourcePath -BuildWithoutBinaries
}

function Install-CloudbaseInit {
    param($Url)

    $sourcePath = "cloudbase-init"

    Clone-Repo $Url $sourcePath
    Install-PythonRequirements -SourcePath $sourcePath -BuildWithoutBinaries
    Install-PythonPackage -SourcePath $sourcePath
}

### Main ###

try {
    $startDate = Get-Date
    Write-Host "Cloudbase-Init build started."

    # Make sure that BuildDir is created and cleaned up properly
    if (!$BuildDir) {
        $BuildDir = "build"
    }
    if (![System.IO.Path]::IsPathRooted($BuildDir)) {
        $BuildDir = Join-Path $scriptPath $BuildDir
    }
    Prepare-BuildDir

    # Make sure VS 2015 is used
    Set-VCVars -Version "14.0"

    # Setup pip upper requirements
    Setup-PythonPip

    # Install PyWin32 from source
    Install-PyWin32FromSource $PyWin32RepoUrl

    # PyMI setup can be skipped once the upstream version is published on pypi
    Install-PyMI $PyMiRepoUrl

    Install-CloudbaseInit $CloudbaseInitRepoUrl
} finally {
    $endDate = Get-Date
    Write-Host "Cloudbase-Init build finished after $(($endDate - $StartDate).Minutes + 1) minutes."
}

