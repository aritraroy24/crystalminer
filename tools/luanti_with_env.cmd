@echo off
rem Starts Luanti (Windows) with the variables of a .env file, so an API key for the tutor, such as DEEPSEEK_API_KEY=..., stays in that file instead of in Luanti's settings. It reads .env in the game folder, then in the folder above it. Set LUANTI to the path of luanti.exe if it is not on the PATH. Arguments are passed on to Luanti.
setlocal
set "GAME=%~dp0.."
for %%F in ("%GAME%\.env" "%GAME%\..\.env") do (
	if exist "%%~F" (
		for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%%~F") do set "%%A=%%~B"
	)
)
if not defined LUANTI for /f "delims=" %%L in ('where luanti 2^>nul') do if not defined LUANTI set "LUANTI=%%L"
rem Installed with "winget install LuantiTeam.Luanti": the zip is unpacked under WinGet\Packages.
if not defined LUANTI for /d %%P in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\LuantiTeam.Luanti_*") do (
	for /d %%V in ("%%~P\luanti-*") do if exist "%%~V\bin\luanti.exe" set "LUANTI=%%~V\bin\luanti.exe"
)
if not defined LUANTI (
	echo Luanti was not found. Set LUANTI to the path of luanti.exe.
	exit /b 1
)
start "" "%LUANTI%" %*
