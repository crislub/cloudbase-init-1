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

function Run-CmdWithRetry($command, $maxRetryCount = 3, $retryInterval=1) {
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}


function Download-File($url, $dest) {
    Write-Host "Downloading: $url"

    $webClient = New-Object System.Net.webclient
    Run-CmdWithRetry {
        $webClient.DownloadFile($url, $dest)
    }
}

function Clone-Repo {
    param($Url, $Destination)

    Run-CmdWithRetry {
        try {
            pushd $BuildDir
            git clone $Url $Destination
            if ($LastExitCode) {
                throw "git clone ${Url} ${Destination} failed" 
            }
        } finally {
            popd
        }
    }
}

function Install-PythonRequirements {
    param($Destination)

    Run-CmdWithRetry {
        try {
            pushd (Join-Path $BuildDir $Destination)
            pip install -r .\requirements.txt
            if ($LastExitCode) {
                throw "'pip install -r .\requirements.txt' in ${Destination} failed" 
            }
        } finally {
            popd
        }
    }
}

function Install-PythonPackage {
    param($Destination)

    Run-CmdWithRetry {
        try {
            pushd (Join-Path $BuildDir $Destination)
            pip install .
            if ($LastExitCode) {
                throw "'pip install .' in ${Destination} failed" 
            }
        } finally {
            popd
        }
    }
}

function Prepare-BuildDir {
    if ($BuildDir -and (Test-Path $BuildDir)) {
        Remove-Item -Recurse -Force $BuildDir
    }
    New-Item -Type Directory -Path $BuildDir -Force | Out-Null
}

function Setup-PythonPip {
    $env:PIP_CONSTRAINT = ""
    $env:PIP_NO_BINARY=""

    # Update pip
    Download-File "https://bootstrap.pypa.io/get-pip.py" "${BuildDir}/get-pip.py"
    Run-CmdWithRetry {
        python "${BuildDir}/get-pip.py"
        if ($LastExitCode) {
            throw "Failed to run 'python get-pip.py'"
        }
    }

    # Cloudbase-Init Python requirements should respect the OpenStack upper constraints
    Clone-Repo "https://github.com/openstack/requirements" "requirements"
    $constraintsFilePath = Join-Path $BuildDir "requirements/upper-constraints.txt"

    $env:PIP_CONSTRAINT = $constraintsFilePath
    $env:PIP_NO_BINARY=":all:"
}

function Install-PyWin32 {
    Run-CmdWithRetry {
        pip install pywin32
        if ($LastExitCode) {
            throw "'pip install pywin32' failed" 
        }
    }
}

function Install-PyWin32FromSource {
    param($Url)

    $sourceFolder = "pywin32"

    Clone-Repo $Url $sourceFolder
    Install-PythonPackage $sourceFolder
}

function Install-PyMI {
    param($Url)

    $sourceFolder = "PyMI"

    Clone-Repo $Url $sourceFolder
    Install-PythonRequirements $sourceFolder
    Install-PythonPackage $sourceFolder
}

function Install-CloudbaseInit {
    param($Url)

    $sourceFolder = "cloudbase-init"

    Clone-Repo $Url $sourceFolder
    Install-PythonRequirements $sourceFolder
    $env:PIP_NO_BINARY=""
    Install-PythonPackage $sourceFolder
}


### Requirements ###

## Clean Windows Server 2016 /2019 or Windows 10 install with latest updates

## Python 3.7 installed and added to path (with pip installed).
##     Download link: https://www.python.org/ftp/python/3.7.0/python-3.7.0-amd64.exe

## Visual Studio 2015 Community installed, with the following components:
##     - Visual C++ (all)
##     - Python Tools for VS
##     - Windows 8.1 (only Tools and Windows SDKs)
##
##    VS 2015 Download link (you need to be logged in to access it): https://download.my.visualstudio.com/db/en_visual_studio_community_2015_with_update_1_x86_x64_web_installer_8234321.exe
##    If you prefer to not build pywin32, Visual Studio 2017 / 2019 can be used too
##    Do not install other versions of Visual Studio, as the default paths might get reused and you will run into dependency issues

## All the Python packages will be built and installed using pip flags: "--no-binary :all:"
## The full build of pywin32, pymi and cloudbase-init from sources takes around 10 minutes.


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

    # Update pip, setup pip upper requirements
    Setup-PythonPip

    # Install PyWin32 from source
    # If you want to install it directly from wheel, use:
    # Install-PyWin32
    Install-PyWin32FromSource $PyWin32RepoUrl

    # PyMI setup can be skipped once the upstream version is published on pypi
    Install-PyMI $PyMiRepoUrl

    Install-CloudbaseInit $CloudbaseInitRepoUrl
} finally {
    $endDate = Get-Date
    Write-Host "Cloudbase-Init build finished after $(($endDate - $StartDate).Minutes) minutes."
}

