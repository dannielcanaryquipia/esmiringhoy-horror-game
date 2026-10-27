@echo off
setlocal
rem Records the Esmiringhoy trailer with Godot Movie Maker.
set "GODOT=C:\Users\Danniel Canary\Downloads\Godot files\Godot_v4.7-stable_win64.exe"
set "PROJ=%~dp0"
if not exist "%PROJ%trailer_out" mkdir "%PROJ%trailer_out"
if not exist "%PROJ%trailer_out\.gdignore" type nul > "%PROJ%trailer_out\.gdignore"
echo Importing the project...
"%GODOT%" --headless --path "%PROJ%." --import
echo Recording the trailer at 1920x1080, 30 fps. Do not touch the game window.
"%GODOT%" --path "%PROJ%." --write-movie "%PROJ%trailer_out\esmiringhoy_trailer.ogv" --fixed-fps 30 --resolution 1920x1080 res://trailer/trailer.tscn
echo.
echo Done: trailer_out\esmiringhoy_trailer.ogv
