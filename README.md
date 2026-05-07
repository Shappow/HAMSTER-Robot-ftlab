# HAMSTER Beta — Fork personnel

Fork de [HAMSTER_beta](https://github.com/liyi14/HAMSTER_beta) avec corrections de compatibilité pour RunPod.

## Corrections apportées

| Problème | Fix |
|---|---|
| `flash_attn` incompatible avec nouvelles GPU/CUDA | Remplacé par PyTorch SDPA natif |
| `torch_dtype` manquant en mode 4-bit | Ajout dans `builder.py` |
| `vision_tower` OOM sur GPU < 16 GB | CPU offload auto en mode 4-bit |
| Nom de modèle rejeté (erreur 422) | Validation assouplie dans `server.py` |
| `ip_eth0.txt` vide (pas d'eth0) | Utilisation de `hostname -I` |

---

## Installation rapide (RunPod)

**Image RunPod recommandée**
```
runpod/pytorch:2.1.0-py3.10-cuda12.1.1-devel-ubuntu22.04
```
**GPU recommandé** : A40 (48 GB) ou supérieur

```bash
cd /workspace
git clone https://github.com/TON_USER/hamster-beta-fork.git
cd hamster-beta-fork
chmod +x setup.sh start_server.sh start_gradio.sh
./setup.sh
```

**Terminal 1 — Serveur**
```bash
./start_server.sh
```

**Terminal 2 — Interface**
```bash
./start_gradio.sh
```
Ouvrir `http://localhost:7860`

---

## GPU < 16 GB (mode 4-bit)

```bash
python -W ignore server.py \
    --port 8000 \
    --model-path "Hamster_dev/VILA1.5-13b-..." \
    --conv-mode vicuna_v1 \
    --load-4bit
```

---

## Test rapide

```bash
curl -X POST http://127.0.0.1:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"HAMSTER_dev","messages":[{"role":"user","content":"Hello!"}]}'
```
