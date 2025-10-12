#!/bin/bash
set -e

dockerd-entrypoint.sh &
sleep 10

echo "[0/5] Building needed images"
/app/deps/build.sh

trap 'rm -rf littlefs.bin spiffs_data' EXIT

TOKEN=${TOKEN:-token}
PORT=${PORT:-/dev/ttyUSB0}
URL=http://192.168.100.3:3000/api/admin/esp/create
FLASH_OFFSET=0x220000
LITTLEFS_SIZE=0x60000

FIRMWARE_DIR=/firmware
BOOTLOADER_BIN=${FIRMWARE_DIR}/bootloader.bin
BOOTLOADER_OFFSET=0x1000
PARTITIONS_BIN=${FIRMWARE_DIR}/partition-table.bin
PARTITIONS_OFFSET=0x8000
OTA_DATA_BIN=${FIRMWARE_DIR}/ota_data_initial.bin
OTA_DATA_OFFSET=0xd000
APP_BIN=${FIRMWARE_DIR}/esp32_dev_app.bin
APP_FLASH_OFFSET=0x10000

if [ ! -d "$FIRMWARE_DIR" ] || [ -z "$(ls -A $FIRMWARE_DIR 2>/dev/null)" ]; then
  echo "Firmware directory not found or empty!"
  echo "Mount your firmware directory with: -v /path/to/firmware:/firmware"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Usage: TOKEN=<your_token> $0"
  exit 1
fi

mkdir -p spiffs_data

echo "[1/5] Reading MAC from ESP at $PORT..."
MAC=$(docker run --rm --device=${PORT}:${PORT} espressif/idf:latest \
  esptool.py --chip esp32 --port ${PORT} read_mac 2>/dev/null \
  | grep "MAC:" \
  | awk '{print $2}' \
  | tr -d ':' \
  | head -n 1)

if [ -z "$MAC" ]; then
  echo "Cannot read MAC address"
  exit 1
fi
echo " MAC: $MAC"

echo "[2/5] Registering device and preparing files..."
docker run --rm --network host \
  -v $(pwd)/spiffs_data:/app/spiffs_data \
  python-prepare-esp \
  --token "$TOKEN" --mac "$MAC" --api-url "$URL"

if [ ! -d "spiffs_data" ] || [ -z "$(ls -A spiffs_data 2>/dev/null)" ]; then
  echo "No SPIFFS data created! Check API connection and credentials."
  exit 1
fi
echo " Device registered, config files ready"

echo "[3/5] Creating LittleFS image..."
docker run --rm \
    -v $(pwd)/spiffs_data:/data \
    -v $(pwd):/output \
    mklittlefs-img \
    -c /data -b 4096 -p 256 -s ${LITTLEFS_SIZE} /output/littlefs.bin

if [ ! -f "littlefs.bin" ]; then
  echo "Failed to create LittleFS image"
  exit 1
fi
echo " LittleFS image created ($(stat -f%z littlefs.bin 2>/dev/null || stat -c%s littlefs.bin) bytes)"

echo "[4/5] Erasing ESP32 flash..."
docker run --rm --device=${PORT}:${PORT} espressif/idf:latest \
  esptool.py --chip esp32 --port ${PORT} erase_flash
echo "Flash erased"

echo "[5/5] Flashing ESP32 with all components..."

echo "Checking firmware files..."
MISSING_FILES=0
for file in "$BOOTLOADER_BIN" "$PARTITIONS_BIN" "$OTA_DATA_BIN" "$APP_BIN"; do
  if [ ! -f "$file" ]; then
    echo "Missing: $(basename $file)"
    MISSING_FILES=$((MISSING_FILES + 1))
  else
    echo "Found: $(basename $file)"
  fi
done

if [ $MISSING_FILES -gt 0 ]; then
  echo "$MISSING_FILES firmware file(s) missing!"
  exit 1
fi

docker run --rm --device=${PORT}:${PORT} \
  -v ${FIRMWARE_DIR}:/firmware \
  -v $(pwd):/work \
  espressif/idf:latest \
  esptool.py --chip esp32 --port ${PORT} --baud 460800 write_flash \
    ${BOOTLOADER_OFFSET} /firmware/bootloader.bin \
    ${PARTITIONS_OFFSET} /firmware/partition-table.bin \
    ${OTA_DATA_OFFSET} /firmware/ota_data_initial.bin \
    ${APP_FLASH_OFFSET} /firmware/esp32_dev_app.bin \
    --encrypt ${FLASH_OFFSET} /work/littlefs.bin

echo ""
echo "=========================================="
echo "ESP32 FLASHED SUCCESSFULLY!"
echo "=========================================="
echo "Device MAC:    $MAC"
echo ""
echo "Flashed components:"
echo "   Bootloader       @ ${BOOTLOADER_OFFSET}"
echo "   Partition table  @ ${PARTITIONS_OFFSET}"
echo "   OTA data         @ ${OTA_DATA_OFFSET}"
echo "   Application      @ ${APP_FLASH_OFFSET}"
echo "   LittleFS (enc)   @ ${FLASH_OFFSET}"
echo "=========================================="
echo ""
echo "Device is ready to use!"
echo "=========================================="