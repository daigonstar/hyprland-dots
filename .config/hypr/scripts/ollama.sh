#!/usr/bin/env bash
# This script ensures the gpt-oss:7b model is available in Ollama and starts the Ollama
# server in the background if it isn't already running.

MODEL="gpt-oss:7b"

# Pull the model if it hasn't been pulled yet.
if ! ollama show "$MODEL" > /dev/null 2>&1; then
  echo "Pulling model $MODEL..."
  ollama pull "$MODEL"
fi

# Start the Ollama server if it isn't already running.
if ! pgrep -f "ollama serve" > /dev/null; then
  echo "Starting Ollama server..."
  ollama serve > /dev/null 2>&1 &
  echo "Ollama server started in background."
else
  echo "Ollama server is already running."
fi
