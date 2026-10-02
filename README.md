# hiveos-docker

HiveOS client as a self-contained GPU container. Built for running HiveOS as a
RunPod pod on our own hardware: the container needs only the GPUs passed in
and the farm hash as an environment variable. No mounts, no host setup beyond
the NVIDIA driver and container toolkit.

Image: `ghcr.io/luis15pt/hiveos-docker:latest` (private; built by GitHub
Actions on every push to `main`).

> **Keep the built image private.** It contains closed-source HiveOS packages
> and scripts from an unofficial, unlicensed base image. This repo only holds
> our own scripts and a Dockerfile that pulls that base image at build time.

## Running it

### RunPod

Create a template with:

| Setting | Value |
|---|---|
| Container image | `ghcr.io/luis15pt/hiveos-docker:latest` |
| Registry credentials | GitHub username + a token with `read:packages` |
| Container start command | leave empty |
| Volume disk | 0 (nothing needs to persist) |
| Exposed ports | none needed |
| Environment variables | see below |

| Variable | |
|---|---|
| `HIVE_TOKEN` | Farm hash (dashboard: *Farm → Settings*). Best stored as a RunPod secret: `{{ RUNPOD_SECRET_hive_farm_hash }}` |
| `HIVE_WORKER` | Optional worker name. Default: the RunPod pod ID |
| `HIVE_ID`, `HIVE_PASS` | Optional: connect to an existing worker (*Farm → Add worker*) instead of joining by farm hash |

The same template works on any machine. With a farm hash, each pod joins the
farm as a worker identified by the **GPUs it was given**: the first start
creates the worker, and a pod that comes back with the same GPUs (restart,
redeploy) reconnects to the same worker. A different set of GPUs is a
different worker. Assign the flight sheet in the HiveOS dashboard as usual.

### Plain Docker

```bash
cp .env.example .env   # fill in HIVE_TOKEN (or HIVE_ID + HIVE_PASS)
docker run -d --name hiveos --restart unless-stopped --gpus all \
  --env-file .env --log-opt max-size=10m --log-opt max-file=3 \
  ghcr.io/luis15pt/hiveos-docker:latest
docker logs -f hiveos
```

`--gpus '"device=1,2"'` gives the container only some GPUs; HiveOS will see
just those.

## What works

- Rig login, flight sheets and miners (tested: SRBMiner on 5× RTX 5090)
- GPU names, core temperature, fan %, power draw, load, memory, power limits
  and VBIOS in the dashboard
- `docker logs` shows startup, then streams the active miner's log (switches
  automatically when the flight sheet changes)
- Containers given a subset of the host's GPUs (e.g. a RunPod pod with 1 of 5)

## What doesn't (and why)

| Feature | Why |
|---|---|
| Overclocking, fan control, power limits from the dashboard | NVIDIA's driver only accepts settings changes from real root with `CAP_SYS_ADMIN`. A normal container doesn't have that, and we don't want the HiveOS agent (which takes remote commands) to have it. Set power limits on the host if needed: `sudo nvidia-smi -i 0 -pl 450`. |
| VRAM / memory temperature | NVIDIA's driver (NVML, DCGM, nvidia-smi) reports it only on datacenter GPUs; on GeForce it's `N/A`. Tools that show it read GPU registers through `/dev/mem`, which would mean a privileged container. |
| HiveOS OS upgrades from the dashboard | The base image's startup scripts are written for HiveOS 0.6-225. Don't click *Upgrade*. |

The startup log still shows a few harmless lines: `ERROR: NVIDIA OC failed`,
`X server failed to run` and two `grep` lines about missing systemd network
files.

## How it works

The image is `hanaik/hiveos` (pinned by digest) plus the changes in
`Dockerfile`:

| Change | Why |
|---|---|
| Blank `HIVE_ID`/`HIVE_PASS`/`HIVE_WORKER`/`HIVE_TOKEN` defaults | The base image ships its author's rig credentials. Without this, any variable left unset connects our GPUs to **their** farm. |
| Skip `install_nvidia_driver` in `/etc/start.sh` | The base image downloads and installs an NVIDIA userspace driver on every start. The container toolkit already provides the host's driver libraries. |
| `POWER_MAX=1500` in `/hive/bin/sanitize` | HiveOS 0.6-225 reports any GPU drawing over 500 W as 0 W. Backported from HiveOS 0.6-231. |
| Install `iproute2`, `usbutils`, `cron`, `kbd`, `dmidecode` | Tools HiveOS scripts call that the base image lacks. |
| Mask `RIG_PASSWD` in the startup config dump and hello response | Keeps the rig password out of `docker logs`. |
| Rig `uid` from GPU UUIDs when DMI is unreadable (`/hive/bin/hello`) | HiveOS identifies a rig by a hash of the DMI system UUID, CPU ID and first MAC. In a container the first two are unreadable and the MAC is random, so every new container joined the farm as a new worker. Hashing the UUIDs of the GPUs passed in makes the same GPUs come back as the same worker. |
| Default `HIVE_WORKER` to `$RUNPOD_POD_ID`, else the hostname | Names new workers when joining by farm hash. |
| `start.sh` runs `miner-logs` instead of sleeping forever | Miner output in `docker logs`. |

And the scripts in `rootfs/`:

| File | Purpose |
|---|---|
| `hive/sbin/nvtool` | Replaces HiveOS's `nvtool`, which refuses to run outside genuine HiveOS ("intended for use only as a part of HIVEOS"), so every GPU showed as MALFUNCTION. Answers the same queries from `nvidia-smi` in nvtool's output format (fields in flag order, `;`-separated). Settings changes exit 3 (not supported), which HiveOS treats as non-fatal. |
| `usr/local/sbin/lspci` | HiveOS finds GPUs with `lspci`, which lists every GPU on the host. This hides NVIDIA GPUs that weren't passed to the container (`nvidia-smi` can't see them), and adds GPUs that `nvidia-smi` sees but the PCI bus doesn't (WSL2). |
| `usr/local/sbin/lsmod` | HiveOS skips NVIDIA queries unless an `nvidia` kernel module is listed. WSL2 has none; this reports it when `nvidia-smi` works. No effect on native Linux. |
| `usr/local/sbin/quiet-wrapper` | Linked as `systemctl`, `timedatectl`, `modprobe`, `dmidecode`, etc. Runs the real tool but drops the errors it always prints in a container (no systemd, D-Bus, `/dev/mem`, console or kernel modules). Exit codes and other output are unchanged. |
| `usr/local/bin/miner-logs` | Follows `/var/log/miner/<miner>/<miner>.log` for the flight sheet's `MINER`/`MINER2`, re-checking every 10 s. |

## Base image notes

`hanaik/hiveos@sha256:db72f63e…` was reviewed before use: it is Ubuntu 20 with
the official HiveOS 0.6-225 client packages from `download.hiveos.farm`, a
modified boot script (`hive_fr`) and an entrypoint that writes `rig.conf` from
the `HIVE_*` variables on every start. Bumping the digest means reviewing the
new image again, especially its default `ENV` values.
