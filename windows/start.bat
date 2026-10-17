@echo off
cd /d %~dp0
.venv\Scripts\python receiver.py %*
rem ค้างหน้าต่างไว้ให้อ่านเฉพาะตอน error (ถูกตัวใหม่สั่งปิด = จบปกติ หน้าต่างปิดเอง)
if errorlevel 1 pause
