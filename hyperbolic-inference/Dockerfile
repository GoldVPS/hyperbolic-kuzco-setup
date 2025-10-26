# simple, small Python image
FROM python:3.9-slim

# set workdir
WORKDIR /app

# system deps (git/curl if needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# copy
COPY . /app

# install python deps
RUN pip install --no-cache-dir -r requirements.txt

# expose API port
EXPOSE 11434

# run with gunicorn (1 worker, threads)
CMD ["gunicorn", "-w", "1", "-k", "gthread", "--threads", "8", "-b", "0.0.0.0:11434", "--keep-alive", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
