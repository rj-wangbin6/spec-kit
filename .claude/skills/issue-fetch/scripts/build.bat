@echo off
REM Issue Fetch 查询工具 - Windows 编译脚本
REM 
REM 功能: 使用 MinGW gcc 编译 query_ci_review.c（依赖 Windows 原生 WinHTTP，无需 libcurl）
REM 使用: build.bat

echo ====================================
echo Issue Fetch 查询工具 - 编译脚本
echo ====================================
echo.

REM 检查源文件是否存在
if not exist "query_ci_review.c" (
    echo [错误] 找不到源文件 query_ci_review.c
    echo 请确保在正确的目录下运行此脚本
    pause
    exit /b 1
)

REM 尝试使用GCC编译（MinGW）—— 依赖 Windows 原生 WinHTTP，无需 libcurl
echo [1/2] 尝试使用 GCC 编译...
where gcc >nul 2>&1
if %errorlevel% == 0 (
    echo 找到 GCC 编译器
    echo 正在编译（WinHTTP 静态可用）...
    gcc -o query_ci_review.exe query_ci_review.c -lwinhttp -lws2_32 -O2
    if %errorlevel% == 0 (
        echo.
        echo ====================================
        echo [成功] 编译完成！
        echo ====================================
        echo 可执行文件: query_ci_review.exe
        echo 依赖: Windows 系统内置 winhttp.dll（无需额外安装）
        echo.
        echo 使用方法:
        echo   query_ci_review.exe ^<changeNumber^>
        echo   query_ci_review.exe --json ^<changeNumber^>
        echo.
        echo 示例:
        echo   query_ci_review.exe 778441
        echo   query_ci_review.exe --json 778441
        echo ====================================
        pause
        exit /b 0
    ) else (
        echo [失败] GCC 编译失败，请检查 gcc 是否正常安装
    )
)

REM 尝试使用MSVC编译（Visual Studio）
echo [2/2] 尝试使用 MSVC 编译...
where cl >nul 2>&1
if %errorlevel% == 0 (
    echo 找到 MSVC 编译器
    echo 正在编译...
    cl query_ci_review.c winhttp.lib ws2_32.lib /Fe:query_ci_review.exe
    if %errorlevel% == 0 (
        echo.
        echo ====================================
        echo [成功] 编译完成！
        echo ====================================
        echo 可执行文件: query_ci_review.exe
        echo ====================================
        pause
        exit /b 0
    ) else (
        echo [失败] MSVC编译失败
    )
)

REM 尝试使用Clang编译
echo [3/3] 尝试使用 Clang 编译...
where clang >nul 2>&1
if %errorlevel% == 0 (
    echo 找到 Clang 编译器
    echo 正在编译...
    clang -o query_ci_review.exe query_ci_review.c -lwinhttp -lws2_32 -O2
    if %errorlevel% == 0 (
        echo.
        echo ====================================
        echo [成功] 编译完成！
        echo ====================================
        echo 可执行文件: query_ci_review.exe
        echo ====================================
        pause
        exit /b 0
    ) else (
        echo [失败] Clang编译失败
    )
)

REM 所有编译器都失败
echo.
echo ====================================
echo [错误] 编译失败！
echo ====================================
echo.
echo 未找到可用的C编译器。请安装以下之一:
echo   1. MinGW-w64 (GCC)  推荐: https://www.msys2.org/
echo   2. Visual Studio (MSVC)
echo   3. LLVM (Clang)
echo.
echo 注意: 本工具依赖 Windows 系统内置的 WinHTTP，无需安装任何第三方库。
echo ====================================
pause
exit /b 1
