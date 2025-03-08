@echo off
powershell.exe -ExecutionPolicy Bypass -Command "& {.\TailorResume.ps1 -JobDescriptionPath JD.txt -DeleteTEXFile:$true}"
pause