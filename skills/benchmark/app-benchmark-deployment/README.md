# app-benchmark-deployment

Deploy applications and benchmarks on target Linux machines via SSH.

## Supported Applications

- **MySQL** with sysbench
- **PostgreSQL** with pgbench
- **Redis** with redis-benchmark

## Usage

```bash
opencode run "Deploy `<app name>` benchmark on <TARGET_IP>"
```

## Output Location

```
/opt/opentunex/applications/<app_name>/
├── scripts/
│   ├── start.sh
│   ├── stop.sh
│   ├── status.sh
│   ├── config-query.sh
│   ├── config-set.sh
│   ├── benchmark-prepare.sh
│   ├── benchmark-run.sh
│   ├── benchmark-cleanup.sh
│   └── benchmark-status.sh
├── configs/
│   └── backup_variables.txt
└── logs/
```

## Quick Commands

```bash
# Start/Stop
/opt/opentunex/applications/`<app name>`/scripts/start.sh
/opt/opentunex/applications/`<app name>`/scripts/stop.sh

# Config
/opt/opentunex/applications/`<app name>`/scripts/config-query.sh `<param name>`
/opt/opentunex/applications/`<app name>`/scripts/config-set.sh `<param name>` `<param value>`

# Benchmark
/opt/opentunex/applications/`<app name>`/scripts/benchmark-prepare.sh `<prepare options>`
/opt/opentunex/applications/`<app name>`/scripts/benchmark-run.sh `<benchmark options>`
```

## Credentials

| Application | Username | Password |
|-------------|----------|----------|
| MySQL | root | 123456 |
| PostgreSQL | postgres | 123456 |
| Redis | - | - |

## Features

1. Auto-detection: Skips if app already deployed
2. Password handling: Prompts user (max 3 attempts)
3. Proxy support: Loads from ~/.bashrc
4. Config backup: Backs up before modification
5. Rollback: Restores original config after test

## Known Issues

- None currently
