param (
    [string]$Port = "",
    [string]$Fqbn = "esp32:esp32:esp32doit-devkit-v1"
)

# 1. Otomatis deteksi Port
if (-not $Port) {
    $detected = Get-CimInstance Win32_SerialPort | Where-Object { 
        $_.Description -match "CP210|CH340|CH341|USB to UART|FTDI" 
    } | Select-Object -First 1

    if ($detected) {
        $Port = $detected.DeviceID
    } else {
        $Port = "COM4"
    }
}

$cliPath = "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
if (-not (Test-Path $cliPath)) {
    Write-Host "[ERROR] arduino-cli.exe tidak ditemukan di $cliPath" -ForegroundColor Red
    exit 1
}

$sketchPath = "$PSScriptRoot\kode"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "            UPLOAD PROGRAM SENSOR TDS KE ESP32            " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Port Target : $Port" -ForegroundColor White
Write-Host "Board FQBN  : $Fqbn" -ForegroundColor White
Write-Host "Sketch      : $sketchPath\kode.ino" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Otomatis bebaskan COM port jika sedang dikunci serial-monitor Arduino IDE
$lockedProcesses = Get-Process -Name "serial-monitor" -ErrorAction SilentlyContinue
if ($lockedProcesses) {
    Write-Host "[INFO] Menutup Serial Monitor yang mengunci $Port..." -ForegroundColor Yellow
    $lockedProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}

# 3. Kompilasi Sketch
Write-Host "[1/2] Mengompilasi kode program..." -ForegroundColor Yellow
& $cliPath compile --fqbn $Fqbn $sketchPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Kompilasi gagal! Silakan periksa kembali kode Anda." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[OK] Kompilasi berhasil!" -ForegroundColor Green
Write-Host ""

# 4. Upload ke Board
Write-Host "[2/2] Memulai proses upload ke $Port..." -ForegroundColor Yellow
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "PENTING UNTUK ESP32:" -ForegroundColor Magenta
Write-Host "Jika muncul titik-titik 'Connecting........____........'" -ForegroundColor Magenta
Write-Host "Segera TEKAN dan TAHAN tombol [BOOT] pada board ESP32 Anda" -ForegroundColor Yellow
Write-Host "hingga muncul tulisan 'Writing at 0x...'" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

& $cliPath upload -p $Port --fqbn $Fqbn $sketchPath
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Upload gagal." -ForegroundColor Red
    Write-Host "Tips jika gagal 'Connecting........':" -ForegroundColor Yellow
    Write-Host "1. Tekan dan tahan tombol BOOT di board ESP32 tepat saat upload dimulai." -ForegroundColor White
    Write-Host "2. Pastikan Serial Monitor di Arduino IDE atau terminal lain sudah ditutup." -ForegroundColor White
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "[SUKSES] Program TDS berhasil diupload ke ESP32!" -ForegroundColor Green
Write-Host "Membuka Serial Monitor..." -ForegroundColor Cyan
Start-Sleep -Seconds 1

& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\monitor.ps1" -PortName $Port
