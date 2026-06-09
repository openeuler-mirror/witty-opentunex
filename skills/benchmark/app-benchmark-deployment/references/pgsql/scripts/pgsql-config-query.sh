#!/bin/bash
if [ -z "$1" ]; then
  su - postgres -c "psql -c 'SHOW ALL'" 2>/dev/null | column -t
else
  su - postgres -c "psql -c 'SHOW $1'" 2>/dev/null | column -t
fi