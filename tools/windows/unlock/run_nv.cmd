@echo off
rem Runs ON THE PHONE. Writes the Secure-Boot-disabled NV image into the free gap, then the GPT that
rem points UEFI_BS_NV at it. On failure, writes the current (stage-1) GPT back. Never reboots.
set D=C:\Data\Users\Public\Downloads
set T=%D%\disktool.exe
set L=C:\Data\nv_log.txt
echo start > %L%
%T% write 0 98816 %D%\SBA_NV.bin >> %L% || goto fail
%T% write 0 0 %D%\GPT_NV.bin >> %L% || goto fail
echo ALL_OK >> %L%
goto end
:fail
echo FAILED_RESTORING >> %L%
%T% write 0 0 %D%\new_GPT.bin >> %L%
echo RESTORED >> %L%
:end
type %L%
