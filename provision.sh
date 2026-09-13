#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Rob's disposable RunPod MiniMax H3 ComfyUI provisioning
# ============================================================
#
# Designed for:
#   AI-Dock ComfyUI
#   RunPod
#   NO Network Volume
#   Disposable container disk
#
# Everything is downloaded again on a new Pod.
#
# ============================================================

COMFY_DIR="${COMFY_DIR:-/opt/ComfyUI}"
COMFY_PYTHON="${COMFY_PYTHON:-/opt/environments/python/comfyui/bin/python}"

MODELS="${COMFY_DIR}/models"
CUSTOM="${COMFY_DIR}/custom_nodes"
WORKFLOWS="${COMFY_DIR}/user/default/workflows"

export HF_HUB_ENABLE_HF_TRANSFER=1

echo
echo "============================================================"
echo " MiniMax H3 RunPod Provisioning"
echo "============================================================"
echo "ComfyUI:  ${COMFY_DIR}"
echo "Python:   ${COMFY_PYTHON}"
echo "============================================================"
echo

# ------------------------------------------------------------
# Stop ComfyUI while we modify the installation.
# ------------------------------------------------------------

echo "==> ComfyUI is left running during provisioning"


# ------------------------------------------------------------
# Verify ComfyUI exists.
# ------------------------------------------------------------

if [[ ! -d "${COMFY_DIR}/.git" ]]; then
    echo "ERROR: ${COMFY_DIR} is not a Git repository."
    exit 1
fi

if [[ ! -x "${COMFY_PYTHON}" ]]; then
    echo "ERROR: ComfyUI Python was not found:"
    echo "       ${COMFY_PYTHON}"
    exit 1
fi

# ------------------------------------------------------------
# Create model directories.
# ------------------------------------------------------------

echo "==> Creating ComfyUI directories"

mkdir -p \
    "${MODELS}/diffusion_models" \
    "${MODELS}/text_encoders" \
    "${MODELS}/vae" \
    "${MODELS}/loras/MiniMax H3" \
    "${MODELS}/loras/MiniMax H3/xxx" \
    "${MODELS}/checkpoints" \
    "${MODELS}/frame_interpolation" \
    "${MODELS}/vae_approx" \
    "${WORKFLOWS}"

# ------------------------------------------------------------
# Update ComfyUI itself.
#
# The stock AI-Dock image contained an old ComfyUI revision.
# The MiniMax H3 nodes require newer ComfyUI APIs.
# ------------------------------------------------------------

echo
echo "==> Updating ComfyUI"

cd "${COMFY_DIR}"

git fetch --all --prune

if git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "  Updating from origin/master"
    git reset --hard origin/master
elif git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "  Updating from origin/main"
    git reset --hard origin/main
else
    echo "ERROR: Could not find ComfyUI master/main branch."
    exit 1
fi

echo "  ComfyUI revision:"
git rev-parse --short HEAD

echo
echo "==> Installing current ComfyUI requirements"
"${COMFY_PYTHON}" -m pip install --upgrade pip

echo
echo "==> Upgrading PyTorch for current ComfyUI"
"${COMFY_PYTHON}" -m pip install --upgrade \
    torch torchvision torchaudio

echo
echo "==> Installing current ComfyUI requirements"
"${COMFY_PYTHON}" -m pip install \
    -r "${COMFY_DIR}/requirements.txt"

# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------

echo
echo "==> Installing required custom nodes"

declare -A REPOS=(
    ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
    ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
    ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
    ["ComfyUI-PlagueKind-Nodes"]="https://github.com/PlagueKind/ComfyUI-PlagueKind-Nodes.git"
    ["ComfyUI-H3-Motion-Context-MultiRef"]="https://github.com/seitanism/ComfyUI-H3-Motion-Context-MultiRef.git"
    ["ComfyUI-Workflow-Encrypt"]="https://github.com/jtydhr88/ComfyUI-Workflow-Encrypt.git"
    ["ComfyUI_Workflow_Timer"]="https://github.com/mike420/ComfyUI_Workflow_Timer.git"
)

for name in "${!REPOS[@]}"; do

    dir="${CUSTOM}/${name}"

    if [[ ! -d "${dir}/.git" ]]; then
        echo
        echo "  ==> Cloning ${name}"
        git clone --depth 1 "${REPOS[$name]}" "${dir}"
    else
        echo
        echo "  ==> Updating ${name}"
        git -C "${dir}" pull --ff-only || true
    fi

    if [[ -f "${dir}/requirements.txt" ]]; then
        echo "  ==> Installing requirements for ${name}"

        "${COMFY_PYTHON}" -m pip install \
            -r "${dir}/requirements.txt" || {

            echo
            echo "WARNING: requirements failed for ${name}"
            echo "         Continuing with remaining nodes."
        }
    fi

done

# ------------------------------------------------------------
# Create an isolated Hugging Face environment.
#
# IMPORTANT:
# Do NOT install huggingface_hub into ComfyUI's environment.
# This previously upgraded Hub to 1.31 and broke Transformers.
# ------------------------------------------------------------

echo
echo "==> Creating isolated Hugging Face downloader"

HF_ENV="/opt/hf-download-env"

if [[ ! -x "${HF_ENV}/bin/python" ]]; then

    "${COMFY_PYTHON}" -m venv "${HF_ENV}"

    "${HF_ENV}/bin/python" -m pip install --upgrade pip

    "${HF_ENV}/bin/python" -m pip install \
        "huggingface_hub>=0.30"

fi

HF_PYTHON="${HF_ENV}/bin/python"

# ------------------------------------------------------------
# Hugging Face download helper.
#
# Uses the Python API rather than the hf CLI.
# This avoids the removed --local-dir-use-symlinks option.
# ------------------------------------------------------------

download_hf() {

    local repo="$1"
    local remote="$2"
    local local_dir="$3"
    local filename="$4"

    mkdir -p "${local_dir}"

    if [[ -f "${local_dir}/${filename}" ]]; then
        echo "  already exists: ${local_dir}/${filename}"
        return
    fi

    echo
    echo "  --------------------------------------------------------"
    echo "  Downloading:"
    echo "    ${repo}"
    echo "    ${remote}"
    echo "  Destination:"
    echo "    ${local_dir}/${filename}"
    echo "  --------------------------------------------------------"

    "${HF_PYTHON}" - "${repo}" "${remote}" "${local_dir}" <<'PY'
import sys
from huggingface_hub import hf_hub_download

repo_id = sys.argv[1]
filename = sys.argv[2]
local_dir = sys.argv[3]

hf_hub_download(
    repo_id=repo_id,
    filename=filename,
    local_dir=local_dir,
)

print("Download complete.")
PY

}

# ------------------------------------------------------------
# MiniMax H3 diffusion models
# ------------------------------------------------------------

echo
echo "==> Downloading MiniMax H3 diffusion models"

download_hf \
    "Comfy-Org/MiniMax-H3" \
    "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
    "${MODELS}/diffusion_models" \
    "minimax_h3_ref2va_pruned_int8_convrot.safetensors"

download_hf \
    "Comfy-Org/MiniMax-H3" \
    "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
    "${MODELS}/diffusion_models" \
    "minimax_h3_fl2va_pruned_int8_convrot.safetensors"

# ------------------------------------------------------------
# Qwen text encoder
# ------------------------------------------------------------

echo
echo "==> Downloading Qwen3-VL text encoder"

download_hf \
    "Comfy-Org/MiniMax-H3" \
    "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
    "${MODELS}/text_encoders" \
    "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"

# ------------------------------------------------------------
# MiniMax H3 VAEs
# ------------------------------------------------------------

echo
echo "==> Downloading MiniMax H3 VAEs"

download_hf \
    "Comfy-Org/MiniMax-H3" \
    "vae/minimax_h3_video_vae_fp16.safetensors" \
    "${MODELS}/vae" \
    "minimax_h3_video_vae_fp16.safetensors"

download_hf \
    "Comfy-Org/MiniMax-H3" \
    "vae/minimax_h3_audio_vae_fp32.safetensors" \
    "${MODELS}/vae" \
    "minimax_h3_audio_vae_fp32.safetensors"

# ------------------------------------------------------------
# Turbo LoRA
# ------------------------------------------------------------

echo
echo "==> Downloading MiniMax H3 Turbo LoRA"

download_hf \
    "lightx2v/Minimax-h3-Turbo" \
    "minimax_h3_fl2v_turbo_4step_v1.1_768p_comfyui_bf16.safetensors" \
    "${MODELS}/loras/MiniMax H3" \
    "minimax_h3_fl2v_turbo_4step_v1.1_768p_comfyui_bf16.safetensors"

# ------------------------------------------------------------
# Frame interpolation
# ------------------------------------------------------------

echo
echo "==> Downloading FILM frame interpolation model"

download_hf \
    "Comfy-Org/frame_interpolation" \
    "frame_interpolation/film_net_fp16.safetensors" \
    "${MODELS}/frame_interpolation" \
    "film_net_fp16.safetensors"

# ------------------------------------------------------------
# TAE
# ------------------------------------------------------------

echo
echo "==> Downloading MiniMax H3 TAE"

download_hf \
    "Kijai/MiniMax-H3-TAE" \
    "vae_approx/taeh3.safetensors" \
    "${MODELS}/vae_approx" \
    "taeh3.safetensors"

# ------------------------------------------------------------
# SAM 3.1
# ------------------------------------------------------------

echo
echo "==> Downloading SAM 3.1"

download_hf \
    "Comfy-Org/sam3.1" \
    "checkpoints/sam3.1_multiplex_fp16.safetensors" \
    "${MODELS}/checkpoints" \
    "sam3.1_multiplex_fp16.safetensors"

# ------------------------------------------------------------
# HMInnie
#
# Deliberately NOT downloaded because its source wasn't
# identified from the supplied workflow.
# ------------------------------------------------------------

echo
echo "==> HMInnie model"

if [[ -f "${MODELS}/loras/MiniMax H3/xxx/HMInnie_v1_e50.safetensors" ]]; then

    echo "  HMInnie_v1_e50.safetensors found."

else

    echo "  HMInnie_v1_e50.safetensors was NOT found."
    echo "  This file was referenced by the supplied workflow,"
    echo "  but its download source was not identified."
    echo
    echo "  If the workflow branch requires it, place it here:"
    echo
    echo "  ${MODELS}/loras/MiniMax H3/xxx/HMInnie_v1_e50.safetensors"
    echo

fi

# ------------------------------------------------------------
# Workflow
# ------------------------------------------------------------

if [[ -n "${WORKFLOW_URL:-}" ]]; then

    echo
    echo "==> Downloading workflow"

    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        "${WORKFLOW_URL}" \
        -o "${WORKFLOWS}/fs2_NR-MiniMaxH3-Turbo-Extend-NoPDD-v18.json"

else

    echo
    echo "WARNING: WORKFLOW_URL is not set."

fi

# ------------------------------------------------------------
# Show installed models
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Provisioning complete"
echo "============================================================"

echo
echo "ComfyUI:"
echo "  ${COMFY_DIR}"

echo
echo "Models:"
find "${MODELS}" -type f -name "*.safetensors" -printf "  %p\n" 2>/dev/null || true

echo
echo "Workflow:"
echo "  ${WORKFLOWS}/fs2_NR-MiniMaxH3-Turbo-Extend-NoPDD-v18.json"

echo
echo "============================================================"
echo " IMPORTANT"
echo "============================================================"
echo "Keep the supplied workflow in classic/legacy node mode."
echo "Do NOT enable experimental Nodes 2 mode."
echo "============================================================"

# ------------------------------------------------------------
# Restart ComfyUI
# ------------------------------------------------------------

echo
echo "==> Starting ComfyUI"

if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl start comfyui || {
        echo
        echo "WARNING: Could not start ComfyUI via supervisor."
        echo "Check:"
        echo "  supervisorctl status"
        echo
    }
fi

echo
echo "==> Provisioning finished."
