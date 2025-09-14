#!/bin/bash
set -e

trap 'rm -rf spiffs.bin spiffs_data' EXIT

# TOKEN=$1
TOKEN=admin
PORT=${PORT:-/dev/ttyUSB0}
URL=http://localhost:3000/api/admin/esp/create
FLASH_OFFSET=0x220000
LITTLEFS_SIZE=0x60000

if [ -z "$TOKEN" ]; then
  echo "Usage: $0 <token>"
  exit 1
fi

mkdir -p spiffs_data

echo "[1/4] Read MAC from esp at $PORT..."
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
echo "MAC: $MAC"

echo "[2/4] Registerig and files preparation..."
docker run --rm --network host \
  -v $(pwd)/spiffs_data:/app/spiffs_data \
  python-prepare-esp \
  --token "$TOKEN" --mac "$MAC" --api-url "$URL"


if [ ! -d "spiffs_data" ] || [ -z "$(ls -A spiffs_data 2>/dev/null)" ]; then
  echo "No SPIFFS data created! Check API connection and credentials."
  exit 1
fi

echo "[3/4] Running LittleFS image..."
docker run --rm \
    -v $(pwd)/spiffs_data:/data \
    -v $(pwd):/output \
    mklittlefs-img \
    -c /data -b 4096 -p 256 -s ${LITTLEFS_SIZE} /output/littlefs.bin

echo "[4/4] ESP32 flashing..."
docker run --rm --device=${PORT}:${PORT} -v $(pwd):/work espressif/idf:latest \
  esptool.py --chip esp32 --port ${PORT} --baud 460800 \
  write_flash --encrypt ${FLASH_OFFSET} /work/littlefs.bin

echo "Ready!!"