#!/bin/bash
set -e


if [ ! -S /var/run/docker.sock ]; then
    echo "Docker socket not found, starting dockerd..."
    dockerd-entrypoint.sh &
    sleep 10
else
    echo "Using Docker from host via mounted socket"
fi

echo "[0/5] Building needed images"
/app/deps/build.sh

trap 'rm -rf littlefs.bin spiffs_data' EXIT

TOKEN=${TOKEN:-token}
PORT=${PORT:-/dev/ttyUSB0}
URL=${URL:-https://localhost/api/v1/admin/esp/create}
FLASH_OFFSET=0x220000
LITTLEFS_SIZE=0x60000

FIRMWARE_DIR=/firmware
BOOTLOADER_BIN=${FIRMWARE_DIR}/bootloader.bin
BOOTLOADER_OFFSET=0x0

PARTITIONS_BIN=${FIRMWARE_DIR}/partition-table.bin
PARTITIONS_OFFSET=0x8000

OTA_DATA_BIN=${FIRMWARE_DIR}/ota_data_initial.bin
OTA_DATA_OFFSET=0x18000

APP_BIN=${FIRMWARE_DIR}/esp32_dev_app.bin
APP_FLASH_OFFSET=0x20000

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
  esptool.py --chip esp32s3 --port ${PORT} read_mac 2>/dev/null \
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

docker volume create spiffs-temp

docker run --rm --network host \
  -v spiffs-temp:/app/spiffs_data \
  python-prepare-esp \
  --token "$TOKEN" --mac "$MAC" --api-url "$URL"

CONTAINER_ID=$(docker create -v spiffs-temp:/data alpine true)
mkdir -p spiffs_data
docker cp ${CONTAINER_ID}:/data/. spiffs_data/
docker rm ${CONTAINER_ID}

# Usuń tymczasowy volume
docker volume rm spiffs-temp

echo "DEBUG: Files after copy:"
ls -la spiffs_data/

if [ ! -d "spiffs_data" ] || [ -z "$(ls -A spiffs_data 2>/dev/null)" ]; then
  echo "No SPIFFS data created! Check API connection and credentials."
  exit 1
fi
echo " Device registered, config files ready"
echo "[3/5] Creating LittleFS image..."
echo "DEBUG: Contents of spiffs_data:"
ls -la spiffs_data/

docker volume create littlefs-input
docker volume create littlefs-output

CONTAINER_ID=$(docker create -v littlefs-input:/data alpine true)
docker cp spiffs_data/. ${CONTAINER_ID}:/data/
docker rm ${CONTAINER_ID}

docker run --rm \
    -v littlefs-input:/data \
    -v littlefs-output:/output \
    mklittlefs-img \
    -c /data -b 4096 -p 256 -s ${LITTLEFS_SIZE} /output/littlefs.bin

EXIT_CODE=$?
echo "DEBUG: mklittlefs exit code: $EXIT_CODE"

CONTAINER_ID=$(docker create -v littlefs-output:/output alpine true)
docker cp ${CONTAINER_ID}:/output/littlefs.bin . || echo "Failed to copy littlefs.bin"
docker rm ${CONTAINER_ID}

docker volume rm littlefs-input littlefs-output

if [ ! -f "littlefs.bin" ]; then
  echo "Failed to create LittleFS image"
  exit 1
fi

SIZE=$(ls -lh littlefs.bin | awk '{print $5}')
echo " LittleFS image created ($SIZE)"

echo "[4/5] Erasing ESP32 flash..."
echo "[4/5] Erasing ESP32 flash..."
docker run --rm --device=${PORT}:${PORT} espressif/idf:latest \
  esptool.py --chip esp32s3 --port ${PORT} erase_flash

# add --force if needed during encryption

echo "Flash erased"


echo "[5/5] Flashing ESP32 with all components..."
echo "Checking firmware files..."
MISSING_FILES=0
for file in "$BOOTLOADER_BIN" "$PARTITIONS_BIN" "$OTA_DATA_BIN" "$APP_BIN"; do
  if [ ! -f "$file" ]; then
    echo "Missing: $(basename $file)"
    MISSING_FILES=$((MISSING_FILES + 1))
  else
    SIZE=$(ls -lh "$file" | awk '{print $5}')
    SIZE_BYTES=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    echo "Found: $(basename $file) - $SIZE ($SIZE_BYTES bytes)"
  fi
done

if [ $MISSING_FILES -gt 0 ]; then
  echo "$MISSING_FILES firmware file(s) missing!"
  exit 1
fi

docker volume create flash-files

CONTAINER_ID=$(docker create -v flash-files:/flash alpine true)
docker cp ${BOOTLOADER_BIN} ${CONTAINER_ID}:/flash/bootloader.bin
docker cp ${PARTITIONS_BIN} ${CONTAINER_ID}:/flash/partition-table.bin
docker cp ${OTA_DATA_BIN} ${CONTAINER_ID}:/flash/ota_data_initial.bin
docker cp ${APP_BIN} ${CONTAINER_ID}:/flash/esp32_dev_app.bin
docker cp littlefs.bin ${CONTAINER_ID}:/flash/littlefs.bin
docker rm ${CONTAINER_ID}

echo "Files prepared in volume, starting flash process..."


# To enable encryption:

# docker run --rm --device=${PORT}:${PORT} \
#   -v flash-files:/flash \
#   espressif/idf:latest \
#   esptool.py --chip esp32s3 --port ${PORT} --baud 460800 \
#     --before default-reset --after hard-reset \
#     write_flash --encrypt --flash-mode dio --flash-freq 40m --flash-size detect \
#     0x1000 /flash/bootloader.bin \
#     0x8000 /flash/partition-table.bin \
#     0x18000 /flash/ota_data_initial.bin \
#     0x20000 /flash/esp32_dev_app.bin \
#     0x220000 /flash/littlefs.bin

docker run --rm --device=${PORT}:${PORT} \
  -v flash-files:/flash \
  espressif/idf:latest \
  esptool.py --chip esp32s3 --port ${PORT} --baud 460800 \
    --before default-reset --after hard-reset \
    write_flash --flash-mode dio --flash-freq 40m --flash-size detect \
    0x0 /flash/bootloader.bin \
    0x8000 /flash/partition-table.bin \
    0x18000 /flash/ota_data_initial.bin \
    0x20000 /flash/esp32_dev_app.bin \
    0x220000 /flash/littlefs.bin

# Cleanup
docker volume rm flash-files

echo ""
echo "=========================================="
echo "ESP32 FLASHED SUCCESSFULLY!"
echo "=========================================="
echo "Device MAC:    $MAC"
echo ""
echo "Flashed components:"
echo "   Bootloader       @ 0x1000"
echo "   Partition table  @ 0x8000"
echo "   OTA data         @ 0x18000"
echo "   Application      @ 0x20000 (factory)"
echo "   LittleFS (enc)   @ 0x220000"
echo "=========================================="
echo ""
echo "Device is ready to use!"
echo "=========================================="