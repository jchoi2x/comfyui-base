[![Watch the video](https://i3.ytimg.com/vi/JovhfHhxqdM/hqdefault.jpg)](https://www.youtube.com/watch?v=JovhfHhxqdM)

Run the latest ComfyUI optimized for NVIDIA Blackwell architecture (RTX 5090, B200). First start installs dependencies (takes a few minutes), then when you see this in the logs, ComfyUI is ready to be used: `[ComfyUI-Manager] All startup tasks have been completed.`

## Access

- `8188`: ComfyUI web UI
- `8080`: FileBrowser (admin / adminadmin12)
- `8888`: JupyterLab (token via `JUPYTER_PASSWORD`, root at `/workspace`)
- `22`: SSH (set `PUBLIC_KEY` or check logs for generated root password)

## Pre-installed custom nodes

- ComfyUI-Manager
- ComfyUI-KJNodes
- Civicomfy
- ComfyUI-Workflow-Models-Downloader

## Source Code

This is an open source template. Source code available at: [github.com/runpod-workers/comfyui-base](https://github.com/runpod-workers/comfyui-base)

## Custom Arguments

Edit `/workspace/runpod-slim/comfyui_args.txt` (one arg per line):

```
--max-batch-size 8
--preview-method auto
```

## Directory Structure

- `/ComfyUI`: ComfyUI installation directory
- `/workspace/runpod-slim/models`: Models directory (symlinked from `/ComfyUI/models`)
- `/workspace/runpod-slim/user`: User configuration directory (symlinked from `/ComfyUI/user`)
- `/workspace/runpod-slim/input`: Input directory (symlinked from `/ComfyUI/input`)
- `/workspace/runpod-slim/output`: Output directory (symlinked from `/ComfyUI/output`)
- `/workspace/runpod-slim/comfyui_args.txt`: ComfyUI arguments file
- `/workspace/runpod-slim/filebrowser.db`: FileBrowser database

### Symbolic Links

The container automatically creates symbolic links to allow easy access to ComfyUI's models and configuration:

- Place your models in `/workspace/runpod-slim/models/` and they will be available in ComfyUI
- Place your user configurations in `/workspace/runpod-slim/user/` and they will be available in ComfyUI
- Input files go in `/workspace/runpod-slim/input/`
- Output files are saved to `/workspace/runpod-slim/output/`

This design allows you to mount `/workspace/runpod-slim` as a volume to persist your data across container restarts.
