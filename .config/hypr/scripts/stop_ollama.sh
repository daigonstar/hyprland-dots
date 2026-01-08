#!/usr/bin/env bash
# Attempts to stop Ollama. If permission is denied, tries sudo.

if pkill -f "ollama serve" 2>/dev/null; then
    echo "Ollama server stopped."
else
    echo "Permission denied – trying with sudo..."
    sudo pkill -f "ollama serve" && echo "Ollama server stopped with sudo."
fi
