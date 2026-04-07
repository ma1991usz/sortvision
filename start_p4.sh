#!/bin/bash
cd ~/sortvision-router
export SV_WORKER_WORKER_NAME=tesla_p4
export SV_WORKER_REDIS_URL=redis://127.0.0.1:6379/0
export SV_WORKER_OLLAMA_URL=http://192.168.25.37:11434
export SV_WORKER_OLLAMA_MODEL=glm-ocr:latest
export SV_WORKER_QUEUES='["queue:tesla_p4"]'
exec ~/sortvision-router/venv/bin/python -m worker.main