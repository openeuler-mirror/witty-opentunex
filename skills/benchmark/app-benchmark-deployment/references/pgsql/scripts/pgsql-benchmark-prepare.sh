#!/bin/bash
SCALE=${1:-10}
su - postgres -c "pgbench -i -s $SCALE pgbench" 2>&1