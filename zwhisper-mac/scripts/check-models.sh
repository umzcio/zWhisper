#!/bin/bash
set -euo pipefail

# Compares the local-model catalog with what's published upstream, so the Models
# screen doesn't go stale silently. Exits 1 only when a catalog model has vanished
# (its Download button would fail); everything else is a warning to review.
# Nothing here changes which model anyone uses.
#
# Usage: scripts/check-models.sh [--update]
#   --update records the current upstream models as reviewed.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CATALOG="${CATALOG_FILE:-$ROOT/Sources/zWhisper/Models/ModelCatalog.swift}"
export KNOWN="${KNOWN_MODELS_FILE:-$ROOT/scripts/known-models.json}"
export RESOLVED="$ROOT/zWhisper.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
export CLOUD_BACKEND="$ROOT/Sources/zWhisper/Modes/CloudLLMBackend.swift"
export UPDATE="${1:-}"
export LATEST_WHISPERKIT
LATEST_WHISPERKIT="$(gh release view --repo argmaxinc/argmax-oss-swift --json tagName --jq .tagName 2>/dev/null || true)"
export LATEST_FLUIDAUDIO
LATEST_FLUIDAUDIO="$(gh release view --repo FluidInference/FluidAudio --json tagName --jq .tagName 2>/dev/null || true)"

python3 -I - <<'PY'
import json, os, re, sys, urllib.error, urllib.request

REPO = "https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main"
# The NVIDIA rows (FluidAudio): the exact folders FluidModelStore downloads.
FLUID_TREES = {
    "Parakeet": "FluidInference/parakeet-ultra-coreml/tree/main",
    "Parakeet vocabulary model": "FluidInference/parakeet-ctc-110m-coreml/tree/main",
    "Nemotron": "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/tree/main/multilingual/1120ms",
}
CONFIG = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/config.json"

def fetch(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        return json.load(response)

try:
    upstream = sorted(x["path"] for x in fetch(REPO) if x["type"] == "directory")
    config = fetch(CONFIG)
except Exception as error:
    print(f"warning: couldn't reach the model repo, skipping the model check ({error})")
    sys.exit(0)

mac_defaults = {
    entry["chips"]: entry["models"]["default"]
    for entry in config["device_support"]
    if any(i.startswith(("Mac", "iMac")) for i in entry["identifiers"])
}

if os.environ["UPDATE"] == "--update":
    with open(os.environ["KNOWN"], "w") as f:
        json.dump({"variants": upstream, "macDefaults": mac_defaults}, f, indent=2)
        f.write("\n")
    print("Recorded the current upstream models as reviewed.")
    sys.exit(0)

catalog = open(os.environ["CATALOG"]).read()
locals_block = catalog[catalog.index("static let locals"):catalog.index("static let clouds")]
ids = re.findall(r'ModelCatalogEntry\(id: "([^"]+)"', locals_block)
missing = [i for i in ids if f"openai_whisper-{i}" not in upstream]

known = json.load(open(os.environ["KNOWN"]))
warnings = [f"new upstream model: {v}" for v in upstream if v not in known["variants"]]
warnings += [f"upstream model removed: {v}" for v in known["variants"] if v not in upstream]
if mac_defaults != known["macDefaults"]:
    warnings.append(f"Argmax's recommended Mac defaults changed: {mac_defaults}")

for name, tree in FLUID_TREES.items():
    try:
        if not any(x["type"] == "file" for x in fetch(f"https://huggingface.co/api/models/{tree}")):
            missing.append(name)
    except urllib.error.HTTPError:
        missing.append(name)
    except Exception as error:
        warnings.append(f"couldn't check {name} upstream ({error})")

try:
    pins = json.load(open(os.environ["RESOLVED"]))["pins"]
except (OSError, KeyError):
    pins = []
for package, identity, env in [
    ("WhisperKit", "argmax-oss-swift", "LATEST_WHISPERKIT"),
    ("FluidAudio", "fluidaudio", "LATEST_FLUIDAUDIO"),
]:
    latest = os.environ.get(env, "").lstrip("v")
    pinned = next((p["state"].get("version") for p in pins if p["identity"] == identity), None)
    if not pinned:
        warnings.append(f"couldn't read the pinned {package} version")
    elif not latest:
        warnings.append(f"couldn't look up the latest {package} release")
    elif pinned != latest:
        warnings.append(f"{package} {latest} is out, this build uses {pinned}")

for warning in warnings:
    print(f"warning: {warning}")
rewrite_model = re.search(r'model: "([^"]+)"', open(os.environ["CLOUD_BACKEND"]).read()).group(1)
print(f"Check by hand: {rewrite_model} (rewrites) and gpt-transcribe at https://developers.openai.com/api/docs/deprecations")
print("Check by hand: whisper-large-v3 at https://console.groq.com/docs/speech-to-text, nova-3 at https://deepgram.com/pricing")

if missing:
    print(f"error: catalog models no longer upstream: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)
print(f"Catalog OK: {len(ids) + len(FLUID_TREES)} model downloads available upstream, {len(warnings)} warning(s).")
PY
