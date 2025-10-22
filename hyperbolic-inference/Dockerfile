FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py .

EXPOSE 11434

CMD ["gunicorn", "--bind", "0.0.0.0:11434", "app:app"]
