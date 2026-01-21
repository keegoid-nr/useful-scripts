# Podman Dependency Verifier

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

This script verifies if your environment is correctly set up to run the New Relic Synthetics Job Manager using Podman in rootless mode.

## How to use this script

### 1. Create the file (if not pulling from repo)

```bash
vi verify_podman_setup.sh
```

Paste the code into the file and save it (`Esc` -> `:wq`).

### 2. Make it executable

```bash
chmod +x verify_podman_setup.sh
```

### 3. Run the script

```bash
./verify_podman_setup.sh
```

## What this script does

* **Version Check**: It logically compares the installed version against 5.0.0 to ensure you meet the minimum requirement.
* **Deep Content Inspection**: It uses grep to look inside `containers.conf`, `delegate.conf`, and `podman-api.service` to ensure the specific configurations (crun, systemd, Delegate=yes, port 8000) are actually there.
* **Functional API Test**: Under step 8, it actually tries to curl the Podman API. If the service is running but firewalled or misconfigured, this step will catch it.
* **Networking Check**: Step 9 check for `slirp4netns`, which is the required networking mode for this setup.
* **Host IP Identification**: Step 10 identifies the machine's actual LAN IP (e.g., 192.168.1.50).
* **Connectivity Test**: It explicitly tries `curl http://<REAL_IP>:8000/_ping`.
  * **If this fails**: The script tells you immediately. This saves you from creating the container, waiting for it to start, and debugging cryptic logs. Usually, this fails because of a local firewall (like firewalld on RHEL) blocking port 8000 on the public interface, even if it's open on localhost.
* **Auto-Generated Command**: If everything passes, it prints the `podman pod create` command with the `--add-host` flag already filled in with the correct IP found in Step 10.
