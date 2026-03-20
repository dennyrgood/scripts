#!/bin/bash
launchctl setenv OLLAMA_HOST "0.0.0.0"
killall ollama 2>/dev/null
sleep 1

echo "Launch OLLAMA app"

OLLAMA_HOST=0.0.0.0 ollama serve 

echo "Kill this OLLAMA"
echo " "
echo "lsof -i -nP | grep ollama"

lsof -i -nP | grep ollama
