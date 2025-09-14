FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    python3-venv \
    python3-dev \
    gcc \
    libusb-1.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY prepare_esp.py .
COPY ca.crt .

ENTRYPOINT ["python3", "prepare_esp.py"]
