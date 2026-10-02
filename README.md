# hiveos-docker

Run HiveOS in a Docker container. All it needs is the GPUs and your farm hash.
Built for RunPod.

Image: `ghcr.io/luis15pt/hiveos-docker:latest`

## RunPod

Create a template:

- **Image:** `ghcr.io/luis15pt/hiveos-docker:latest`
- **Environment variable:** `HIVE_TOKEN` = your farm hash (HiveOS: *Farm → Settings*)
- Everything else: leave empty or 0

Deploy a pod, then set a flight sheet for the new worker in HiveOS.

Each set of GPUs becomes one worker, named after the pod. A pod that comes
back with the same GPUs reconnects to the same worker.

## Docker

```bash
docker run -d --name hiveos --restart unless-stopped --gpus all \
  -e HIVE_TOKEN=<farm hash> ghcr.io/luis15pt/hiveos-docker:latest
docker logs -f hiveos
```

## Options

| Variable | |
|---|---|
| `HIVE_TOKEN` | Farm hash |
| `HIVE_WORKER` | Worker name (default: pod ID or hostname) |
| `HIVE_ID` + `HIVE_PASS` | Use an existing worker instead of the farm hash |

## Limitations

- No overclocking or fan control. Leave OC empty in HiveOS.
- No VRAM temperature (NVIDIA doesn't expose it on GeForce cards).
- Don't use *Upgrade* in the HiveOS dashboard.

## How it works

Built on [`hanaik/hiveos`](https://hub.docker.com/r/hanaik/hiveos), with fixes
so it runs properly in a container. See the comments in `Dockerfile` and the
scripts in `rootfs/` for details.
