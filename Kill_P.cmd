@echo off
setlocal enabledelayedexpansion
title 文件解锁工具

:: 判断是否已经是管理员
net session >nul 2>&1
if %errorlevel% equ 0 goto :AdminMode

:: ==================== 非管理员模式: 接收拖放 ====================
:UserMode
cls
echo ============================================
echo          文件解锁工具
echo ============================================
echo.
echo 请把文件/文件夹拖到本窗口，然后按回车。
echo 也可以直接把文件/文件夹拖到本脚本图标上运行。
echo.

:: 如果有启动参数（拖到图标），直接使用第一个参数
set "TARGET="
if not "%~1"=="" (
    set "TARGET=%~1"
    echo [信息] 从启动参数获取: !TARGET!
    goto :ConfirmElevate
)

set /p "TARGET=路径: "
if not defined TARGET goto UserMode
set "TARGET=!TARGET:"=!"
if not exist "!TARGET!" (
    echo [错误] 路径不存在: !TARGET!
    pause
    goto UserMode
)

:ConfirmElevate
echo.
echo [信息] 目标: !TARGET!
echo [信息] 即将请求管理员权限，请在 UAC 弹窗中确认...

:: 保存路径到临时文件
set "ARGS_FILE=%temp%\unlock_args.txt"
> "!ARGS_FILE!" echo !TARGET!

:: 提权
set "VBS=%temp%\elev_%random%.vbs"
> "%VBS%" echo Set UAC = CreateObject^("Shell.Application"^)
>> "%VBS%" echo UAC.ShellExecute "%~f0", "elevated", "", "runas", 1
cscript //nologo "%VBS%"
if errorlevel 1 (
    echo [错误] 提权失败或被取消
    if exist "!ARGS_FILE!" del "!ARGS_FILE!" >nul 2>&1
    pause
    exit /b 1
)
del "%VBS%" >nul 2>&1
exit /b

:: ==================== 管理员模式 ====================
:AdminMode
if /i "%~1"=="elevated" shift

:: 读取之前保存的路径
set "TARGET="
set "ARGS_FILE=%temp%\unlock_args.txt"
if exist "!ARGS_FILE!" (
    set /p TARGET=<"!ARGS_FILE!"
    del "!ARGS_FILE!" >nul 2>&1
)

:: 检查 handle.exe
where handle.exe >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 handle.exe
    echo        请下载: https://learn.microsoft.com/sysinternals/downloads/handle
    echo        放到系统 PATH 或本脚本同目录
    pause
    exit /b 1
)
handle.exe /accepteula >nul 2>&1

:: 有保存的路径就处理
if defined TARGET (
    echo.
    echo [信息] 处理目标: !TARGET!
    set "FOUND=0"
    call :ProcessPath "!TARGET!"
    call :ShowResult
    echo.
    pause
    exit /b
)

:: 直接以管理员运行，无法拖放，只能手动输入
:AdminLoop
cls
echo ============================================
echo          文件解锁工具 - 管理员模式
echo ============================================
echo.
echo 注意: 管理员窗口无法接收拖放（Windows UIPI 安全限制）。
echo       请手动输入路径，或将文件/文件夹拖到脚本图标上运行。
echo.
set "TARGET="
set /p "TARGET=路径: "
if not defined TARGET goto AdminLoop
set "TARGET=!TARGET:"=!"
if not exist "!TARGET!" (
    echo [错误] 路径不存在: !TARGET!
    pause
    goto AdminLoop
)
set "FOUND=0"
call :ProcessPath "!TARGET!"
call :ShowResult
echo.
pause
goto AdminLoop

:: ==================== 子程序: 处理路径 ====================
:ProcessPath
set "T=%~1"
echo.
if exist "!T!\" (
    echo [信息] 类型: 文件夹 - !T!
    echo [信息] 步骤 1/3: 检查文件夹本身
    call :KillLocker "!T!"
    echo [信息] 步骤 2/3: 检查全部子文件
    for /r "!T!" %%F in (*) do call :KillLocker "%%F"
    echo [信息] 步骤 3/3: 检查全部子文件夹
    for /d /r "!T!" %%D in (*) do call :KillLocker "%%D"
) else (
    echo [信息] 类型: 文件 - !T!
    call :KillLocker "!T!"
)
exit /b

:: ==================== 子程序: 显示结果 ====================
:ShowResult
if "!FOUND!"=="0" (
    echo.
    echo [结果] 未检测到占用进程。
    echo        如果仍无法删除，可能原因:
    echo          1. 杀毒软件实时扫描
    echo          2. 缩略图缓存，可尝试重启 explorer.exe
    echo          3. 系统搜索索引服务
    echo          4. 需要重启电脑或进入安全模式
) else (
    echo.
    echo [结果] 已终止所有占用进程。
)
exit /b

:: ==================== 子程序: 终止锁定进程 ====================
:KillLocker
set "F=%~1"
if not exist "!F!" exit /b
set "TMP=%temp%\ho_%random%.txt"
set "DONE_PIDS=,"

handle.exe -nobanner -a "!F!" > "!TMP!" 2>&1
if errorlevel 1 (
    findstr /i /c:"No matching handles found" "!TMP!" >nul
    if errorlevel 1 (
        echo [警告] handle.exe 执行异常: !F!
        type "!TMP!"
    )
    del "!TMP!" >nul 2>&1
    exit /b
)

for /f "tokens=1,3" %%A in ('type "!TMP!" ^| findstr /i /r "pid:"') do (
    set "PR=%%A"
    set "PI=%%B"
    if /i not "!PR!"=="handle.exe" (
        echo !DONE_PIDS! | findstr /c:",!PI!," >nul
        if errorlevel 1 (
            set "DONE_PIDS=!DONE_PIDS!!PI!,"
            echo [发现] !PR! PID=!PI!  占用: !F!
            taskkill /f /pid !PI! >nul 2>&1
            if !errorlevel! equ 0 (
                echo [终止] !PR! PID=!PI!
            ) else (
                echo [失败] !PR! PID=!PI! 可能已退出或权限不足
            )
            set "FOUND=1"
        )
    )
)
del "!TMP!" >nul 2>&1
exit /b