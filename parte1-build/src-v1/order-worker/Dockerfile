FROM python:3.12-slim
RUN useradd -m app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER app
ENV PYTHONUNBUFFERED=1 SERVICE_NAME=order-worker
CMD ["python", "worker.py"]
