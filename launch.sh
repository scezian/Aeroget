#!/bin/bash
# Launcher for AeroGet Desktop Application

cd "$(dirname "$0")" || exit
source .venv/bin/activate
python3 main.py
