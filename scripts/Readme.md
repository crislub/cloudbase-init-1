### Requirements ###

#### Clean Windows Server 2016 / 2019 or Windows 10 install with latest updates

#### Python installed and added to path (with pip installed) if PythonOrigin is set to AlreadyInstalled.
    Download link: https://www.python.org/ftp/python/3.7.7/python-3.7.7-amd64.exe

#### Visual Studio 2015 Community installed, with the following components:
    - Programming Languages -> Visual C++ (all)
    - Windows and Web Development -> Windows 8.1 (only Tools and Windows SDKs)

    VS 2015 Download page (you need to be logged in to access it): https://visualstudio.microsoft.com/vs/older-downloads/
    If you prefer to not build pywin32, Visual Studio 2017 / 2019 can be used too.
    Reboot after VS installation is complete.

#### To build Python from source, Visual Studio 2017 Community installed with the following components:
    - VC++ 2017 v141
    - Windows 10 SDK (10.0.14393.0). This version of VS supports Python 3.8 build too.

#### All the Python packages will be built and installed using pip flags: "--no-binary :all:"

#### The full build of cloudbase-init (and dependencies) using Python from source takes around 20 minutes.

#### How to run:


```powershell
# install Cloudbase-Init using Python already installed (Python and Python scripts folders should be added to path).
.\build_install_from_sources.ps1

# install Cloudbase-Init using Python from source (tag v3.7.7)
.\build_install_from_sources.ps1 -PythonOrigin FromSource -PythonVersion "v3.7.7"

# full command line
.\build_install_from_sources.ps1 `
    -CloudbaseInitRepoUrl "https://github.com/cloudbase/cloudbase-init" `
    -PyWin32RepoUrl "https://github.com/mhammond/pywin32" `
    -PyMiRepoUrl "https://github.com/cloudbase/PyMI" `
    -PythonOrigin "AlreadyInstalled" `
    -PythonVersion "v3.7.7" `
    -SetuptoolsUrl "https://github.com/pypa/setuptools" `
    -PipSourceUrl "https://github.com/pypa/pip/archive/20.0.2.tar.gz" `
    -WheelSourceUrl "https://github.com/pypa/wheel/archive/0.34.2.tar.gz" `,
    -CleanBuildArtifacts:$false,
    -RemoveUnnecessaryExecutables:$false,
    -RemovePyWin32Adodbapi:$false,
    -BuildDir "build"
```


#### Workflow of the script:
   - Download and set pip upper requirements from OpenStack
   - Create / clean temporary build directory
   - If PythonOrigin="AlreadyInstalled" is set, do nothing. Python should be already installed and added to path.
   - If PythonOrigin="FromSource" is set, download the Python source from GitHub, build, prepare it and add it to path. Setuptools, pip and wheel will be built from source and installed.
   - Build and install PyWin32 from sources
   - Build and install PyMI from sources
   - Build, install and create Cloudbase-Init binary from sources
   - If CleanBuildArtifacts is set and PythonOrigin is FromSource, cleanup the .pdb, .pyc, header files.
   - If RemoveUnnecessaryExecutables is set and PythonOrigin is FromSource, remove the .exe files (excluding python.exe, setuptools/pip/wheel and cloudbase-init.exe).
   - If RemovePyWin32Adodbapi is set, remove the Adodbapi sources and references from PyWin32 source code
