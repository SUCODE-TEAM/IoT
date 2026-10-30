/*
  Program Monitoring Kualitas Air: Sensor TDS & pH Meter (ESP32)
  Dengan Fitur Auto-Detect Pin TDS (D2 / D34 / D14) & Sensor pH
*/

#include <Arduino.h>

#define VREF 3.3         // Tegangan referensi ADC ESP32
#define SCOUNT 30        // Jumlah sampel untuk filter median

// Daftar pin TDS yang dipindai otomatis (D2, D34, D14, D32)
const int tdsProbePins[] = {2, 34, 14, 32};
const int numTdsPins = sizeof(tdsProbePins) / sizeof(tdsProbePins[0]);
int activeTdsPin = 2;    // Default ke GPIO 2 (D2)

// Pin Sensor pH (default ke GPIO 35 / D35)
#define PH_PIN 35

// Konfigurasi Kalibrasi pH-4502C
// Berdasarkan data tegangan nyata probe kamu:
// Saat air pH 4.0 (asam)  : tegangan terbaca ~2.40 V
// Saat air pH 9.0 (basa)  : tegangan terbaca ~1.58 V
// Slope = (9.0 - 4.0) / (1.58 - 2.40) = -6.10
// Tegangan netral pH 7.0  : ~1.91 V
#define PH_OFFSET 0.00   
#define PH_NEUTRAL_VOLT 1.91 // Tegangan saat pH 7.0 (netral, terkalibrasi)
#define PH_SLOPE -6.10       // Slope terkalibrasi (2.40V->pH4, 1.58V->pH9)

int tdsBuffer[SCOUNT];
int tdsBufferIndex = 0;

int phBuffer[SCOUNT];
int phBufferIndex = 0;

float tdsVoltage = 0.0;
float tdsValue = 0.0;
float phVoltage = 0.0;
float phValue = 0.0;
float temperature = 25.0; // Suhu default cairan (25 °C)

int getMedianNum(int bArray[], int iFilterLen);

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Set ADC 11dB (0 - 3.3V)
  analogSetAttenuation(ADC_11db);

  for (int i = 0; i < SCOUNT; i++) {
    tdsBuffer[i] = 0;
    phBuffer[i] = 0;
  }

  Serial.println("\n========================================================");
  Serial.println("  SISTEM MONITORING KUALITAS AIR (TDS & pH METER) ESP32 ");
  Serial.println("========================================================");
  Serial.println("Status Sensor : Auto-Detect Pin TDS + pH Meter (D35)");
  Serial.println("Baud Rate     : 115200 (Interval Update: 1 Detik)");
  Serial.println("========================================================\n");
}

void loop() {
  // 1. Auto-Detect pin TDS: cari pin yang memiliki sinyal tegangan aktif
  int bestTdsPin = activeTdsPin;
  int maxRead = 0;
  for (int i = 0; i < numTdsPins; i++) {
    int val = analogRead(tdsProbePins[i]);
    if (val > maxRead) {
      maxRead = val;
      bestTdsPin = tdsProbePins[i];
    }
  }
  // Jika ditemukan sinyal aktif (> 50 ADC), gunakan pin tersebut
  if (maxRead > 50) {
    activeTdsPin = bestTdsPin;
  }

  // 2. Ambil sampel analog TDS & pH setiap 30 ms
  static unsigned long sampleTimer = 0;
  if (millis() - sampleTimer >= 30) {
    sampleTimer = millis();

    tdsBuffer[tdsBufferIndex] = analogRead(activeTdsPin);
    tdsBufferIndex = (tdsBufferIndex + 1) % SCOUNT;

    phBuffer[phBufferIndex] = analogRead(PH_PIN);
    phBufferIndex = (phBufferIndex + 1) % SCOUNT;
  }

  // 3. Update dan cetak hasil setiap 2 detik (2000 ms)
  static unsigned long printTimer = 0;
  if (millis() - printTimer >= 2000) {
    printTimer = millis();

    // ----------------- PROSES SENSOR TDS -----------------
    int tempTds[SCOUNT];
    for (int i = 0; i < SCOUNT; i++) tempTds[i] = tdsBuffer[i];
    int medianTdsRaw = getMedianNum(tempTds, SCOUNT);

    if (medianTdsRaw < 30) {
      tdsVoltage = 0.0;
      tdsValue = 0.0;
    } else {
      tdsVoltage = (float)medianTdsRaw * (VREF / 4095.0);
      float compCoeff = 1.0 + 0.02 * (temperature - 25.0);
      float compVolt = tdsVoltage / compCoeff;

      if (compVolt > 0.015) {
        tdsValue = (133.42 * compVolt * compVolt * compVolt 
                    - 255.86 * compVolt * compVolt 
                    + 857.39 * compVolt) * 0.5;
        if (tdsValue < 0) tdsValue = 0;
      } else {
        tdsValue = 0;
      }
    }

    // ----------------- PROSES SENSOR pH ------------------
    int tempPh[SCOUNT];
    for (int i = 0; i < SCOUNT; i++) tempPh[i] = phBuffer[i];
    int medianPhRaw = getMedianNum(tempPh, SCOUNT);

    phVoltage = (float)medianPhRaw * (VREF / 4095.0);

    if (phVoltage <= 0.05) {
      phValue = 0.0; // Probe belum terhubung
    } else {
      // Rumus kalibrasi presisi:
      // Pada 2.10 V -> pH = 7.0 + (2.10 - 2.50) * 7.50 = 7.0 - 3.0 = 4.00 (ASAM)
      // Pada 2.50 V -> pH = 7.0 + (2.50 - 2.50) * 7.50 = 7.0 + 0.0 = 7.00 (NETRAL)
      phValue = 7.0 + ((phVoltage - PH_NEUTRAL_VOLT) * PH_SLOPE) + PH_OFFSET;
      if (phValue < 0.0) phValue = 0.0;
      if (phValue > 14.0) phValue = 14.0;
    }

    // ----------------- TAMPILAN SERIAL -------------------
    Serial.print("[TDS (D");
    Serial.print(activeTdsPin);
    Serial.print(")] ADC: ");
    Serial.print(medianTdsRaw);
    Serial.print(" | Volt: ");
    Serial.print(tdsVoltage, 2);
    Serial.print(" V | Nilai: ");
    Serial.print(tdsValue, 0);
    Serial.print(" ppm");

    Serial.print("  ||  [pH (D35)] ADC: ");
    Serial.print(medianPhRaw);
    Serial.print(" | Volt: ");
    Serial.print(phVoltage, 2);
    Serial.print(" V | pH: ");
    Serial.print(phValue, 2);

    if (phVoltage <= 0.05) {
      Serial.println("  [pH Blm Terpasang]");
    } else if (phValue < 6.5) {
      Serial.println("  [Asam]");
    } else if (phValue <= 7.5) {
      Serial.println("  [Netral]");
    } else {
      Serial.println("  [Basa]");
    }
  }

  delay(10);
}

// Fungsi pendukung Median Filter
int getMedianNum(int bArray[], int iFilterLen) {
  int bTab[30];
  int len = (iFilterLen > 30) ? 30 : iFilterLen;
  for (byte i = 0; i < len; i++) {
    bTab[i] = bArray[i];
  }
  int i, j, bTemp;
  for (j = 0; j < len - 1; j++) {
    for (i = 0; i < len - j - 1; i++) {
      if (bTab[i] > bTab[i + 1]) {
        bTemp = bTab[i];
        bTab[i] = bTab[i + 1];
        bTab[i + 1] = bTemp;
      }
    }
  }
  int bMedian;
  if ((len & 1) > 0) {
    bMedian = bTab[(len - 1) / 2];
  } else {
    bMedian = (bTab[len / 2] + bTab[len / 2 - 1]) / 2;
  }
  return bMedian;
}
