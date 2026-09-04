#!/bin/bash
if [ -z "$1" ]; then
  nginx -T 2>&1 | head -50
else
  nginx -T 2>&1 | grep -i "$1"
fi