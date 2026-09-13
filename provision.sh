#!/usr/bin/env bash
set -Eeuo pipefail

# Rob's disposable RunPod MiniMax H3 ComfyUI provisioning script.
# Designed for a fresh RunPod Pod with NO Network Volume.
#
# The workflow and all large model files are downloaded on every new Pod.
# Set WORKFLOW_URL to the raw GitHub URL of the workflow JSON.
#
# Optional:
#   HF_TOKEN       Hugging Face token if a future model becomes gated.
#   WORKFLOW_URL   Raw URL to fs2_NR-MiniMaxH3-Turbo-Extend-NoPDD-v18.json

COMFY_DIR="${COMFY_DIR:-/opt/ComfyUI}"
MODELS="${COMFY_DIR}/models"
CUSTOM="${COMFY_DIR}/custom_nodes"
WORKFLOWS="${COMFY_DIR}/user/default/workflows"

export HF_HUB_ENABLE_HF_TRANSFER=1

mkdir -p \
  "${MODELS}/diffusion_models" \
  "${MODELS}/text_encoders" \
  "${MODELS}/vae" \
  "${MODELS}/loras/MiniMax H3" \
  "${MODELS}/checkpoints" \
  "${MODELS}/frame_interpolation" \
  "${MODELS}/vae_approx" \
  "${WORKFLOWS}"

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
    echo "  cloning ${name}"
    git clone --depth 1 "${REPOS[$name]}" "${dir}"
  else
    echo "  ${name} already present"
  fi

  if [[ -f "${dir}/requirements.txt" ]]; then
    echo "  installing Python requirements for ${name}"
    /opt/environments/python/comfyui/bin/python -m pip install -r "${dir}/requirements.txt" || {
      echo "WARNING: requirements failed for ${name}; continuing so the other nodes can install."
    }
  fi
done

echo "==> Downloading MiniMax H3 models"

# Ensure Hugging Face CLI is available
/opt/environments/python/comfyui/bin/python -m pip install -U huggingface_hub
export PATH="/opt/environments/python/comfyui/bin:$PATH"

download_hf() {
  local repo="$1"
  local remote="$2"
  local local_dir="$3"
  local filename="$4"

  if [[ -f "${local_dir}/${filename}" ]]; then
    echo "  already exists: ${filename}"
    return
  fi

  echo "  downloading ${repo}/${remote}"
  hf download "${repo}" "${remote}" --local-dir "${local_dir}" --local-dir-use-symlinks False
}

# Main workflow models. These exact filenames are referenced by the supplied workflow.
download_hf \
  "Comfy-Org/MiniMax-H3" \
  "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
  "${MODELS}" \
  "minimax_h3_ref2va_pruned_int8_convrot.safetensors"

download_hf \
  "Comfy-Org/MiniMax-H3" \
  "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
  "${MODELS}" \
  "minimax_h3_fl2va_pruned_int8_convrot.safetensors"

download_hf \
  "Comfy-Org/MiniMax-H3" \
  "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
  "${MODELS}" \
  "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"

download_hf \
  "Comfy-Org/MiniMax-H3" \
  "vae/minimax_h3_video_vae_fp16.safetensors" \
  "${MODELS}" \
  "minimax_h3_video_vae_fp16.safetensors"

download_hf \
  "Comfy-Org/MiniMax-H3" \
  "vae/minimax_h3_audio_vae_fp32.safetensors" \
  "${MODELS}" \
  "minimax_h3_audio_vae_fp32.safetensors"

# Turbo LoRA used by the supplied workflow.
download_hf \
  "lightx2v/Minimax-h3-Turbo" \
  "minimax_h3_fl2v_turbo_4step_v1.1_768p_comfyui_bf16.safetensors" \
  "${MODELS}/loras/MiniMax H3" \
  "minimax_h3_fl2v_turbo_4step_v1.1_768p_comfyui_bf16.safetensors"

# Optional/auxiliary models referenced by the supplied workflow.
download_hf \
  "Comfy-Org/frame_interpolation" \
  "frame_interpolation/film_net_fp16.safetensors" \
  "${MODELS}" \
  "film_net_fp16.safetensors"

download_hf \
  "Kijai/MiniMax-H3-TAE" \
  "vae_approx/taeh3.safetensors" \
  "${MODELS}" \
  "taeh3.safetensors"

download_hf \
  "Comfy-Org/sam3.1" \
  "checkpoints/sam3.1_multiplex_fp16.safetensors" \
  "${MODELS}" \
  "sam3.1_multiplex_fp16.safetensors"

# The supplied workflow also references HMInnie_v1_e50.safetensors.
# Its source is not identified by the workflow itself, so we do NOT guess a
# download URL. If your local copy is required by the selected branch, upload
# it to:
#   ${MODELS}/loras/MiniMax H3/xxx/HMInnie_v1_e50.safetensors
#
# This avoids silently downloading a potentially unrelated file.

if [[ -n "${WORKFLOW_URL:-}" ]]; then
  echo "==> Downloading workflow"
  curl -fL --retry 3 "${WORKFLOW_URL}" \
    -o "${WORKFLOWS}/fs2_NR-MiniMaxH3-Turbo-Extend-NoPDD-v18.json"
else
  echo "WARNING: WORKFLOW_URL is not set."
  echo "Upload the supplied workflow JSON manually to:"
  echo "  ${WORKFLOWS}/fs2_NR-MiniMaxH3-Turbo-Extend-NoPDD-v18.json"
fi

echo "==> Provisioning complete"
echo "    ComfyUI: ${COMFY_DIR}"
echo "    Workflow: ${WORKFLOWS}/fs2_NR-MiniMaxH3-Turbo-Extend-NoPDD-v18.json"
echo "    NOTE: Keep ComfyUI in classic/legacy node mode; the supplied workflow notes"
echo "          say not to enable the experimental Nodes 2 mode."
