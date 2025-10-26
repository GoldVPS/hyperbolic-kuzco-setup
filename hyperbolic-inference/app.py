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

# Model mapping dari Ollama ke Hyperbolic
MODEL_MAPPING = {
    "llama3.2:3b-instruct-fp16": "meta-llama/Llama-3.2-3B-Instruct",
    "llama3.2:3b-instruct": "meta-llama/Llama-3.2-3B-Instruct",
    "llama3.2:3b": "meta-llama/Llama-3.2-3B-Instruct",
    "llama3.2": "meta-llama/Llama-3.2-3B-Instruct",
    "llama3:8b": "meta-llama/Meta-Llama-3.1-8B-Instruct",
    "llama3:70b": "meta-llama/Meta-Llama-3.1-70B-Instruct",
    # Default fallback
    "default": "meta-llama/Llama-3.2-3B-Instruct"
}

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

def _map_model(ollama_model):
    """Map Ollama model names to Hyperbolic model names"""
    if ollama_model in MODEL_MAPPING:
        return MODEL_MAPPING[ollama_model]
    return MODEL_MAPPING["default"]

def _to_hyperbolic_payload(messages, max_tokens=None, temperature=None, top_p=None, stream=False, model=None):
    # Gunakan model yang dimapping atau default
    hyperbolic_model = _map_model(model) if model else HYPERBOLIC_MODEL
    
    payload = {
        "model": hyperbolic_model,
        "messages": messages or [],
        "stream": stream
    }
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens
    if temperature is not None:
        payload["temperature"] = temperature
    if top_p is not None:
        payload["top_p"] = top_p
    return payload

def _from_hyperbolic_to_ollama(h_resp, original_model=None):
    content = ""
    choices = h_resp.get("choices") or []
    if choices:
        content = _safe_get(choices[0], "message", "content", default="") or ""

    return {
        "model": original_model or HYPERBOLIC_MODEL,
        "created_at": _now_iso(),
        "message": {
            "role": "assistant",
            "content": content
        },
        "done": True,
        "done_reason": "stop",
        "total_duration": 1000000000,
        "load_duration": 100000000,
        "prompt_eval_count": 10,
        "prompt_eval_duration": 50000000,
        "eval_count": 20,
        "eval_duration": 800000000
    }

def _ollama_options(body):
    opts = body.get("options") or {}
    temperature = body.get("temperature", opts.get("temperature", 0.7))
    top_p       = body.get("top_p", opts.get("top_p", 0.9))
    max_tokens  = body.get("max_tokens", opts.get("num_predict", 512))
    stream      = body.get("stream", False)
    return max_tokens, temperature, top_p, stream

def _http_post_json(url, payload, timeout=60):
    r = SESSION.post(url, data=json.dumps(payload), timeout=timeout)
    return r

# ===================== Routes =====================

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

@app.route("/", methods=["GET"])
def root():
    return jsonify({
        "message": "Hyperbolic Inference Proxy", 
        "status": "running",
        "supported_models": list(MODEL_MAPPING.values())
    })

@app.route("/api/version", methods=["GET"])
def api_version():
    return jsonify({"version": "0.1.0"})

@app.route("/api/tags", methods=["GET"])
def api_tags():
    # Return semua model yang didukung (dalam format Ollama)
    ollama_models = []
    for ollama_name, hyperbolic_name in MODEL_MAPPING.items():
        if ollama_name != "default":
            ollama_models.append({
                "name": ollama_name,
                "model": hyperbolic_name,
                "modified_at": "2024-01-01T00:00:00Z",
                "size": 3000000000,
                "digest": f"hyperbolic-{hyperbolic_name.replace('/', '-').lower()}",
                "details": {"format": "gguf", "family": "llama", "parameter_size": "3B"}
            })
    
    return jsonify({"models": ollama_models})

@app.route("/api/generate", methods=["POST"])
def api_generate():
    try:
        body = request.get_json(force=True) or {}
        prompt = body.get("prompt", "")
        if not prompt:
            return jsonify({"error": "prompt is required"}), 400

        max_tokens, temperature, top_p, stream = _ollama_options(body)
        requested_model = body.get("model", "llama3.2:3b-instruct-fp16")

        messages = [{"role": "user", "content": prompt}]
        payload = _to_hyperbolic_payload(
            messages, 
            max_tokens=max_tokens, 
            temperature=temperature, 
            top_p=top_p, 
            stream=stream,
            model=requested_model
        )

        r = _http_post_json(f"{HYPERBOLIC_API_URL}/chat/completions", payload)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 502

        out = _from_hyperbolic_to_ollama(r.json(), original_model=requested_model)
        
        return jsonify({
            "model": out["model"],
            "created_at": out["created_at"],
            "response": out["message"]["content"],
            "done": True,
            "context": [],
            "total_duration": out["total_duration"],
            "load_duration": out["load_duration"],
            "prompt_eval_count": out["prompt_eval_count"],
            "prompt_eval_duration": out["prompt_eval_duration"],
            "eval_count": out["eval_count"],
            "eval_duration": out["eval_duration"]
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/chat", methods=["POST"])
def api_chat():
    try:
        body = request.get_json(force=True) or {}
        requested_model = body.get("model", "llama3.2:3b-instruct-fp16")

        messages = body.get("messages")
        if not messages and "prompt" in body:
            messages = [{"role": "user", "content": body.get("prompt", "")}]

        if not messages:
            return jsonify({"error": "messages or prompt is required"}), 400

        max_tokens, temperature, top_p, stream = _ollama_options(body)

        payload = _to_hyperbolic_payload(
            messages, 
            max_tokens=max_tokens, 
            temperature=temperature, 
            top_p=top_p, 
            stream=stream,
            model=requested_model
        )

        r = _http_post_json(f"{HYPERBOLIC_API_URL}/chat/completions", payload)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 502

        out = _from_hyperbolic_to_ollama(r.json(), original_model=requested_model)
        return jsonify(out)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/show", methods=["POST"])
def api_show():
    body = request.get_json(force=True) or {}
    model = body.get("name", "llama3.2:3b-instruct-fp16")
    hyperbolic_model = _map_model(model)
    
    return jsonify({
        "modelfile": f"""
FROM {hyperbolic_model}
TEMPLATE '''[INST] {{ if .System }}<<SYS>>{{ .System }}<</SYS>>

{{ end }}{{ .Prompt }} [/INST]'''
SYSTEM \"\"\"You are a helpful assistant.\"\"\"
PARAMETER temperature 0.7
PARAMETER top_p 0.9
        """.strip(),
        "parameters": {
            "temperature": "0.7",
            "top_p": "0.9"
        },
        "template": "[INST] {{ if .System }}<<SYS>>{{ .System }}<</SYS>>\n\n{{ end }}{{ .Prompt }} [/INST]",
        "details": {
            "format": "gguf",
            "family": "llama",
            "parameter_size": "3B",
            "quantization_level": "Q4_0"
        }
    })

@app.route("/api/ps", methods=["GET", "POST"])
def api_ps():
    return jsonify({"models": [
        {
            "name": "llama3.2:3b-instruct-fp16",
            "model": "meta-llama/Llama-3.2-3B-Instruct",
            "size": 3000000000,
            "digest": "hyperbolic-llama3.2-3b",
            "details": {"parent_model": "", "format": "gguf", "family": "llama", "parameter_size": "3B"},
            "expires_at": "2024-12-31T23:59:59Z",
            "size_vram": 1500000000
        }
    ]})

@app.route("/api/copy", methods=["POST"])
def api_copy():
    return jsonify({"status": "success"})

@app.route("/api/delete", methods=["DELETE"])
def api_delete():
    return jsonify({"status": "success"})

@app.route("/api/pull", methods=["POST"])
def api_pull():
    body = request.get_json(force=True) or {}
    model = body.get("name") or "llama3.2:3b-instruct-fp16"
    
    return jsonify({"status": "success"})

@app.route("/api/blobs/<digest>", methods=["HEAD"])
def api_blobs_head(digest):
    return Response(status=200)

@app.route("/api/blobs/<digest>", methods=["GET"])
def api_blobs_get(digest):
    return jsonify({"status": "success"})

@app.route("/v1/chat/completions", methods=["POST"])
def v1_chat_completions_passthrough():
    try:
        data = request.get_json(force=True) or {}
        # Map model jika perlu
        requested_model = data.get("model", "llama3.2:3b-instruct-fp16")
        hyperbolic_model = _map_model(requested_model)
        data["model"] = hyperbolic_model
        
        r = _http_post_json(f"{HYPERBOLIC_API_URL}/chat/completions", data)
        return Response(r.content, status=r.status_code, content_type=r.headers.get("content-type", "application/json"))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# CORS handling
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

@app.route('/', methods=['OPTIONS'])
@app.route('/<path:path>', methods=['OPTIONS'])
def options_handler(path=None):
    return Response(status=200)

# Catch-all untuk route yang tidak ditemukan
@app.errorhandler(404)
def not_found(e):
    return jsonify({
        "error": "Endpoint not found", 
        "available_endpoints": [
            "/health", "/api/version", "/api/tags", "/api/chat", "/api/generate", 
            "/api/show", "/api/ps", "/api/pull", "/v1/chat/completions"
        ]
    }), 404

# ===================== Main =====================
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=11434, debug=False)
