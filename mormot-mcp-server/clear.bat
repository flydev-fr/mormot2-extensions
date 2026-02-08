@echo off
for /d /r %%f in (__history;__recovery;build;builds;*.log) do rmdir /s/q %%f
for /r %%f in (*.dcu;*.drc;*.map;*.o;*.log;*.rsm;*.identcache;*.local;*.local;*.ithelper) do del /f/q %%f
