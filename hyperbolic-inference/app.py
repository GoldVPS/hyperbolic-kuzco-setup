# app.py
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
import os
import json
import requests
from datetime import datetime

app = Flask(__name__)
CORS(app)

# === ENV ===
HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1").rstrip("/")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL   = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

SESSION = requests.Session()
DEFAULT_TIMEOUT = 60

# === Helpers ===
def _headers():
    return {
        "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
        "Content-Type": "application/json",
    }

def _ensure_messages(data: dict):
    """Terima payload gaya Ollama (prompt) atau OpenAI (messages) lalu normalisasi ke OpenAI messages."""
    if not isinstance(data, dict):
        data = {}
    if "messages" in data and isinstance(data["messages"], list):
        msgs = data["messages"]
    elif "prompt" in data:
        p = data.get("prompt", "")
        msgs = [{"role": "user", "content": p}]
    else:
        msgs = []
    return msgs

def _to_ollama_chat_response(content: str, model: str):
    # Bentuk response ala `ollama /api/chat`
    return {
        "model": model,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "message": {"role": "assistant", "content": content},
        "done": True
    }

def _to_ollama_generate_response(content: str, model: str):
    # Bentuk response ala `ollama /api/generate`
    return {
        "model": model,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "response": content,
        "done": True,
        "context": [],
        "total_duration": 0,
        "load_duration": 0,
        "prompt_eval_count": 0,
        "prompt_eval_duration": 0,
        "eval_count": 0,
        "eval_duration": 0,
    }

def _post_chat_completions(payload: dict):
    # Paksa stream False supaya gampang diparse Kuzco
    payload = dict(payload or {})
    payload.setdefault("model", HYPERBOLIC_MODEL)
    payload["stream"] = False

    r = SESSION.post(
        f"{HYPERBOLIC_API_URL}/chat/completions",
        headers=_headers(),
        json=payload,
        timeout=DEFAULT_TIMEOUT,
    )
    return r

# === Routes ===

@app.route("/", methods=["GET"])
def root():
    return jsonify({"status": "ok", "service": "hyperbolic-ollama-compat", "model": HYPERBOLIC_MODEL})

@app.route("/health", methods=["GET"])
def health():
    ok = bool(HYPERBOLIC_API_KEY)
    return jsonify({"status": "healthy" if ok else "missing_api_key", "model": HYPERBOLIC_MODEL})

@app.route("/api/tags", methods=["GET"])
def list_models():
    # Format mirip ollama /api/tags agar discovery-nya lolos
    model_name = HYPERBOLIC_MODEL
    digest = model_name.replace("/", "-").lower()
    return jsonify({
        "models": [{
            "name": model_name,
            "model": model_name,
            "modified_at": "2024-01-01T00:00:00Z",
            "size": 3000000000,
            "digest": f"hyperbolic-{digest}",
            "details": {"format": "gguf", "family": "llama", "parameter_size": "3B"}
        }]
    })

# ---- OLLAMA COMPAT: /api/chat (chat) ----
@app.route("/api/chat", methods=["POST"])
def api_chat_compat():
    try:
        data = request.get_json(force=True) or {}
        messages = _ensure_messages(data)
        payload = {
            "model": HYPERBOLIC_MODEL,
            "messages": messages,
            "max_tokens": data.get("max_tokens", 512),
            "temperature": data.get("temperature", 0.7),
            "top_p": data.get("top_p", 0.9),
            "stream": False,
        }
        r = _post_chat_completions(payload)
        if not r.ok:
            return Response(r.content, status=r.status_code,
                            content_type=r.headers.get("content-type","application/json"))
        jr = r.json()
        content = (jr.get("choices") or [{}])[0].get("message", {}).get("content", "")
        return jsonify(_to_ollama_chat_response(content, HYPERBOLIC_MODEL)), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ---- OLLAMA COMPAT: /api/generate (text completion) ----
@app.route("/api/generate", methods=["POST"])
def api_generate_compat():
    try:
        data = request.get_json(force=True) or {}
        messages = _ensure_messages(data)
        payload = {
            "model": HYPERBOLIC_MODEL,
            "messages": messages,
            "max_tokens": data.get("max_tokens", 512),
            "temperature": data.get("temperature", 0.7),
            "top_p": data.get("top_p", 0.9),
            "stream": False,
        }
        r = _post_chat_completions(payload)
        if not r.ok:
            return Response(r.content, status=r.status_code,
                            content_type=r.headers.get("content-type","application/json"))
        jr = r.json()
        content = (jr.get("choices") or [{}])[0].get("message", {}).get("content", "")
        return jsonify(_to_ollama_generate_response(content, HYPERBOLIC_MODEL)), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ---- OPENAI STYLE: pass-through (untuk tools lain yang nembak langsung) ----
@app.route("/v1/chat/completions", methods=["POST"])
def v1_chat_completions_passthrough():
    try:
        data = request.get_json(force=True) or {}
        # Paksa model ke env supaya konsisten
        data["model"] = HYPERBOLIC_MODEL
        r = SESSION.post(
            f"{HYPERBOLIC_API_URL}/chat/completions",
            headers=_headers(),
            json=data,
            timeout=DEFAULT_TIMEOUT,
        )
        return Response(r.content, status=r.status_code,
                        content_type=r.headers.get("content-type","application/json"))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# (opsional) kompat route tanpa prefix api, sering kepakai saat uji manual
@app.route("/chat/completions", methods=["POST"])
def chat_completions_short():
    try:
        data = request.get_json(force=True) or {}
        data["model"] = HYPERBOLIC_MODEL
        r = SESSION.post(
            f"{HYPERBOLIC_API_URL}/chat/completions",
            headers=_headers(),
            json=data,
            timeout=DEFAULT_TIMEOUT,
        )
        return Response(r.content, status=r.status_code,
                        content_type=r.headers.get("content-type","application/json"))
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    # Gunicorn disarankan di Docker, tapi ini biar bisa run lokal juga
    app.run(host="0.0.0.0", port=11434, debug=False)
