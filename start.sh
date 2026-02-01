#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

COMFYUI_DIR="/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv"
FILEBROWSER_CONFIG="/root/.config/filebrowser/config.json"
DB_FILE="/workspace/runpod-slim/filebrowser.db"

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                  #
# ---------------------------------------------------------------------------- #

# Setup SSH with optional key or random password
setup_ssh() {
    mkdir -p ~/.ssh
    
    # Generate host keys if they don't exist
    for type in rsa dsa ecdsa ed25519; do
        if [ ! -f "/etc/ssh/ssh_host_${type}_key" ]; then
            ssh-keygen -t ${type} -f "/etc/ssh/ssh_host_${type}_key" -q -N ''
            echo "${type^^} key fingerprint:"
            ssh-keygen -lf "/etc/ssh/ssh_host_${type}_key.pub"
        fi
    done

    # If PUBLIC_KEY is provided, use it
    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        # Generate random password if no public key
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "Generated random SSH password for root: ${RANDOM_PASS}"
    fi

    # Configure SSH to preserve environment variables
    echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config

    # Start SSH service
    /usr/sbin/sshd
}

# Export environment variables
export_env_vars() {
    echo "Exporting environment variables..."
    
    # Create environment files
    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"
    
    # Backup original files
    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true
    
    # Clear files
    > "$ENV_FILE"
    > "$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    > "$SSH_ENV_DIR"
    
    # Export to multiple locations for maximum compatibility
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH' | while read -r line; do
        # Get variable name and value
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)
        
        # Add to /etc/environment (system-wide)
        echo "$name=\"$value\"" >> "$ENV_FILE"
        
        # Add to PAM environment
        echo "$name DEFAULT=\"$value\"" >> "$PAM_ENV_FILE"
        
        # Add to SSH environment file
        echo "$name=\"$value\"" >> "$SSH_ENV_DIR"
        
        # Add to current shell
        echo "export $name=\"$value\"" >> /etc/rp_environment
    done
    
    # Add sourcing to shell startup files
    echo 'source /etc/rp_environment' >> ~/.bashrc
    echo 'source /etc/rp_environment' >> /etc/bash.bashrc
    
    # Set permissions
    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

# Start Jupyter Lab server for remote access
start_jupyter() {
    mkdir -p /workspace
    echo "Starting Jupyter Lab on port 8888..."
    nohup jupyter lab \
        --allow-root \
        --no-browser \
        --port=8888 \
        --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --FileContentsManager.preferred_dir=/workspace \
        --ServerApp.root_dir=/workspace \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --IdentityProvider.token="${JUPYTER_PASSWORD:-}" \
        --ServerApp.allow_origin=* &> /jupyter.log &
    echo "Jupyter Lab started"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Setup environment
setup_ssh
export_env_vars

# Initialize FileBrowser if not already done
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing FileBrowser..."
    filebrowser config init
    filebrowser config set --address 0.0.0.0
    filebrowser config set --port 8080
    filebrowser config set --root /workspace
    filebrowser config set --auth.method=json
    filebrowser users add admin adminadmin12 --perm.admin
else
    echo "Using existing FileBrowser configuration..."
fi

# Start FileBrowser
echo "Starting FileBrowser on port 8080..."
nohup filebrowser &> /filebrowser.log &

start_jupyter

# Create default comfyui_args.txt if it doesn't exist
ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
if [ ! -f "$ARGS_FILE" ]; then
    echo "# Add your custom ComfyUI arguments here (one per line)" > "$ARGS_FILE"
    echo "Created empty ComfyUI arguments file at $ARGS_FILE"
fi

# Setup ComfyUI if needed
if [ ! -d "$COMFYUI_DIR" ] || [ ! -d "$VENV_DIR" ]; then
    echo "First time setup: Installing ComfyUI and dependencies..."
    
    # Clone ComfyUI if not present
    if [ ! -d "$COMFYUI_DIR" ]; then
        cd /
        git clone https://github.com/comfyanonymous/ComfyUI.git
    fi
    
    # Create symbolic links for models and user configuration folders
    echo "Setting up directories and symbolic links..."
    
    # Create workspace directories
    mkdir -p /workspace/runpod-slim/models
    mkdir -p /workspace/runpod-slim/user
    mkdir -p /workspace/runpod-slim/input
    mkdir -p /workspace/runpod-slim/output
    
    # Handle models directory - copy from network volume to container
    if [ -d "/workspace/runpod-slim/models" ] && [ "$(ls -A /workspace/runpod-slim/models 2>/dev/null)" ]; then
        echo "Copying models from /workspace/runpod-slim/models to /ComfyUI/models..."
        mkdir -p "$COMFYUI_DIR/models"
        rsync -av --ignore-existing /workspace/runpod-slim/models/ "$COMFYUI_DIR/models/" 2>/dev/null || \
        cp -rn /workspace/runpod-slim/models/* "$COMFYUI_DIR/models/" 2>/dev/null || true
    else
        mkdir -p "$COMFYUI_DIR/models"
    fi
    
    # Handle user directory - symlink from ComfyUI to network volume
    if [ ! -d "/workspace/runpod-slim/user" ] || [ -z "$(ls -A /workspace/runpod-slim/user 2>/dev/null)" ]; then
        # If network volume user directory is empty or doesn't exist, copy from ComfyUI
        if [ -d "$COMFYUI_DIR/user" ] && [ "$(ls -A "$COMFYUI_DIR/user" 2>/dev/null)" ]; then
            echo "Copying user config from /ComfyUI/user to /workspace/runpod-slim/user..."
            cp -r "$COMFYUI_DIR/user"/* "/workspace/runpod-slim/user/" 2>/dev/null || true
        fi
    fi
    
    # Remove existing user directory/symlink in ComfyUI and create symlink
    if [ -L "$COMFYUI_DIR/user" ]; then
        rm "$COMFYUI_DIR/user"
    elif [ -d "$COMFYUI_DIR/user" ]; then
        rm -rf "$COMFYUI_DIR/user"
    fi
    ln -sf "/workspace/runpod-slim/user" "$COMFYUI_DIR/user"
    
    # Handle input and output - create symlinks
    for dir in input output; do
        target_path="$COMFYUI_DIR/$dir"
        
        if [ -L "$target_path" ]; then
            rm "$target_path"
        elif [ -d "$target_path" ]; then
            # Migrate any existing data first
            if [ "$(ls -A "$target_path" 2>/dev/null)" ]; then
                echo "Migrating existing $dir directory to /workspace/runpod-slim/$dir..."
                cp -r "$target_path"/* "/workspace/runpod-slim/$dir/" 2>/dev/null || true
            fi
            rm -rf "$target_path"
        fi
        
        ln -sf "/workspace/runpod-slim/$dir" "$target_path"
    done
    
    echo "Directory setup complete:"
    echo "  $COMFYUI_DIR/models - copied from /workspace/runpod-slim/models"
    echo "  $COMFYUI_DIR/user -> /workspace/runpod-slim/user (symlink)"
    echo "  $COMFYUI_DIR/input -> /workspace/runpod-slim/input (symlink)"
    echo "  $COMFYUI_DIR/output -> /workspace/runpod-slim/output (symlink)"
    
    # Configure ComfyUI settings from environment variables
    echo "Configuring ComfyUI settings from environment variables..."
    mkdir -p "$COMFYUI_DIR/user/default"
    export SETTINGS_FILE="$COMFYUI_DIR/user/default/comfy.settings.json"
    
    python3.12 << 'PYTHON_EOF'
import json
import os

settings_file = os.environ.get('SETTINGS_FILE', '/ComfyUI/user/default/comfy.settings.json')

# Load existing settings or create new object
if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            settings = {}
else:
    settings = {}

# Track if any changes were made
changed = False

# Check and add CIVITAI_API_KEY
if 'CIVITAI_API_KEY' in os.environ and os.environ['CIVITAI_API_KEY']:
    settings['WorkflowModelsDownloader.CivitAIApiKey'] = os.environ['CIVITAI_API_KEY']
    print(f"Added CIVITAI_API_KEY to settings")
    changed = True

# Check and add HF_TOKEN
if 'HF_TOKEN' in os.environ and os.environ['HF_TOKEN']:
    settings['WorkflowModelsDownloader.HuggingFaceToken'] = os.environ['HF_TOKEN']
    settings['downloader.hf_token'] = os.environ['HF_TOKEN']
    print(f"Added HF_TOKEN to settings")
    changed = True

# Check and add TAVILY_API_TOKEN
if 'TAVILY_API_TOKEN' in os.environ and os.environ['TAVILY_API_TOKEN']:
    settings['WorkflowModelsDownloader.TavilyApiKey'] = os.environ['TAVILY_API_TOKEN']
    print(f"Added TAVILY_API_TOKEN to settings")
    changed = True

# Write settings file if any changes were made
if changed:
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
    print(f"Settings file updated: {settings_file}")
else:
    print("No API keys found in environment variables")
PYTHON_EOF
    
    # Install ComfyUI-Manager if not present
    if [ ! -d "$COMFYUI_DIR/custom_nodes/ComfyUI-Manager" ]; then
        echo "Installing ComfyUI-Manager..."
        mkdir -p "$COMFYUI_DIR/custom_nodes"
        cd "$COMFYUI_DIR/custom_nodes"
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    fi

    # Install additional custom nodes
    CUSTOM_NODES=(
        "https://github.com/kijai/ComfyUI-KJNodes"
        "https://github.com/MoonGoblinDev/Civicomfy"
        "https://github.com/MadiatorLabs/ComfyUI-RunpodDirect"
        "https://github.com/slahiri/ComfyUI-Workflow-Models-Downloader"
    )

    for repo in "${CUSTOM_NODES[@]}"; do
        repo_name=$(basename "$repo")
        if [ ! -d "$COMFYUI_DIR/custom_nodes/$repo_name" ]; then
            echo "Installing $repo_name..."
            cd "$COMFYUI_DIR/custom_nodes"
            git clone "$repo"
        fi
    done
    
    # Create and setup virtual environment if not present
    if [ ! -d "$VENV_DIR" ]; then
        cd $COMFYUI_DIR
        # Create venv with access to system packages (torch, numpy, etc. pre-installed in image)
        python3.12 -m venv --system-site-packages $VENV_DIR
        source $VENV_DIR/bin/activate

        # Ensure pip is available in the venv (needed for ComfyUI-Manager)
        python -m ensurepip --upgrade
        python -m pip install --upgrade pip

        echo "Base packages (torch, numpy, etc.) available from system site-packages"
        echo "Installing custom node dependencies..."

        # Install dependencies for all custom nodes
        cd "$COMFYUI_DIR/custom_nodes"
        for node_dir in */; do
            if [ -d "$node_dir" ]; then
                echo "Checking dependencies for $node_dir..."
                cd "$COMFYUI_DIR/custom_nodes/$node_dir"
                
                # Check for requirements.txt
                if [ -f "requirements.txt" ]; then
                    echo "Installing requirements.txt for $node_dir"
                    pip install --no-cache-dir -r requirements.txt
                fi

                # Check for install.py
                if [ -f "install.py" ]; then
                    echo "Running install.py for $node_dir"
                    python install.py
                fi

                # Check for setup.py
                if [ -f "setup.py" ]; then
                    echo "Running setup.py for $node_dir"
                    pip install --no-cache-dir -e .
                fi
            fi
        done
    fi
else
    # Just activate the existing venv
    source $VENV_DIR/bin/activate

    echo "Checking for custom node dependencies..."

    # Install dependencies for all custom nodes
    cd "$COMFYUI_DIR/custom_nodes"
    for node_dir in */; do
        if [ -d "$node_dir" ]; then
            echo "Checking dependencies for $node_dir..."
            cd "$COMFYUI_DIR/custom_nodes/$node_dir"
            
            # Check for requirements.txt
            if [ -f "requirements.txt" ]; then
                echo "Installing requirements.txt for $node_dir"
                uv pip install --no-cache -r requirements.txt
            fi
            
            # Check for install.py
            if [ -f "install.py" ]; then
                echo "Running install.py for $node_dir"
                python install.py
            fi
            
            # Check for setup.py
            if [ -f "setup.py" ]; then
                echo "Running setup.py for $node_dir"
                uv pip install --no-cache -e .
            fi
        fi
    done
fi

# Create a script to sync models back to network volume
cat > /usr/local/bin/sync-models-to-network.sh << 'EOF'
#!/bin/bash
# Sync models from container to network volume to persist downloads
rsync -av --ignore-existing /ComfyUI/models/ /workspace/runpod-slim/models/ 2>/dev/null || true
EOF
chmod +x /usr/local/bin/sync-models-to-network.sh

# Set up cron job to sync models every 5 minutes
echo "Setting up cronjob to sync models to network volume..."
(crontab -l 2>/dev/null || true; echo "*/5 * * * * /usr/local/bin/sync-models-to-network.sh") | crontab -

# Start cron service
service cron start 2>/dev/null || cron || true

echo "Model sync cronjob configured to run every 5 minutes"

# Start ComfyUI with custom arguments if provided
cd $COMFYUI_DIR
FIXED_ARGS="--listen 0.0.0.0 --port 8188"
if [ -s "$ARGS_FILE" ]; then
    # File exists and is not empty, combine fixed args with custom args
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')
    if [ ! -z "$CUSTOM_ARGS" ]; then
        echo "Starting ComfyUI with additional arguments: $CUSTOM_ARGS"
        nohup python main.py $FIXED_ARGS $CUSTOM_ARGS &> /workspace/runpod-slim/comfyui.log &
    else
        echo "Starting ComfyUI with default arguments"
        nohup python main.py $FIXED_ARGS &> /workspace/runpod-slim/comfyui.log &
    fi
else
    # File is empty, use only fixed args
    echo "Starting ComfyUI with default arguments"
    nohup python main.py $FIXED_ARGS &> /workspace/runpod-slim/comfyui.log &
fi

# Tail the log file
tail -f /workspace/runpod-slim/comfyui.log
