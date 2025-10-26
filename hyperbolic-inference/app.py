from flask import Flask, request, jsonify, Response
import requests
import os
import json
from datetime import datetime, timezone

app = Flask(__name__)

# ===================== Config =====================
HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1").rstrip("/")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL   = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

SESSION = requests.Session()
SESSION.headers.update({
    "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
    "Content-Type": "application/json"
})

# ===================== Helpers =====================
def _now_iso():
    return datetime.now(timezone.utc).isoformat()

def _safe_get(d, *path, default=None):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

def _to_hyperbolic_payload(messages, max_tokens=None, temperature=None, top_p=None, stream=False):
    payload = {
        "model": HYPERBOLIC_MODEL,
        "messages": messages or [],
        "stream": False  # paksa non-stream demi stabilitas
    }
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens
    if temperature is not None:
        payload["temperature"] = temperature
    if top_p is not None:
        payload["top_p"] = top_p
    return payload

def _from_hyperbolic_to_ollama(h_resp, original_model=None):
    # Ambil teks jawaban
    content = ""
    choices = h_resp.get("choices") or []
    if choices:
        content = _safe_get(choices[0], "message", "content", default="") or ""

    # Format mirip Ollama /api/chat
    return {
        "model": original_model or HYPERBOLIC_MODEL,
        "created_at": _now_iso(),
        "message": {
            "role": "assistant",
            "content": content
        },
        "done": True,
        # Stub logprobs agar konsumen yang expect field ini tidak meledak
        "logprobs": {
            "content": [],
            "token_logprobs": [],
            "tokens": [],
            "top_logprobs": []
        }
    }

def _ollama_options(body):
    """
    Ollama biasanya menaruh pengaturan di body.options
    contoh:
    {
      "messages": [...],
      "model": "llama2",
      "stream": true,
      "options": {"temperature": 0.7, "top_p": 0.9, "num_predict": 256}
    }
    """
    opts = body.get("options") or {}
    temperature = body.get("temperature", opts.get("temperature"))
    top_p       = body.get("top_p", opts.get("top_p"))
    max_tokens  = body.get("max_tokens", opts.get("num_predict"))
    stream      = body.get("stream", False)
    return max_tokens, temperature, top_p, stream

def _http_post_json(url, payload, timeout=60):
    r = SESSION.post(url, data=json.dumps(payload), timeout=timeout)
    return r

# ===================== Routes =====================

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

@app.route("/api/tags", methods=["GET"])
def api_tags():
    # Mirip Ollama /api/tags
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

@app.route("/api/generate", methods=["POST"])
def api_generate():
    """
    Endpoint kompatibel Ollama text completion:
    body: { "prompt": "...", "options": {...}, "model": "xxx", "stream": false }
    Kita konversi ke OpenAI/Hyperbolic chat dengan 1 message user.
    """
    try:
        body = request.get_json(force=True) or {}
        prompt = body.get("prompt", "")
        if not prompt:
            return jsonify({"error": "prompt is required"}), 400

        max_tokens, temperature, top_p, _stream = _ollama_options(body)

        messages = [{"role": "user", "content": prompt}]
        payload = _to_hyperbolic_payload(
            messages, max_tokens=max_tokens, temperature=temperature, top_p=top_p, stream=False
        )

        r = _http_post_json(f"{HYPERBOLIC_API_URL}/chat/completions", payload)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 502

        out = _from_hyperbolic_to_ollama(r.json(), original_model=body.get("model") or HYPERBOLIC_MODEL)
        # Bentuk response yang mirip /api/generate Ollama (minimal)
        return jsonify({
            "model": out["model"],
            "created_at": out["created_at"],
            "response": out["message"]["content"],
            "done": True,
            "context": [],
            "total_duration": 0,
            "load_duration": 0,
            "prompt_eval_count": 0,
            "prompt_eval_duration": 0,
            "eval_count": 0,
            "eval_duration": 0
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/chat", methods=["POST"])
def api_chat():
    """
    Endpoint kompatibel Ollama chat:
    body: { "messages":[...], "model": "...", "options": {...}, "stream": true|false }
    """
    try:
        body = request.get_json(force=True) or {}

        messages = body.get("messages")
        # fallback jika ada "prompt"
        if not messages and "prompt" in body:
            messages = [{"role": "user", "content": body.get("prompt", "")}]

        if not messages:
            return jsonify({"error": "messages or prompt is required"}), 400

        max_tokens, temperature, top_p, _stream = _ollama_options(body)

        payload = _to_hyperbolic_payload(
            messages, max_tokens=max_tokens, temperature=temperature, top_p=top_p, stream=False
        )

        r = _http_post_json(f"{HYPERBOLIC_API_URL}/chat/completions", payload)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 502

        out = _from_hyperbolic_to_ollama(r.json(), original_model=body.get("model") or HYPERBOLIC_MODEL)
        return jsonify(out)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/v1/chat/completions", methods=["POST"])
def v1_chat_completions_passthrough():
    """
    Passthrough OpenAI-compatible -> Hyperbolic.
    Kita inject model default kalau tidak ada.
    """
    try:
        data = request.get_json(force=True) or {}
        data["model"] = data.get("model") or HYPERBOLIC_MODEL
        r = _http_post_json(f"{HYPERBOLIC_API_URL}/chat/completions", data)
        return Response(r.content, status=r.status_code, content_type=r.headers.get("content-type", "application/json"))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ===================== Main =====================
if __name__ == "__main__":
    # Untuk debugging lokal (tidak dipakai saat run via gunicorn)
    app.run(host="0.0.0.0", port=11434, debug=False)
