from flask import Flask, request, jsonify, Response
import requests
import os
import json

app = Flask(__name__)

# ==========
# ENV & CONST
# ==========
HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL   = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

DEFAULT_TIMEOUT = 60
JSON_CT = "application/json"

# ==========
# HELPERS
# ==========
def convert_ollama_to_hyperbolic(ollama_data: dict) -> dict:
    """
    Terima payload gaya Ollama:
      - { "prompt": "...", "stream": bool, ... } atau
      - { "messages": [...], "stream": bool, ... }
    Kembalikan payload OpenAI-style untuk Hyperbolic.
    """
    messages = []
    if not isinstance(ollama_data, dict):
        ollama_data = {}

    if "prompt" in ollama_data:
        messages.append({"role": "user", "content": ollama_data.get("prompt", "")})
    elif "messages" in ollama_data and isinstance(ollama_data["messages"], list):
        messages = ollama_data["messages"]

    return {
        "model": HYPERBOLIC_MODEL,
        "messages": messages,
        "max_tokens": ollama_data.get("max_tokens", 512),
        "temperature": ollama_data.get("temperature", 0.7),
        "top_p": ollama_data.get("top_p", 0.9),
        # untuk kesederhanaan, non-stream
        "stream": False,
    }


def convert_hyperbolic_to_ollama(hyperbolic_response: dict, original_model_name: str = None) -> dict:
    """
    Konversi respons OpenAI-style ke format sederhana Ollama /api/generate.
    """
    try:
        original_model_name = original_model_name or HYPERBOLIC_MODEL
        choices = hyperbolic_response.get("choices", [])
        content = choices[0].get("message", {}).get("content", "") if choices else ""
        return {
            "model": original_model_name,
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
    except Exception as e:
        return {"model": original_model_name or "unknown", "response": f"Error: {str(e)}", "done": True}


def _hyperbolic_post_chat(payload: dict) -> requests.Response:
    """
    Panggil Hyperbolic /chat/completions dengan header & timeout standar.
    """
    headers = {
        "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
        "Content-Type": JSON_CT,
    }
    return requests.post(
        f"{HYPERBOLIC_API_URL}/chat/completions",
        json=payload,
        headers=headers,
        timeout=DEFAULT_TIMEOUT,
    )

# ==========
# ROUTES OLLAMA-COMPAT
# ==========

@app.route('/api/tags', methods=['GET'])
def list_models():
    """
    Minimal endpoint yang biasa dipakai klien Ollama untuk cek daftar model.
    Dibuat dinamis mengikuti env HYPERBOLIC_MODEL agar konsisten.
    """
    m = HYPERBOLIC_MODEL
    return jsonify({
        "models": [{
            "name": m,
            "model": m,
            "modified_at": "",
            "size": 0,
            "digest": "",
            # format kita proxy OpenAI-style, bukan file GGUF asli
            "details": {"format": "openai-proxy", "family": "meta-llama"}
        }]
    })


@app.route('/api/generate', methods=['POST'])
def api_generate():
    """
    Endpoint gaya Ollama lama (/api/generate). Konversi ke Hyperbolic lalu balas format Ollama.
    """
    try:
        ollama_data = request.get_json(force=True, silent=True) or {}
        hyperbolic_data = convert_ollama_to_hyperbolic(ollama_data)
        r = _hyperbolic_post_chat(hyperbolic_data)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 500
        hyperbolic_json = r.json()
        ollama_resp = convert_hyperbolic_to_ollama(hyperbolic_json, ollama_data.get("model") or HYPERBOLIC_MODEL)
        return jsonify(ollama_resp), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/chat', methods=['POST'])
def api_chat():
    """
    Endpoint Ollama-style chat. Kita bentuk payload OpenAI-style dan balas format Ollama chat.
    """
    try:
        payload = request.get_json(force=True, silent=True) or {}
        # Pastikan ada messages; kalau hanya "prompt", bungkus jadi message user
        if "messages" not in payload and "prompt" in payload:
            payload["messages"] = [{"role": "user", "content": payload.get("prompt", "")}]
        payload["model"] = HYPERBOLIC_MODEL
        payload["stream"] = False  # simple non-stream

        r = _hyperbolic_post_chat(payload)
        content_type = r.headers.get("content-type", "")
        data = r.json() if content_type.startswith(JSON_CT) else {}
        content = ""
        if isinstance(data, dict):
            ch = data.get("choices", [])
            if ch:
                content = ch[0].get("message", {}).get("content", "")

        # Respon kompatibel Ollama /api/chat
        return jsonify({
            "model": HYPERBOLIC_MODEL,
            "created_at": "",
            "message": {"role": "assistant", "content": content},
            "done": True,
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/pull', methods=['POST'])
def api_pull():
    """
    Ollama biasanya 'pull' model. Karena kita proxy ke Hyperbolic (tanpa file lokal),
    cukup jawab sukses supaya caller lanjut.
    """
    body = request.get_json(force=True, silent=True) or {}
    name = body.get("name") or HYPERBOLIC_MODEL
    return jsonify({
        "status": "success",
        "name": name,
        "digest": "",
        "size": 0,
        "details": {"format": "openai-proxy"}
    }), 200


@app.route('/api/show', methods=['POST'])
def api_show():
    """
    Tampilkan metadata model minimal ala Ollama.
    """
    body = request.get_json(force=True, silent=True) or {}
    name = body.get("name") or HYPERBOLIC_MODEL
    return jsonify({
        "license": "",
        "modelfile": "",
        "parameters": "",
        "template": "",
        "details": {
            "parent_model": "",
            "format": "openai-proxy",
            "family": "meta-llama",
            "parameter_size": "3B"
        },
        "model_info": {},
        "model": name
    }), 200

# ==========
# OPENAI-COMPAT (passthrough)
# ==========

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """
    Passthrough OpenAI /v1/chat/completions → Hyperbolic /chat/completions.
    """
    try:
        data = request.get_json(force=True, silent=True) or {}
        data["model"] = HYPERBOLIC_MODEL
        r = _hyperbolic_post_chat(data)
        return Response(r.content, status=r.status_code, content_type=r.headers.get('content-type', JSON_CT))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ==========
# HEALTH
# ==========

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

# ==========
# MAIN
# ==========

if __name__ == '__main__':
    # Proxy dengarkan di 0.0.0.0:11434 (compose map ke 11434 & 14444 di host)
    app.run(host='0.0.0.0', port=11434, debug=False)
