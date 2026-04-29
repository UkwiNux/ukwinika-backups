# Monsun Cron Jobs

This directory contains templated scripts for all system cron jobs used in a production Linux environment. They are designed to be deployed by `monsun_cron_backup.sh`.

## Structure

- Each job has its own subdirectory with `bin/` (executable) and `conf/` (configuration).
- Logs are written to `/var/log/monsun_cron/` on the target server.
- All scripts use `flock` to prevent overlapping runs.
- The `monsun_cron_backup.sh` installer pulls these templates and sets up crontab entries.

## Adding a new job

1. Create a new folder under the appropriate category.
2. Add `bin/<jobname>.sh` and `conf/<jobname>.conf` (copy from an existing job).
3. Update the `jobs` array in `monsun_cron_backup.sh`.
4. Commit and push.
