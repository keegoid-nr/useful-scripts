# New Relic Synthetics Job Manager (SJM) Cron Job Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

The cron jobs scripts help to ensure the SJM container runs reliability and gets regular updates.

## Scripts

- **`sjm_cron_job.sh`**: For environments using Docker.
- **`sjm_cron_job_podman.sh`**: For environments using Podman.

## Prerequisites

- **Container Runtime**: You must have either [Docker](https://www.docker.com/) or [Podman](https://podman.io/) installed and running on the host.
- **Private Location Key**: You must have your New Relic Synthetics Private Location key. This is a secret key used to authenticate the SJM with your New Relic account.

## Usage

1. **Set the `PRIVATE_LOCATION_KEY` Environment Variable**

    You must set the `PRIVATE_LOCATION_KEY` environment variable on the host. This is typically done in your shell's profile file (e.g., `~/.bash_profile`, `~/.zshrc`, etc.) or in the crontab itself.

    ```bash
    export PRIVATE_LOCATION_KEY=YOUR_PRIVATE_LOCATION_KEY
    ```

2. **Schedule the Script with Cron**

   Add the appropriate script to your crontab to run at a regular interval. For example, to run the script every Sunday at 2 AM, you would add the following line to your crontab (edited with `crontab -e`):

   ```crontab
   0 2 * * 0 /path/to/sjm_cron_job.sh
   ```

   |      Field       | Value |                    Meaning                    |
   |:----------------:|:-----:|:---------------------------------------------:|
   |    **Minute**    |  `0`  |   At the beginning of the hour (minute 0).    |
   |     **Hour**     |  `2`  |                   At 2 AM.                    |
   | **Day of Month** |  `*`  |            Every day of the month.            |
   |    **Month**     |  `*`  |                 Every month.                  |
   | **Day of Week**  |  `0`  | Sunday (where 0 and 7 both represent Sunday). |

   *(Note: Ensure the script is executable (`chmod +x <script_name>`))*

## How It Works

The scripts perform the following actions in a sequence designed to keep the Synthetics Job Manager (SJM) and its related containers running and up-to-date:

1. **Check for a Running Container**: It first checks if a container named `synthetics-job-manager` is currently running.

2. **Restart and Cleanup**: The script initiates a cleanup and restart process:

    a.  **Stop All Containers**: It stops all currently running containers on the host. This is a critical step because the Synthetics Job Manager only checks for and pulls updated Synthetics runtime images on its own startup. Stopping all containers ensures a clean slate.

    b.  **System Prune**: It runs a `system prune -af` command. This forcefully removes all stopped containers, unused networks, and dangling images. This helps to keep the container runtime environment clean and frees up disk space.

    c.  **Start SJM Container**: A new `synthetics-job-manager` container is started using the `latest` image tag.

This entire process, when run on a regular cron schedule, provides several benefits:

- **High Availability**: Ensures the SJM is always running and available to execute synthetic monitors.
- **Automatic Updates**: By pruning the system and re-pulling the `latest` image, the script ensures that both the Synthetics Job Manager and the Synthetics runtimes are kept up-to-date automatically.
- **Clean Environment**: Regularly prunes the system to prevent the accumulation of old containers, networks, and images, which helps to maintain the health of the host.
- **Docker Root Cleanup**: You may also consider cleaning the whole Docker root from time to time, especially if disk space is getting low. This script will not handle that aside from what is cleaned with the prune command.

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](/LICENSE) file for details.
