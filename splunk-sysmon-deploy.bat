@echo off
REM ============================================================================
REM  Splunk Universal Forwarder + Sysmon Deployment Script
REM ----------------------------------------------------------------------------
REM  Repository : splunk-sysmon-deploy
REM  Author     : Shahpasandi
REM  Website    : https://shahpasandi.github.io/
REM  License    : MIT
REM ----------------------------------------------------------------------------
REM  Idempotent deployment script for Windows endpoints.
REM  Installs / upgrades Splunk Universal Forwarder, installs / refreshes
REM  Sysmon, and deploys inputs.conf / outputs.conf from a central share.
REM  Designed to be distributed via Active Directory Group Policy (GPO).
REM ============================================================================

setlocal EnableExtensions EnableDelayedExpansion
cls

echo ==========================================
echo       Splunk / Sysmon Deployment Script
echo ==========================================
echo   Author : Shahpasandi
echo   Web    : https://shahpasandi.github.io/
echo ==========================================
echo.

REM =========================================================
REM CONFIGURATION - EDIT THESE VALUES FOR YOUR ENVIRONMENT
REM =========================================================

REM Base path of the network share hosting deployment files.
REM Example: \\fileserver\share\Splunk_GPO\Splunk_for_Servers
set "DEPLOY_SHARE=\\YOUR-FILESERVER\YOUR-SHARE\Splunk_for_Servers"

REM Individual file names (relative to DEPLOY_SHARE)
set "SYSMON_EXE_NAME=Sysmon64.exe"
set "SYSMON_CONFIG_NAME=sysmonconfig-export.xml"
set "SPLUNK_MSI_NAME=splunkforwarder-10.6.1.1-b2ae2962645c-windows-x64.msi"
set "INPUTS_CONFIG_NAME=inputs.conf"
set "OUTPUTS_CONFIG_NAME=outputs.conf"

REM Full paths (do not edit unless you know what you are doing)
set "SYSMON_EXE=%DEPLOY_SHARE%\%SYSMON_EXE_NAME%"
set "SYSMON_CONFIG=%DEPLOY_SHARE%\%SYSMON_CONFIG_NAME%"
set "SPLUNK_MSI=%DEPLOY_SHARE%\%SPLUNK_MSI_NAME%"
set "INPUTS_CONFIG=%DEPLOY_SHARE%\%INPUTS_CONFIG_NAME%"
set "OUTPUTS_CONFIG=%DEPLOY_SHARE%\%OUTPUTS_CONFIG_NAME%"

REM =========================================================
REM LOCAL PATHS (do not edit)
REM =========================================================

set "SPLUNK_HOME=C:\Program Files\SplunkUniversalForwarder"
set "LOCAL_INPUTS=%SPLUNK_HOME%\etc\apps\SplunkUniversalForwarder\local\inputs.conf"
set "LOCAL_OUTPUTS=%SPLUNK_HOME%\etc\system\local\outputs.conf"
set "SPLUNK_EXE=%SPLUNK_HOME%\bin\splunk.exe"

set "SPLUNK_CONFIG_CHANGED=0"
set "SYSMON_CONFIG_CHANGED=0"

REM =========================================================
REM HASH STORAGE PATHS
REM =========================================================

set "SYSMON_HASH_FILE=%ProgramData%\SplunkSysmonConfig.sha256"
set "SPLUNK_MSI_HASH_FILE=%ProgramData%\SplunkMSI.sha256"
set "SPLUNK_VERSION_FILE=%ProgramData%\SplunkVersion.txt"

REM =========================================================
REM CHECK NETWORK SHARE
REM =========================================================

echo [ + ] Checking network share...

if not exist "%SYSMON_EXE%" (
    echo [ ! ] Cannot access network share or Sysmon64.exe not found.
    echo [ ! ] Deployment aborted.
    goto :END
)

echo [ + ] Network share is accessible.
echo.

REM =========================================================
REM CHECK REQUIRED FILES
REM =========================================================

echo [ + ] Checking required files...

if not exist "%SYSMON_CONFIG%" (
    echo [ ! ] Sysmon configuration file not found:
    echo     %SYSMON_CONFIG%
    goto :END
)

if not exist "%SPLUNK_MSI%" (
    echo [ ! ] Splunk Universal Forwarder MSI not found:
    echo     %SPLUNK_MSI%
    goto :END
)

if not exist "%INPUTS_CONFIG%" (
    echo [ ! ] inputs.conf not found:
    echo     %INPUTS_CONFIG%
    goto :END
)

if not exist "%OUTPUTS_CONFIG%" (
    echo [ ! ] outputs.conf not found:
    echo     %OUTPUTS_CONFIG%
    goto :END
)

echo [ + ] All required files are available.
echo.

REM =========================================================
REM EXTRACT VERSION FROM MSI FILENAME
REM =========================================================

echo [ + ] Extracting version from MSI filename...

for /f "tokens=2 delims=-" %%A in ("%SPLUNK_MSI%") do (
    set "MSI_VERSION=%%A"
    goto :MSI_VERSION_EXTRACTED
)

:MSI_VERSION_EXTRACTED
echo [ + ] MSI Version: !MSI_VERSION!
echo.

REM =========================================================
REM GET INSTALLED SPLUNK VERSION - IMPROVED METHOD
REM =========================================================

echo [ + ] Checking installed Splunk version...

set "INSTALLED_VERSION="

if exist "%SPLUNK_EXE%" (
    pushd "%SPLUNK_HOME%\bin" 2>nul
    if not errorlevel 1 (
        for /f "tokens=4" %%V in ('splunk.exe version 2^>nul ^| find "Splunk Universal Forwarder"') do (
            set "INSTALLED_VERSION=%%V"
        )
        popd
    )
)

if not defined INSTALLED_VERSION (
    REM Alternative: Check via registry
    for /f "tokens=3" %%V in ('reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\Splunk Universal Forwarder" /v DisplayVersion 2^>nul') do (
        set "INSTALLED_VERSION=%%V"
    )
)

if defined INSTALLED_VERSION (
    echo [ + ] Installed Version: !INSTALLED_VERSION!
) else (
    echo [ ! ] Could not determine installed version.
    set "INSTALLED_VERSION=UNKNOWN"
)

echo.

REM =========================================================
REM SYSMON INSTALLATION AND CONFIGURATION
REM =========================================================

echo [ + ] Checking Sysmon status...

sc query Sysmon64 >nul 2>&1

if errorlevel 1 (

    echo [ + ] Sysmon64 is not installed.
    echo [ + ] Installing Sysmon64 for the first time...

    "%SYSMON_EXE%" -accepteula -i "%SYSMON_CONFIG%"

    if errorlevel 1 (
        echo [ ! ] Sysmon installation failed.
    ) else (
        echo [ + ] Sysmon64 installed successfully.
        call :STORE_SYSMON_HASH
        set "SYSMON_CONFIG_CHANGED=1"
    )

) else (

    echo [ + ] Sysmon64 is already installed.
    echo [ + ] Checking Sysmon configuration...

    call :COMPARE_SYSMON_HASH

    if "!COMPARE_RESULT!"=="CHANGED" (

        echo [ + ] Sysmon configuration has changed.
        echo [ + ] Updating Sysmon64 configuration...

        "%SYSMON_EXE%" -c "%SYSMON_CONFIG%"

        if errorlevel 1 (
            echo [ ! ] Sysmon configuration update failed.
        ) else (
            echo [ + ] Sysmon configuration updated successfully.
            call :STORE_SYSMON_HASH
            set "SYSMON_CONFIG_CHANGED=1"
            echo [ + ] New Sysmon configuration hash stored.
        )

    ) else (

        echo [ + ] Sysmon configuration is already up to date.

    )
)

echo.

REM =========================================================
REM SPLUNK UNIVERSAL FORWARDER - CHECK AND UPGRADE
REM =========================================================

echo [ + ] Checking Splunk Universal Forwarder...

if exist "%SPLUNK_EXE%" (

    echo [ + ] Splunk Forwarder is already installed.
    echo [ + ] Installed version: !INSTALLED_VERSION!
    echo [ + ] Network version: !MSI_VERSION!

    REM Compare versions (only if we have a valid installed version)
    if not "!INSTALLED_VERSION!"=="UNKNOWN" (
        if "!MSI_VERSION!"=="!INSTALLED_VERSION!" (
            echo [ + ] Splunk version is already up to date.
        ) else (
            echo [ + ] Version mismatch detected! Upgrading from !INSTALLED_VERSION! to !MSI_VERSION!...
            echo [ + ] Upgrading Splunk Universal Forwarder...

            REM Stop Splunk service before upgrade
            net stop SplunkForwarder >nul 2>&1
            timeout /t 3 /nobreak >nul

            REM Perform upgrade using msiexec
            msiexec.exe /i "%SPLUNK_MSI%" ^
                AGREETOLICENSE="Yes" ^
                INSTALLDIR="%SPLUNK_HOME%" ^
                LAUNCHSPLUNK="1" ^
                INSTALL_SHORTCUT="0" ^
                USE_LOCAL_SYSTEM=1 ^
                /quiet ^
                /norestart ^
                /lv* "%TEMP%\splunk_upgrade_!MSI_VERSION!.log"

            if errorlevel 1 (
                echo [ ! ] Splunk upgrade failed!
                echo [ ! ] Error code: !errorlevel!
                echo [ ! ] Check log: %TEMP%\splunk_upgrade_!MSI_VERSION!.log
                set "SPLUNK_CONFIG_CHANGED=0"
            ) else (
                echo [ + ] Splunk upgraded successfully to version !MSI_VERSION!
                call :STORE_SPLUNK_MSI_HASH
                echo !MSI_VERSION! > "%SPLUNK_VERSION_FILE%"
                set "SPLUNK_CONFIG_CHANGED=1"
            )
        )
    ) else (
        echo [ ! ] Cannot verify version. Forcing upgrade...
        echo [ + ] Upgrading Splunk Universal Forwarder...

        msiexec.exe /i "%SPLUNK_MSI%" ^
            AGREETOLICENSE="Yes" ^
            INSTALLDIR="%SPLUNK_HOME%" ^
            LAUNCHSPLUNK="1" ^
            INSTALL_SHORTCUT="0" ^
            USE_LOCAL_SYSTEM=1 ^
            /quiet ^
            /norestart ^
            /lv* "%TEMP%\splunk_upgrade_!MSI_VERSION!.log"

        if errorlevel 1 (
            echo [ ! ] Splunk upgrade failed!
            echo [ ! ] Error code: !errorlevel!
            set "SPLUNK_CONFIG_CHANGED=0"
        ) else (
            echo [ + ] Splunk upgraded successfully to version !MSI_VERSION!
            call :STORE_SPLUNK_MSI_HASH
            echo !MSI_VERSION! > "%SPLUNK_VERSION_FILE%"
            set "SPLUNK_CONFIG_CHANGED=1"
        )
    )

) else (

    echo [ + ] Splunk Forwarder is not installed.
    echo [ + ] Installing Splunk Universal Forwarder version !MSI_VERSION!...

    msiexec.exe /i "%SPLUNK_MSI%" ^
        AGREETOLICENSE="Yes" ^
        INSTALLDIR="%SPLUNK_HOME%" ^
        LAUNCHSPLUNK="1" ^
        INSTALL_SHORTCUT="0" ^
        USE_LOCAL_SYSTEM=1 ^
        /quiet ^
        /norestart

    if errorlevel 1 (

        echo [ ! ] Splunk Universal Forwarder installation failed.
        echo [ ! ] Error code: !errorlevel!
        goto :END

    ) else (

        echo [ + ] Splunk Universal Forwarder installed successfully.
        call :STORE_SPLUNK_MSI_HASH
        echo !MSI_VERSION! > "%SPLUNK_VERSION_FILE%"
        set "SPLUNK_CONFIG_CHANGED=1"

    )
)

echo.

REM =========================================================
REM INPUTS.CONF DEPLOYMENT
REM =========================================================

echo [ + ] Checking inputs.conf...

call :COMPARE_FILES "%INPUTS_CONFIG%" "%LOCAL_INPUTS%"

if "!COMPARE_RESULT!"=="CHANGED" (

    echo [ + ] inputs.conf has changed.
    echo [ + ] Updating inputs.conf...

    if not exist "%SPLUNK_HOME%\etc\apps\SplunkUniversalForwarder\local" (
        mkdir "%SPLUNK_HOME%\etc\apps\SplunkUniversalForwarder\local" >nul 2>&1
    )

    copy /Y "%INPUTS_CONFIG%" "%LOCAL_INPUTS%" >nul

    if errorlevel 1 (

        echo [ ! ] Failed to update inputs.conf.

    ) else (

        echo [ + ] inputs.conf updated successfully.
        set "SPLUNK_CONFIG_CHANGED=1"

    )

) else (

    echo [ + ] inputs.conf is already up to date.

)

echo.

REM =========================================================
REM OUTPUTS.CONF DEPLOYMENT
REM =========================================================

echo [ + ] Checking outputs.conf...

call :COMPARE_FILES "%OUTPUTS_CONFIG%" "%LOCAL_OUTPUTS%"

if "!COMPARE_RESULT!"=="CHANGED" (

    echo [ + ] outputs.conf has changed.
    echo [ + ] Updating outputs.conf...

    if not exist "%SPLUNK_HOME%\etc\system\local" (
        mkdir "%SPLUNK_HOME%\etc\system\local" >nul 2>&1
    )

    copy /Y "%OUTPUTS_CONFIG%" "%LOCAL_OUTPUTS%" >nul

    if errorlevel 1 (

        echo [ ! ] Failed to update outputs.conf.

    ) else (

        echo [ + ] outputs.conf updated successfully.
        set "SPLUNK_CONFIG_CHANGED=1"

    )

) else (

    echo [ + ] outputs.conf is already up to date.

)

echo.

REM =========================================================
REM SPLUNK SERVICE RESTART
REM =========================================================

if "!SPLUNK_CONFIG_CHANGED!"=="1" (

    echo [ + ] Splunk configuration changes detected.
    echo [ + ] Restarting Splunk Forwarder...

    net stop SplunkForwarder >nul 2>&1

    if errorlevel 1 (
        echo [ ! ] Failed to stop Splunk Forwarder service.
        echo [ + ] Attempting to force stop...
        taskkill /F /IM splunkd.exe >nul 2>&1
        timeout /t 3 /nobreak >nul
    ) else (
        echo [ + ] Splunk Forwarder stopped successfully.
        timeout /t 3 /nobreak >nul
    )

    net start SplunkForwarder >nul 2>&1

    if errorlevel 1 (

        echo [ ! ] Failed to start Splunk Forwarder.
        echo [ + ] Attempting to start via splunk.exe...
        pushd "%SPLUNK_HOME%\bin" 2>nul
        start "" splunk.exe start
        popd
        echo [ + ] Splunk started via splunk.exe.

    ) else (

        echo [ + ] Splunk Forwarder restarted successfully.

    )

) else (

    echo [ + ] No Splunk configuration changes detected.
    echo [ + ] Splunk Forwarder restart is not required.

)

echo.
echo ==========================================
echo [ + ] Installation/Update has been completed
echo ==========================================
echo.
echo Deployment Summary:
echo -------------------
echo Sysmon Status: Check logs above for details
echo Splunk Version: !MSI_VERSION!
echo.
echo Author : Shahpasandi
echo Web    : https://shahpasandi.github.io/
echo.

goto :END

REM =========================================================
REM SUBROUTINE: COMPARE TWO FILES USING SHA256 HASH
REM =========================================================

:COMPARE_FILES

set "COMPARE_RESULT=CHANGED"

set "SOURCE_FILE=%~1"
set "DEST_FILE=%~2"

if not exist "%SOURCE_FILE%" (
    echo [ ! ] Source file does not exist:
    echo     %SOURCE_FILE%
    exit /b 1
)

if not exist "%DEST_FILE%" (
    set "COMPARE_RESULT=CHANGED"
    exit /b 0
)

set "SOURCE_HASH="
set "DEST_HASH="

for /f "tokens=1" %%H in ('certutil -hashfile "%SOURCE_FILE%" SHA256 ^| findstr /R /V /C:"SHA256" /C:"CertUtil"') do (
    set "SOURCE_HASH=%%H"
    goto :SOURCE_HASH_DONE
)

:SOURCE_HASH_DONE

for /f "tokens=1" %%H in ('certutil -hashfile "%DEST_FILE%" SHA256 ^| findstr /R /V /C:"SHA256" /C:"CertUtil"') do (
    set "DEST_HASH=%%H"
    goto :DEST_HASH_DONE
)

:DEST_HASH_DONE

if /I "!SOURCE_HASH!"=="!DEST_HASH!" (
    set "COMPARE_RESULT=SAME"
) else (
    set "COMPARE_RESULT=CHANGED"
)

exit /b 0

REM =========================================================
REM SUBROUTINE: COMPARE SYSMON CONFIGURATION HASH
REM =========================================================

:COMPARE_SYSMON_HASH

set "COMPARE_RESULT=CHANGED"

if not exist "%SYSMON_CONFIG%" (
    exit /b 1
)

if not exist "%SYSMON_HASH_FILE%" (
    set "COMPARE_RESULT=CHANGED"
    exit /b 0
)

set "SOURCE_HASH="
set "STORED_HASH="

for /f "tokens=1" %%H in ('certutil -hashfile "%SYSMON_CONFIG%" SHA256 ^| findstr /R /V /C:"SHA256" /C:"CertUtil"') do (
    set "SOURCE_HASH=%%H"
    goto :SYSMON_SOURCE_HASH_DONE
)

:SYSMON_SOURCE_HASH_DONE

set /p STORED_HASH=<"%SYSMON_HASH_FILE%" 2>nul

if /I "!SOURCE_HASH!"=="!STORED_HASH!" (
    set "COMPARE_RESULT=SAME"
) else (
    set "COMPARE_RESULT=CHANGED"
)

exit /b 0

REM =========================================================
REM SUBROUTINE: STORE SYSMON CONFIGURATION HASH
REM =========================================================

:STORE_SYSMON_HASH

certutil -hashfile "%SYSMON_CONFIG%" SHA256 > "%TEMP%\sysmon_hash.tmp" 2>nul

for /f "tokens=1" %%H in ('findstr /R /V /C:"SHA256" /C:"CertUtil" "%TEMP%\sysmon_hash.tmp"') do (
    echo %%H > "%SYSMON_HASH_FILE%"
    goto :SYSMON_HASH_STORED
)

:SYSMON_HASH_STORED
del "%TEMP%\sysmon_hash.tmp" >nul 2>&1

exit /b 0

REM =========================================================
REM SUBROUTINE: STORE SPLUNK MSI HASH
REM =========================================================

:STORE_SPLUNK_MSI_HASH

certutil -hashfile "%SPLUNK_MSI%" SHA256 > "%TEMP%\splunk_msi_hash.tmp" 2>nul

for /f "tokens=1" %%H in ('findstr /R /V /C:"SHA256" /C:"CertUtil" "%TEMP%\splunk_msi_hash.tmp"') do (
    echo %%H > "%SPLUNK_MSI_HASH_FILE%"
    goto :SPLUNK_MSI_HASH_STORED
)

:SPLUNK_MSI_HASH_STORED
del "%TEMP%\splunk_msi_hash.tmp" >nul 2>&1

exit /b 0

REM =========================================================
REM END OF SCRIPT
REM =========================================================

:END

endlocal
exit /b