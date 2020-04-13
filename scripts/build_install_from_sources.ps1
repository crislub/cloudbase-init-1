#ps1
param(
    [string]$CloudbaseInitRepoUrl="https://github.com/cloudbase/cloudbase-init",
    [string]$PyWin32RepoUrl="https://github.com/mhammond/pywin32",
    [string]$PyMiRepoUrl="https://github.com/cloudbase/PyMI",
    [ValidateSet("AlreadyInstalled", "Embedded", "FromSource")]
    [string]$PythonOrigin="AlreadyInstalled",
    # Specifies which version to use in case Embedded or FromSource is used
    # In Embedded case: "https://www.python.org/ftp/python/$PythonVersion" should exist
    # In FromSource case, the GitHub https://github.com/python/cpython branch should exist (tags also work as branches)
    [string]$PythonVersion="v3.7.7",
    # Specifies which setuptools git source to use in case Embedded or FromSource is used
    [string]$SetuptoolsGitUrl="https://github.com/pypa/setuptools",
    # Specifies which pip source in ttar.gz format to use in case Embedded or FromSource is used
    [string]$PipSourceUrl="https://github.com/pypa/pip/archive/20.0.2.tar.gz",
    # Specifies which wheel source in ttar.gz format to use in case Embedded or FromSource is used
    [string]$WheelSourceUrl="https://github.com/pypa/wheel/archive/0.34.2.tar.gz",
    # If the PythonOrigin is set to Embedded or FromSource, clean the Python folder (remove .pdb, .pyc, header files)
    [switch]$CleanBuildArtifacts,
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
        $Destination,
        $Branch="master"
    )

    Write-Host "Cloning ${Url} to ${Destination}"

    Run-CmdWithRetry {
        try {
            Push-Location $BuildDir
            git clone --single-branch -b $Branch $Url $Destination
            if ($LastExitCode) {
                throw "git clone --single-branch -b $Url $Branch $Destination failed"
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

    $cmdArgs = @("-W ignore", "-m", "pip", "install")
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

function Expand-Archive {
    param([string]$archive,
          [string]$outputDir
    )

    Push-Location $outputDir
    try {
        & "C:\Program Files\7-Zip\7z.exe" x -y $archive
        if ($LastExitCode) {
            throw "7z.exe failed on archive: $archive"
        }
    } finally {
        Pop-Location
    }
}

function Setup-PythonPackage {
    param([string]$SourcePath)

    Write-Host "Setup Python package from ${SourcePath}"

    $cmdArgs = @("-W ignore", "setup.py", "install")

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

    # Cloudbase-Init Python requirements should respect the OpenStack upper constraints
    Clone-Repo "https://github.com/openstack/requirements" "requirements"
    $constraintsFilePath = Join-Path $BuildDir "requirements/upper-constraints.txt"

    $env:PIP_CONSTRAINT = $constraintsFilePath
}

function Install-PyWin32FromSource {
    param($Url)

    $sourcePath = "pywin32"

    Clone-Repo $Url $sourceFolder
    Install-PythonPackage -SourcePath $sourcePath
}

function Install-ComtypesFromSource {
    param($Url)

    $sourcePath = "comptype"

    Clone-Repo $Url $sourcePath
    Install-PythonPackage -SourcePath $sourcePath
}

function Install-PyMI {
    param($Url)

    $sourcePath = "PyMI"

    Clone-Repo $Url $sourcePath
    Install-PythonRequirements -SourcePath $sourcePath -BuildWithoutBinaries
    Install-PythonPackage -SourcePath $sourcePath
}

function Install-CloudbaseInit {
    param($Url)

    $sourcePath = "cloudbase-init"

    Clone-Repo $Url $sourcePath
    Install-PythonRequirements -SourcePath $sourcePath -BuildWithoutBinaries
    Install-PythonPackage -SourcePath $sourcePath
}

function Install-SetuptoolsFromSource {
    param($Url)

    $sourcePath = "setuptools"

    Clone-Repo $Url $sourcePath

    Run-CmdWithRetry {
        try {
            Push-Location (Join-Path $BuildDir $SourcePath)
            Run-Command -Cmd "python" -Arguments @("-W ignore", ".\bootstrap.py")
            Run-Command -Cmd "python" -Arguments @("-W ignore", "setup.py", "install")
            Run-Command -Cmd "python" -Arguments @("-W ignore", "-m", "easy_install", $PipSourceUrl)
            Run-Command -Cmd "python" -Arguments @("-W ignore", "-m", "easy_install", $WheelSourceUrl)
        } finally {
            Pop-Location
        }
    }
}

function Setup-EmbeddedPythonEnvironment {
    param($EmbeddedPythonVersion)

    $EmbeddedPythonUrl = "https://www.python.org/ftp/python/${EmbeddedPythonVersion}/python-${EmbeddedPythonVersion}-embed-amd64.zip"
    $SourcePythonUrl = "https://www.python.org/ftp/python/${EmbeddedPythonVersion}/Python-${EmbeddedPythonVersion}.tgz"
    $pythonVersionHeader = "python" + (($EmbeddedPythonVersion.split(".") | Select-Object -First 2) -Join  "")

    Download-File $EmbeddedPythonUrl "${PythonDir}.zip"
    New-Item -Type Directory -Path $PythonDir
    Expand-Archive "${PythonDir}.zip" $PythonDir
    Remove-Item -Force "${PythonDir}.zip"

    $sourcePythonDir = "$BuildDir\source-python"
    Download-File "${SourcePythonUrl}" "${sourcePythonDir}.tgz"
    New-Item -Type Directory -Path $sourcePythonDir
    Expand-Archive "${sourcePythonDir}.tgz" $sourcePythonDir
    Remove-Item -Force "${sourcePythonDir}.tgz"
    New-Item -Type Directory -Path "$sourcePythonDir\src"
    Expand-Archive "${sourcePythonDir}\source-python.tar" "$sourcePythonDir\src"
    Remove-Item -Force -Recurse "${sourcePythonDir}\source-python.tar"
    $sourcePythonDir = "${sourcePythonDir}\src\Python-${EmbeddedPythonVersion}"

    Remove-Item -Force "${PythonDir}\${pythonVersionHeader}._pth"

    New-Item -Type Directory -Path "${PythonDir}\Lib"
    Expand-Archive "${PythonDir}\${pythonVersionHeader}.zip" "${PythonDir}\Lib"
    Remove-Item -Force "${PythonDir}\${pythonVersionHeader}.zip"

    Copy-Item -Recurse -Force "${sourcePythonDir}\Include" "${PythonDir}\"
    Copy-Item -Recurse -Force "${sourcePythonDir}\PC\pyconfig.h" "${PythonDir}\Include\"

    New-Item -Type Directory -Path "${PythonDir}\libs\"
    $pythonLibPath = "${PythonDir}\libs\${pythonVersionHeader}.lib"
    $pythonLibDefRawPath = "${PythonDir}\libs\${pythonVersionHeader}.raw.def"
    $pythonLibDefPath = "${PythonDir}\libs\${pythonVersionHeader}.def"
    $pythonDllPath = "${PythonDir}\${pythonVersionHeader}.dll"
    dumpbin.exe /exports "${pythonDllPath}" > "${pythonLibDefRawPath}"
    if ($LastExitCode) {
        throw "Failed to dump symbols"
    }
    Write-Output "EXPORTS" > "${pythonLibDefPath}"
    Get-Content "${pythonLibDefRawPath}" | ForEach-Object {
        $splitObject = $_.split(" ")
        [array]::reverse($splitObject)
        if ($splitObject[0] -clike "*Py*") {
            Write-Output $splitObject[0] >> "${pythonLibDefPath}"
        }
    }
    lib.exe /def:"${pythonLibDefPath}" /out:"${pythonLibPath}" /machine:x64
    if ($LastExitCode) {
        throw "Failed to create symbol map"
    }
    Remove-Item -Force $pythonLibDefRawPath
    Remove-Item -Force $pythonLibDefPath

    # Embedded Python has bdist_wininst.pyc reimplemented to throw an error if any package using this feature
    # is to be installed. Pywin32 and comtypes packages cannot be installed with pip or by running setup.py install.
    $bdistWininstFile = "${embeddedPythonDir}\Lib\distutils\command\bdist_wininst.py"
    Download-File "https://raw.githubusercontent.com/python/cpython/v${EmbeddedPythonVersion}/Lib/distutils/command/bdist_wininst.py" `
        $bdistWininstFile
    Remove-Item -Force "${bdistWininstFile}c"
}

function Setup-FromSourcePythonEnvironment {
    param($FromSourcePythonVersion)

    $sourceFolder = "python-source"
    $pythonSourceFolderPath = "$BuildDir\$sourceFolder"
    $pythonTempBuildDir = "$pythonSourceFolderPath\PCbuild\amd64"
    $pythonSourceRepo = "https://github.com/python/cpython"

    Clone-Repo -Url $pythonSourceRepo -Destination $sourceFolder -Branch $FromSourcePythonVersion
    Push-Location $pythonSourceFolderPath
    try {
        cmd.exe /c PCbuild\build.bat -p x64 --no-tkinter -e
        if ($LastExitCode) {
            throw "Failed to build Python from source"
        }
    } finally {
        Pop-Location
    }

    Move-Item $pythonTempBuildDir $PythonDir
    Copy-Item -Recurse "$pythonSourceFolderPath\Include" "$PythonDir"
    Copy-Item "$pythonSourceFolderPath\PC\pyconfig.h" "$PythonDir\Include\"

    Copy-Item -Recurse "$pythonSourceFolderPath\Lib" "$PythonDir"

    New-Item -Type Directory -Path "${PythonDir}\libs\"
    Copy-Item "$PythonDir\python*.lib" "${PythonDir}\libs\"
}

function Clean-BuildArtifacts {
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
        # There are used as global variables and their value do not change
        $BuildDir = Join-Path $scriptPath $BuildDir
        $PythonDir = Join-Path $BuildDir "python"
    }
    Prepare-BuildDir

    # Make sure VS 2015 is used
    Set-VCVars -Version "14.0"

    # Setup pip upper requirements
    Setup-PythonPip

    if (@("Embedded", "FromSource") -contains $PythonOrigin) {
        if (!($PythonVersion -and $SetuptoolsGitUrl -and $PipSourceUrl -and $WheelSourceUrl)) {
            throw "If PythonOrigin is set to ${PythonOrigin}, SetuptoolsGitUrl, PipSourceUrl and WheelSourceUrl must be set"
        }
        if ($PythonOrigin -eq "Embedded") {
            Setup-EmbeddedPythonEnvironment $PythonVersion
        } else {
            Setup-FromSourcePythonEnvironment $PythonVersion
        }
        $env:path = "${PythonDir};${PythonDir}\scripts;" + $env:path
        Install-SetuptoolsFromSource $SetuptoolsGitUrl
    }

    # Install PyWin32 from source
    #Install-PyWin32FromSource $PyWin32RepoUrl
    # TODO. Comment the following line and uncomment the line before. Keep this line for faster script testing (it takes more than 10 minutes to build the pywin32).
    python -m pip install pywin32

    # PyMI setup can be skipped once the upstream version is published on pypi
    Install-PyMI $PyMiRepoUrl

    Install-CloudbaseInit $CloudbaseInitRepoUrl

    if ($CleanBuildArtifacts -and (@("Embedded", "FromSource") -contains $PythonOrigin)) {
        Clean-BuildArtifacts
    }
} finally {
    $endDate = Get-Date
    Write-Host "Cloudbase-Init build finished after $(($endDate - $StartDate).Minutes + 1) minutes."
}

