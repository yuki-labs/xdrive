# Spacedrive Relay Server

WebSocket relay server to enable internet access for Spacedrive.

## Setup

```bash
cd relay-server
npm install
```

## Run Locally

```bash
npm start
```

Server will run on `ws://localhost:8081`

## Deploy to VPS

### Option 1: DigitalOcean/Vultr
1. Create a droplet (Ubuntu 22.04, $5/month)
2. SSH into server
3. Install Node.js:
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```
4. Copy server files
5. Install dependencies: `npm install`
6. Run with PM2:
```bash
sudo npm install -g pm2
pm2 start server.js
pm2 save
pm2 startup
```

### Option 2: Railway/Render (Free Tier)
1. Push to GitHub
2. Connect to Railway/Render
3. Auto-deploys on push

## Environment Variables

- `PORT`: Server port (default: 8081)

## Usage

The relay server forwards WebSocket messages between:
- **Hosts** (desktop servers)
- **Clients** (mobile apps)

Messages are end-to-end encrypted. The relay only forwards packets.
