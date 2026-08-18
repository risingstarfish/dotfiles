#!/usr/bin/env sh


llama-server \
  --host 0.0.0.0 \
  --port 8080 \
  --cors-origins http://localhost,http://192.168.10.240,http://192.168.0.197 \
  --cors-credentials \
  --alias kvstorm1 \
  --model ~/opt/llamacpp/models/Qwen3.6-35B-A3B-UD-Q4_K_XL.mtp.gguf \
  --ctx-size 262144 \
  --jinja \
  --flash-attn on \
  -np 1 \
  --spec-type draft-mtp \
  --spec-draft-n-max 2 \
  --cont-batching \
  --metrics \
  --cache-prompt \
  --gpu-layers 999 \
  --temp 0.6 \
  --min-p 0 \
  --top-p 0.95 \
  --top-k 20 \
  --presence-penalty 0