from flask import Flask, request, jsonify, Response
import requests
import os
import json
import sys
from datetime import datetime

app = Flask(__name__)

HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

# ---------- utils ----------
def log(*args):
    ts = datetime.utcnow().isoformat() + "Z"
    print(f"[proxy] {ts}", *args, file=sys.stdout, flush=True)

def hyper_headers():
    return {
        "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
        "Content-Type": "application/json",
    }

def convert_ollama_to_hyperbolic(ollama_data):
    messages = []
    if "prompt" in ollama_data:
        messages.append({"role": "user", "content": ollama_data["prompt"]})
    elif "messages" in ollama_data:
        messages = ollama_data["messages"]
    return {
        "model": HYPERBOLIC_MODEL,
        "messages": messages,
        "max_tokens": ollama_data.get("max_tokens", 512),
        "temperature": ollama_data.get("temperature", 0.7),
        "top_p": ollama_data.get("top_p", 0.9),
        "stream": False,  # paksa non-stream agar gampang kompatibel
    }

def convert_hyperbolic_to_ollama(hyperbolic_response, original_model_name=None):
    try:
        choices = hyperbolic_response.get("choices", [])
        content = choices[0].get("message", {}).get("content", "") if choices else ""
        return {
            "model": original_model_name or HYPERBOLIC_MODEL,
            "message": {"role": "assistant", "content": content},
            "response": content,      # beberapa klien pakai field ini
            "done": True,
            "created_at": "",
        }
    except Exception as e:
        return {
            "model": original_model_name or HYPERBOLIC_MODEL,
            "response": f"Error: {str(e)}",
            "done": True,
            "created_at": "",
        }

# ---------- basic health ----------
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

# ---------- tags/models ----------
@app.route("/api/tags", methods=["GET"])
def list_models():
    log("GET /api/tags")
    return jsonify({
        "models": [{
            "name": HYPERBOLIC_MODEL,
            "model": HYPERBOLIC_MODEL,
            "modified_at": "2024-01-01T00:00:00Z",
            "size": 3000000000,
            "digest": "hyperbolic-llama3.2-3b",
            "details": {"format": "gguf", "family": "llama", "parameter_size": "3B"}
        }]
    })

# ---------- main chat (ollama-style compat) ----------
@app.route("/api/chat", methods=["POST"])
def api_chat():
    data = request.get_json(force=True, silent=True) or {}
    log("POST /api/chat", f"keys={list(data.keys())}")
    payload = {
        "model": HYPERBOLIC_MODEL,
        "messages": data.get("messages") or [{"role": "user", "content": data.get("prompt", "")}],
        "max_tokens": data.get("max_tokens", 512),
        "temperature": data.get("temperature", 0.7),
        "top_p": data.get("top_p", 0.9),
        "stream": False,
        # map logprobs kalau ada supaya worker gak error walau Hyperbolic mungkin abaikan
        "logprobs": data.get("logprobs", None),
        "top_logprobs": data.get("top_logprobs", None),
    }
    r = requests.post(f"{HYPERBOLIC_API_URL}/chat/completions", headers=hyper_headers(), json=payload, timeout=60)
    try:
        jr = r.json()
    except Exception:
        return Response(r.content, status=r.status_code, content_type=r.headers.get("content-type","application/json"))
    return jsonify(convert_hyperbolic_to_ollama(jr, data.get("model"))), 200

# ---------- openai-style passthrough ----------
@app.route("/v1/chat/completions", methods=["POST"])
def openai_chat_completions():
    data = request.get_json(force=True, silent=True) or {}
    log("POST /v1/chat/completions", f"keys={list(data.keys())}")
    data["model"] = HYPERBOLIC_MODEL
    r = requests.post(f"{HYPERBOLIC_API_URL}/chat/completions", headers=hyper_headers(), json=data, timeout=60)
    return Response(r.content, status=r.status_code, content_type=r.headers.get('content-type', 'application/json'))

# ---------- simple generate (compat lama) ----------
@app.route("/api/generate", methods=["POST"])
def generate():
    ollama_data = request.get_json(force=True, silent=True) or {}
    log("POST /api/generate", f"keys={list(ollama_data.keys())}")
    hyperbolic_data = convert_ollama_to_hyperbolic(ollama_data)
    r = requests.post(f"{HYPERBOLIC_API_URL}/chat/completions", json=hyperbolic_data, headers=hyper_headers(), timeout=60)
    if r.status_code != 200:
        return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 500
    return jsonify(convert_hyperbolic_to_ollama(r.json(), ollama_data.get("model"))), 200

# ---------- extra compat endpoints that Kuzco sometimes hits ----------
@app.route("/api/create", methods=["POST"])
def api_create():
    log("POST /api/create (noop)")
    return jsonify({"status": "ok"}), 200

@app.route("/api/pull", methods=["POST"])
def api_pull():
    # Kuzco terkadang “pull model” kalau pakai sidecar; kita jawab sukses instan
    body = request.get_json(force=True, silent=True) or {}
    log("POST /api/pull", body.get("name"))
    return jsonify({"status": "success", "model": body.get("name", HYPERBOLIC_MODEL)}), 200

@app.route("/api/show", methods=["POST"])
def api_show():
    body = request.get_json(force=True, silent=True) or {}
    log("POST /api/show", body.get("name"))
    return jsonify({"model": body.get("name", HYPERBOLIC_MODEL)}), 200

@app.route("/api/ps", methods=["GET"])
def api_ps():
    log("GET /api/ps")
    return jsonify({"models": [HYPERBOLIC_MODEL]}), 200

@app.route("/api/embed", methods=["POST"])
@app.route("/api/embeddings", methods=["POST"])
def api_embeddings():
    body = request.get_json(force=True, silent=True) or {}
    log("POST", request.path, f"len_input={len((body.get('input') or ''))}")
    # dummy vector to keep clients satisfied
    return jsonify({"embeddings": [{"embedding": [0.0]*16, "index": 0}]}), 200

@app.route("/api/version", methods=["GET"])
def api_version():
    log("GET /api/version")
    return jsonify({"version": "ollama-compat-proxy-1.0"}), 200

# ---------- safe fallback for any /api/*  ----------
@app.route("/api/<path:anything>", methods=["GET","POST","PUT","DELETE","PATCH"])
def api_fallback(anything):
    log(f"{request.method} /api/{anything} -> fallback 200")
    # supaya klien yang berharap JSON gak error
    return jsonify({"status": "ok", "path": f"/api/{anything}"}), 200

# ---------- root ----------
@app.route("/", methods=["GET"])
def root():
    return jsonify({"ok": True, "service": "hyperbolic-ollama-compat-proxy", "model": HYPERBOLIC_MODEL}), 200

if __name__ == "__main__":
    # bind ke semua interface (container) port 11434
    app.run(host="0.0.0.0", port=11434, debug=False)
