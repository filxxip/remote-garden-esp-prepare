import os
import binascii
import logging
import argparse
import shutil
import requests

DATA_DIR = "spiffs_data"
BIN_FILE = "spiffs.bin"
DEFAULT_CA_PATH = "/app/ca.crt"
DEFAULT_API_URL = "http://localhost:3000/api/admin/esp/create"

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def generate_secret():
    return binascii.hexlify(os.urandom(64)).decode()


def prepare_files(mac, secret, ca_path):
    os.makedirs(DATA_DIR, exist_ok=True)

    with open(os.path.join(DATA_DIR, "device_id.txt"), "w") as f:
        f.write(mac)
    with open(os.path.join(DATA_DIR, "device_secret.txt"), "w") as f:
        f.write(secret)

    if not os.path.isfile(ca_path):
        raise FileNotFoundError(f"No such file: {ca_path}")

    shutil.copy(ca_path, os.path.join(DATA_DIR, "ca.crt"))
    logger.info("Copied CA certificate to SPIFFS data directory.")


def register_device_remotely(mac: str, secret: str, api_url: str, token: str):
    payload = {"mac": mac, "secret": secret}
    headers = {"Authorization": f"Bearer {token}"}
    try:
        r = requests.post(api_url, json=payload, headers=headers, timeout=10)
        r.raise_for_status()
        logger.info("ESP device registered via API.")
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to register device: {e}")
        if hasattr(e, "response") and e.response is not None:
            logger.error(f"Response status: {e.response.status_code}")
            logger.error(f"Response body: {e.response.text}")
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ca", type=str, default=DEFAULT_CA_PATH)
    parser.add_argument("--api-url", type=str, default=DEFAULT_API_URL)
    parser.add_argument("--token", type=str, required=True)
    parser.add_argument("--mac", type=str, required=True)
    args = parser.parse_args()

    secret = generate_secret()
    logger.info(f"Generated device secret: {secret[:16]}...")

    prepare_files(args.mac, secret, args.ca)
    register_device_remotely(args.mac, secret, args.api_url, args.token)

    logger.info(
        "Provisioning complete (SPiFFS image still to be built & flashed).")


if __name__ == "__main__":
    main()
