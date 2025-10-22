# Hyperbolic Kuzco Setup

Setup untuk menjalankan Kuzco dengan Hyperbolic Inference Server (tanpa VPS GPU).

## 🚀 Quick Deploy

```bash
git clone https://github.com/username/hyperbolic-kuzco-setup.git
cd hyperbolic-kuzco-setup
```
# Auto deploy (recommended)
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Atau manual setup:
cd hyperbolic-inference
cp .env.example .env
# Edit .env dengan API key Hyperbolic
nano .env
docker-compose up -d

cd ../kuzco-main
# Edit docker-compose.yml dengan WORKER_CODE dan WORKER_NAME
nano docker-compose.yml
docker-compose up -d
