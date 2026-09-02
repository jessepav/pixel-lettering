@echo off
rem no cd: a definition file path resolves against the caller's cwd, and
rem everything named inside it against the definition file's own directory

setlocal
for %%I in ("%~dp0..") do set "PROJDIR=%%~fI"

rem Lua 5.3 consults the versioned names before the plain ones, so set both.
rem Prepend rather than replace, or an existing luarocks tree stops resolving.
if defined LUA_PATH_5_3 (
    set "LUA_PATH_5_3=%PROJDIR%\src\?.lua;%LUA_PATH_5_3%"
) else if defined LUA_PATH (
    set "LUA_PATH_5_3=%PROJDIR%\src\?.lua;%LUA_PATH%"
) else (
    set "LUA_PATH_5_3=%PROJDIR%\src\?.lua;;"
)

if defined LUA_CPATH_5_3 (
    set "LUA_CPATH_5_3=%PROJDIR%\build\?.dll;%PROJDIR%\build\Release\?.dll;%LUA_CPATH_5_3%"
) else if defined LUA_CPATH (
    set "LUA_CPATH_5_3=%PROJDIR%\build\?.dll;%PROJDIR%\build\Release\?.dll;%LUA_CPATH%"
) else (
    set "LUA_CPATH_5_3=%PROJDIR%\build\?.dll;%PROJDIR%\build\Release\?.dll;;"
)
set "LUA_PATH=%LUA_PATH_5_3%"
set "LUA_CPATH=%LUA_CPATH_5_3%"

rem LUA_INIT is an interactive convenience. A batch tool should not pick up
rem the user's repl helpers, and should not die when they fail to load.
set "LUA_INIT="
set "LUA_INIT_5_3="

rem The interpreter must be the one in windows-libs: wrap_stb_image.dll
rem imports from that same lua.dll, and a differently-linked lua.exe off PATH
rem would leave the process with a second Lua state. Bail rather than fall back.
set "LUA_EXE=%PROJDIR%\windows-libs\tools\lua\lua.exe"
if not exist "%LUA_EXE%" (
    >&2 echo pixel-lettering: no Lua interpreter at "%LUA_EXE%"
    >&2 echo pixel-lettering: populate windows-libs -- see README.md
    exit /b 1
)

"%LUA_EXE%" "%PROJDIR%\src\lettering.lua" %*
exit /b %ERRORLEVEL%
