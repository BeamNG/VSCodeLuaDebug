:: run this file as administrator to create a folder link in the VSCode extension folder

mklink /j %USERPROFILE%\.vscode\extensions\BeamNG.lua-debug-0.1.1 %~dp0

:: the copy version of it:
::copy /y *.* %USERPROFILE%\.vscode\extensions\BeamNG.lua-debug-0.1.0
@pause