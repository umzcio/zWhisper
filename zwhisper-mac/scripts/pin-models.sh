#!/bin/bash
set -euo pipefail

# Records the exact upstream commit and the SHA-256 of every file for each
# local catalog model, in Sources/zWhisper/Models/model-pins.json. The app
# downloads only those commits and refuses any file whose hash differs, so a
# changed or compromised Hugging Face repo can't swap the models it runs.
#
# Run it to adopt new upstream models (review the diff), then commit the JSON.
# check-models.sh fails a release whose pins no longer resolve upstream.
#
# Usage: scripts/pin-models.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PINS="$ROOT/Sources/zWhisper/Models/model-pins.json"

python3 -I - <<'PY'
import hashlib, json, os, urllib.parse, urllib.request

HUB = "https://huggingface.co"
WHISPER_REPO = "argmaxinc/whisperkit-coreml"
TOKENIZER_FILES = ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "special_tokens_map.json"]

# Catalog id -> parts. `folder` names the local folder the files land in
# (ModelPins.folder(for:) in the app); `prefix` is the repo path that maps to it.
WHISPER = {
    "tiny": "openai/whisper-tiny",
    "small": "openai/whisper-small",
    "medium": "openai/whisper-medium",
    "large-v3-v20240930_626MB": "openai/whisper-large-v3",
    "large-v3-v20240930": "openai/whisper-large-v3",
    "large-v3-v20240930_turbo": "openai/whisper-large-v3",
}
MODELS = {}
for variant, tokenizer_repo in WHISPER.items():
    MODELS[variant] = [
        {"repo": WHISPER_REPO, "prefix": f"openai_whisper-{variant}/", "folder": "whisper"},
        {"repo": tokenizer_repo, "prefix": "", "folder": "whisper", "only": TOKENIZER_FILES},
    ]
MODELS["parakeet-tdt-v3"] = [
    {"repo": "FluidInference/parakeet-ultra-coreml", "prefix": "", "folder": "parakeet"},
    {"repo": "FluidInference/parakeet-ctc-110m-coreml", "prefix": "", "folder": "ctc"},
]
MODELS["nemotron-3.5-streaming"] = [
    {"repo": "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML",
     "prefix": "multilingual/1120ms/", "folder": "nemotron"},
]

def get(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()

commits = {}
def commit(repo):
    if repo not in commits:
        commits[repo] = json.loads(get(f"{HUB}/api/models/{repo}/revision/main"))["sha"]
    return commits[repo]

def tree(repo, sha, path):
    url = f"{HUB}/api/models/{repo}/tree/{sha}/{urllib.parse.quote(path.rstrip('/'))}?recursive=true"
    return [x for x in json.loads(get(url)) if x["type"] == "file"]

out = {"models": {}}
for model, parts in MODELS.items():
    pinned = []
    for part in parts:
        repo, prefix = part["repo"], part["prefix"]
        sha = commit(repo)
        files = {}
        for item in tree(repo, sha, prefix):
            path = item["path"]
            relative = path[len(prefix):]
            # FluidAudio skips .mlpackage sources; the app never loads repo docs.
            if ".mlpackage" in path or relative.startswith(".") or "/." in relative:
                continue
            if "only" in part and relative not in part["only"]:
                continue
            # Conversion tooling and docs in the repos; nothing the app loads.
            if "only" not in part and (relative.startswith("convert/")
                    or relative.endswith((".md", ".py", ".toml", ".lock"))
                    or relative == "LICENSE"):
                continue
            if item.get("lfs"):
                digest = item["lfs"]["oid"]
            else:
                digest = hashlib.sha256(get(f"{HUB}/{repo}/resolve/{sha}/{urllib.parse.quote(path)}")).hexdigest()
            files[relative] = digest
        if not files:
            raise SystemExit(f"error: no files for {model} in {repo}/{prefix}")
        pinned.append({"repo": repo, "revision": sha, "folder": part["folder"],
                       "prefix": prefix, "files": dict(sorted(files.items()))})
        print(f"{model}: {repo}@{sha[:10]} {len(files)} files")
    out["models"][model] = pinned

with open(os.environ["PINS"], "w") as f:
    json.dump(out, f, indent=1, sort_keys=True)
    f.write("\n")
print(f"Wrote {os.environ['PINS']}")
PY
