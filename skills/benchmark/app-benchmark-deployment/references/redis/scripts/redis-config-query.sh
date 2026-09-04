#!/bin/bash
if [ -z "$1" ]; then
  redis-cli CONFIG GET * 2>/dev/null | paste - - | column -t
else
  redis-cli CONFIG GET "$1" 2>/dev/null | paste - - | column -t
fi