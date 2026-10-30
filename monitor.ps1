param (
    [string]$PortName = "",
    [int]$BaudRate = 115200
)

# 1. Otomatis deteksi Port jika tidak ditentukan
if (-not $PortName) {
    $detected = Get-CimInstance Win32_SerialPort | Where-Object { 
        $_.Description -match "CP210|CH340|CH341|USB to UART|FTDI" 
    } | Select-Object -First 1

    if ($detected) {
        $PortName = $detected.DeviceID
    } else {
        $PortName = "COM4"
    }
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         MONITOR SERIAL SENSOR TDS (ESP32 - $PortName)       " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Tekan Ctrl + C untuk keluar dari monitor." -ForegroundColor DarkGray
Write-Host ""

# 2. Otomatis bebaskan COM port jika sedang dikunci serial-monitor Arduino IDE
$lockedProcesses = Get-Process -Name "serial-monitor" -ErrorAction SilentlyContinue
if ($lockedProcesses) {
    Write-Host "[INFO] Menutup Serial Monitor Arduino IDE yang mengunci $PortName..." -ForegroundColor Yellow
    $lockedProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}

$port = New-Object System.IO.Ports.SerialPort $PortName, $BaudRate
$port.ReadTimeout = 2000
$port.DtrEnable = $false
$port.RtsEnable = $false

try {
    $port.Open()
    Write-Host "[OK] Berhasil terhubung ke $PortName ($BaudRate baud)." -ForegroundColor Green
    Write-Host "Menunggu data dari sensor..." -ForegroundColor DarkYellow
    Write-Host "(Catatan: Jika data belum muncul, tekan tombol [EN] / [RST] di board ESP32 Anda sekali)" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

    while ($true) {
        try {
            $line = $port.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $timestamp = Get-Date -Format "HH:mm:ss"
                
                # Format warna sesuai kondisi air
                if ($line -match "Air Murni|Air Minum|Baik|Normal") {
                    Write-Host "[$timestamp] $line" -ForegroundColor Green
                } elseif ($line -match "Pekat|Nutrisi|Terkontaminasi") {
                    Write-Host "[$timestamp] $line" -ForegroundColor Yellow
                } elseif ($line -match "Kering|Udara") {
                    Write-Host "[$timestamp] $line" -ForegroundColor Cyan
                } else {
                    Write-Host "[$timestamp] $line" -ForegroundColor White
                }
            }
        } catch [System.TimeoutException] {
            # Timeout normal jika sensor belum kirim baris baru
        }
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] Gagal membuka port $PortName." -ForegroundColor Red
    Write-Host "Detail Error: $_" -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "Tips Solusi:" -ForegroundColor Yellow
    Write-Host "1. Pastikan tab 'Serial Monitor' di aplikasi Arduino IDE telah DITUTUP." -ForegroundColor White
    Write-Host "2. Cabut lalu pasang kembali kabel USB ESP32 ke komputer." -ForegroundColor White
} finally {
    if ($port -and $port.IsOpen) {
        $port.Close()
    }
    Write-Host "`n[INFO] Port $PortName telah ditutup." -ForegroundColor Cyan
}
