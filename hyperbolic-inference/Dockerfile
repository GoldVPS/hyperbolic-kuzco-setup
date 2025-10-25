FROM python:3.9-slim

# Lebih cepat & kecil
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# System deps minimal (curl cuma buat healthcheck opsional)
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Install python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app.py .

EXPOSE 11434

# Jalankan via gunicorn (sesuai compose)
CMD ["gunicorn", \
     "-w","1", \
     "-k","gthread","--threads","8", \
     "-b","0.0.0.0:11434", \
     "--keep-alive","30", \
     "--access-logfile","-","--error-logfile","-", \
     "app:app"]
