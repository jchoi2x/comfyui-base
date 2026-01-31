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

Edit `/workspace/comfyui_args.txt` (one arg per line):

```
--max-batch-size 8
--preview-method auto
```

## Directory Structure

- `/ComfyUI`: ComfyUI installation directory
- `/workspace/models`: Models directory (symlinked to `/ComfyUI/models`)
- `/workspace/user`: User configuration directory (symlinked to `/ComfyUI/user`)
- `/workspace/input`: Input directory (symlinked to `/ComfyUI/input`)
- `/workspace/output`: Output directory (symlinked to `/ComfyUI/output`)
- `/workspace/comfyui_args.txt`: ComfyUI arguments file
- `/workspace/filebrowser.db`: FileBrowser database

### Symbolic Links

The container automatically creates symbolic links to allow easy access to ComfyUI's models and configuration:

- Place your models in `/workspace/models/` and they will be available in ComfyUI
- Place your user configurations in `/workspace/user/` and they will be available in ComfyUI
- Input files go in `/workspace/input/`
- Output files are saved to `/workspace/output/`

This design allows you to mount `/workspace` as a volume to persist your data across container restarts.
