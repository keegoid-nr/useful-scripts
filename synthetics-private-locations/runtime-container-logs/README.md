# Watch and Copy Docker Container Logs

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

## Overview

`watch-and-copy.sh` is a bash script that monitors New Relic Synthetics runtime containers and automatically captures their input/output files before the containers are removed. This is particularly useful for debugging short-lived containers that are launched with the `--rm` flag, which automatically removes them after execution.

## Problem Statement

New Relic Synthetics runtime containers often execute very quickly and are removed immediately after completion. This makes it difficult to inspect their input configurations and output logs for debugging purposes. This script solves this problem by:

- Monitoring Docker events for new runtime containers
- Polling the containers for file changes while they're running
- Copying input and output directories before the container is removed
- Archiving captured files for later analysis

## Features

- **Real-time monitoring**: Listens for Docker container start events
- **Rapid polling**: Checks for file changes every 0.1 seconds to catch short-lived containers
- **Immediate capture**: Attempts to copy files as soon as the container starts
- **Size-based tracking**: Only copies when directory sizes increase to avoid redundant operations
- **Automatic archiving**: Compresses captured files into `.tar.gz` archives
- **Cleanup**: Removes empty capture directories when no files were found
- **Configurable**: Accepts command-line parameters for customization
- **Concurrent support**: Handles multiple simultaneous container starts without missing any

## Requirements

- **Docker**: Must be installed and running
- **Bash**: Shell environment
- **Permissions**: User must have access to run Docker commands

## Installation

1. Download the script:

```bash
cd /path/to/your/scripts
chmod +x watch-and-copy.sh
```

1. Ensure Docker is running:

```bash
docker ps
```

## Usage

### Basic Usage

Run the script with default settings:

```bash
./watch-and-copy.sh
```

This will monitor the default image `newrelic/synthetics-node-browser-runtime` and save captured files to `./captured_outputs`.

### Advanced Usage

Customize the script with command-line options:

```bash
./watch-and-copy.sh -i <image_name> -d <destination_path> -t <check_interval>
```

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-i` | Docker image to monitor (name or `name:tag`) | `newrelic/synthetics-node-browser-runtime` |
| `-d` | Destination base directory for captured files | `./captured_outputs` |
| `-t` | Seconds to wait for file stability (currently unused in polling) | `1` |
| `-h` | Show help message and exit | - |

### Examples

**Monitor a different runtime image:**

```bash
./watch-and-copy.sh -i newrelic/synthetics-chrome-browser-runtime:latest
```

**Save to a custom directory:**

```bash
./watch-and-copy.sh -d /tmp/runtime-logs
```

**Full customization:**

```bash
./watch-and-copy.sh -i newrelic/synthetics-node-browser-runtime -d ~/debugging/logs -t 2
```

## How It Works

1. **Event Monitoring**: The script uses `docker events` to listen for container start events matching the specified image. It handles full image names, tags, and registry prefixes.

2. **Runtime Resolution**: The script automatically extracts the base runtime name from the image and maps keywords to canonical runtimes for internal path resolution:
    - Images containing **"api"** map to `/app/synthetics-node-api-runtime/...`
    - Images containing **"browser"** map to `/app/synthetics-node-browser-runtime/...`
    - This allows using shorthand image names like `node-api-runtime` or `node-browser-runtime`.

3. **Background Processing**: When a container starts, a background job is spawned to monitor it independently, allowing the script to handle multiple containers simultaneously

4. **Immediate Capture**: The script attempts an initial copy after a 0.05 second delay to catch files written at container startup

5. **Polling Loop**: While the container is running, the script polls every 0.1 seconds to detect file size increases

6. **Incremental Copying**: Files are copied only when directory sizes increase, avoiding redundant operations

7. **Final Attempt**: After the container stops, the script makes one last attempt to copy any files that were written just before shutdown

8. **Archiving**: If files were captured, they're compressed into a `.tar.gz` archive and the uncompressed directory is removed

## Output Structure

Captured files are organized by run ID in the following structure:

```sh
captured_outputs/
├── 20251219_160154_2a83cf.tar.gz
├── 20251219_160302_5b94de.tar.gz
└── ...
```

Each archive contains:

```sh
20251219_160154_2a83cf/
├── input/
│   └── (input files from container)
└── output/
    └── (output files from container)
```

The run ID format is: `YYYYMMDD_HHMMSS_<container_id_prefix>`

## Limitations

- **Race condition with --rm**: If a container exits extremely quickly, the `--rm` flag might remove it before the final copy attempt succeeds
- **Resource usage**: Polling every 0.1 seconds can consume CPU resources when many containers are running
- **No retroactive capture**: The script cannot capture files from containers that started before the script was launched

## Troubleshooting

### No files are being captured

- Verify the container is creating files at the expected paths
- Check that the script has permission to execute Docker commands
- Ensure the image name matches exactly (use `docker images` to verify)
- If using a custom image, ensure the internal path structure matches `/app/<runtime-name>/...`

### Script exits with "docker: command not found"

- Install Docker or ensure it's in your system PATH
- Verify Docker daemon is running: `docker ps`

### Archives are empty or missing

- The script only creates archives when files are actually captured
- Empty directories (no files) are automatically cleaned up
- Check the script output for error messages during copy operations

### Multiple containers cause missed captures

- The script runs each container monitor in a background job to handle concurrency
- If you're still missing captures, the containers may be exiting too quickly even for the 0.05s initial delay

## Development Notes

This script was developed through iterative debugging to handle increasingly edge cases:

- **Version 1**: Basic polling with standard intervals
- **Version 2**: Added immediate capture attempt for short-lived containers
- **Version 3**: Implemented size-based change detection
- **Version 4**: Added archiving and cleanup
- **Current**: Optimized polling interval and initial capture timing

## Contributing

When modifying this script, consider:

- Testing with containers of varying lifespans (milliseconds to minutes)
- Validating behavior with multiple simultaneous container starts
- Ensuring cleanup of empty directories to avoid clutter
- Maintaining backward compatibility with the command-line interface

## License

This script is part of the useful-scripts repository. Please refer to the repository's license for terms of use.

## Author

Created for debugging New Relic Synthetics runtime containers.

## See Also

- [Docker Events Documentation](https://docs.docker.com/engine/reference/commandline/events/)
- [New Relic Synthetics Documentation](https://docs.newrelic.com/docs/synthetics/)
