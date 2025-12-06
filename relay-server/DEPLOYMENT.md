# Spacedrive Relay Server - Production Deployment

## Option 1: Railway.app (Recommended - Easiest)

### Steps:
1. Create account at [railway.app](https://railway.app)
2. Click **"New Project"** → **"Deploy from GitHub repo"**
3. Select this repository and point to `/relay-server` folder
4. Railway auto-detects Node.js and deploys

### Configuration:
- Set root directory to `relay-server` in Railway settings
- PORT is automatically provided by Railway
- WebSocket support is built-in

### Cost: Free tier available (500 hours/month)

---

## Option 2: Render.com

### Steps:
1. Create account at [render.com](https://render.com)
2. Click **"New +"** → **"Web Service"**
3. Connect GitHub repo
4. Configure:
   - **Root Directory**: `relay-server`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Environment**: Node

### Cost: Free tier (spins down after inactivity)

---

## Option 3: Fly.io

### Steps:
```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Navigate to relay-server
cd relay-server

# Launch app
fly launch

# Deploy
fly deploy
```

### Cost: Free tier (3 shared VMs)

---

## Option 4: Docker (Any VPS)

### Build and run:
```bash
cd relay-server
docker build -t spacedrive-relay .
docker run -d -p 8081:8081 --name relay spacedrive-relay
```

---

## After Deployment

Update the relay URL in the app:

1. Get your deployment URL (e.g., `wss://your-app.railway.app`)
2. Update in `lib/client/account_service.dart`:
   ```dart
   static const String _defaultRelayUrl = 'wss://your-app.railway.app';
   ```
3. Update in `lib/client/connection_manager.dart` (default parameter)
4. Update in `lib/relay/relay_client.dart`
5. Rebuild the app

---

## Security Recommendations

1. **Use WSS (WebSocket Secure)** - All cloud providers give HTTPS/WSS automatically
2. **Add rate limiting** - Prevent abuse
3. **Add authentication** - Optional, for private deployments
4. **Monitor logs** - Check for issues

---

## Quick Test

After deployment, test with:
```bash
# Install wscat
npm install -g wscat

# Test connection
wscat -c wss://your-app.railway.app
```

Type: `{"type": "ping"}` 
Should respond: `{"type": "pong"}`
