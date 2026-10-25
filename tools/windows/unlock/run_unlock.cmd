@echo off
rem Runs ON THE PHONE. Writes the Spec A unlock images; each write is read back and compared by disktool.
rem On any failure, writes every original region back. Never reboots.
set D=C:\Data\Users\Public\Downloads
set T=%D%\disktool.exe
set L=C:\Data\unlock_log.txt
echo start > %L%
%T% write 0 36864 %D%\new_SBL2.bin >> %L% || goto fail
%T% write 0 40960 %D%\new_SBL3.bin >> %L% || goto fail
%T% write 0 35767 %D%\new_HACK.bin >> %L% || goto fail
%T% write 0 77824 %D%\new_UEFI.bin >> %L% || goto fail
%T% write 0 0 %D%\new_GPT.bin >> %L% || goto fail
echo ALL_OK >> %L%
goto end
:fail
echo FAILED_RESTORING >> %L%
%T% write 0 0 %D%\org_GPT.bin >> %L%
%T% write 0 77824 %D%\org_UEFI.bin >> %L%
%T% write 0 35767 %D%\org_HACK.bin >> %L%
%T% write 0 40960 %D%\org_SBL3.bin >> %L%
%T% write 0 36864 %D%\org_SBL2.bin >> %L%
echo RESTORED >> %L%
:end
type %L%
