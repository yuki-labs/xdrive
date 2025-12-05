const WebSocket = require('ws');
const crypto = require('crypto');

const PORT = process.env.PORT || 8081;
const wss = new WebSocket.Server({ port: PORT });

// Track active rooms: roomId -> { hosts: Map<deviceName, WebSocket>, clients: Set<WebSocket> }
const rooms = new Map();

// Track which WebSocket belongs to which room and their role
const socketInfo = new Map(); // ws -> { roomId, role: 'host'|'client', deviceName? }

console.log(`Relay server starting on port ${PORT}...`);

// Normalize username to room ID (lowercase, trimmed)
function usernameToRoomId(username) {
  return username.toLowerCase().trim().replace(/\s+/g, '-');
}

// Generate a random room ID (fallback for legacy support)
function generateRoomId() {
  const words = [
    'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel',
    'india', 'juliet', 'kilo', 'lima', 'mike', 'november', 'oscar', 'papa',
    'quebec', 'romeo', 'sierra', 'tango', 'uniform', 'victor', 'whiskey',
    'xray', 'yankee', 'zulu'
  ];

  const word1 = words[Math.floor(Math.random() * words.length)];
  const word2 = words[Math.floor(Math.random() * words.length)];
  const word3 = words[Math.floor(Math.random() * words.length)];

  return `${word1}-${word2}-${word3}`;
}

wss.on('connection', (ws) => {
  console.log('New connection established');

  // Initialize heartbeat
  ws.isAlive = true;

  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      console.log('Received message:', message.type);

      switch (message.type) {
        case 'register':
          // Legacy: random room ID
          handleRegister(ws);
          break;

        case 'register-username':
          // New: username-based room with device name
          handleRegisterUsername(ws, message.username, message.deviceName);
          break;

        case 'join':
          // Legacy: join by room ID
          handleJoin(ws, message.roomId);
          break;

        case 'join-username':
          // New: join by username, get list of hosts
          handleJoinUsername(ws, message.username);
          break;

        case 'check-username':
          // Check if hosts are available for username (without joining)
          handleCheckUsername(ws, message.username);
          break;

        case 'select-host':
          // New: client selects which host device to connect to
          handleSelectHost(ws, message.deviceName);
          break;

        case 'request':
          handleRequest(ws, message);
          break;

        case 'response':
          handleResponse(ws, message);
          break;

        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;

        default:
          console.log('Unknown message type:', message.type);
      }
    } catch (error) {
      console.error('Error processing message:', error);
    }
  });

  ws.on('close', () => {
    handleDisconnect(ws);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    handleDisconnect(ws);
  });
});

// Legacy: Register with random room ID
function handleRegister(ws) {
  let roomId;
  do {
    roomId = generateRoomId();
  } while (rooms.has(roomId));

  // Create room with legacy structure
  rooms.set(roomId, {
    hosts: new Map([['default', ws]]),
    clients: new Set(),
    selectedHost: new Map() // client -> deviceName
  });

  socketInfo.set(ws, { roomId, role: 'host', deviceName: 'default' });

  ws.send(JSON.stringify({
    type: 'registered',
    roomId: roomId
  }));

  console.log(`Host registered with room ID: ${roomId}`);
}

// New: Register with username and device name
function handleRegisterUsername(ws, username, deviceName) {
  if (!username || !deviceName) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Username and device name are required'
    }));
    return;
  }

  const roomId = usernameToRoomId(username);

  // Get or create room
  let room = rooms.get(roomId);
  if (!room) {
    room = {
      hosts: new Map(),
      clients: new Set(),
      selectedHost: new Map()
    };
    rooms.set(roomId, room);
  }

  // Check if device name already exists
  if (room.hosts.has(deviceName)) {
    ws.send(JSON.stringify({
      type: 'error',
      message: `Device "${deviceName}" is already connected for this username`
    }));
    return;
  }

  // Add host with device name
  room.hosts.set(deviceName, ws);
  socketInfo.set(ws, { roomId, role: 'host', deviceName });

  ws.send(JSON.stringify({
    type: 'registered',
    roomId: roomId,
    username: username,
    deviceName: deviceName
  }));

  // Notify existing clients about new host
  for (const client of room.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'hosts-updated',
        hosts: Array.from(room.hosts.keys())
      }));
    }
  }

  console.log(`Host "${deviceName}" registered for username "${username}" (room: ${roomId})`);
}

// Legacy: Join by room ID
function handleJoin(ws, roomId) {
  const room = rooms.get(roomId);

  if (!room) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Room not found'
    }));
    console.log(`Client tried to join non-existent room: ${roomId}`);
    return;
  }

  room.clients.add(ws);
  socketInfo.set(ws, { roomId, role: 'client' });

  // Auto-select first host for legacy compatibility
  const firstHost = room.hosts.keys().next().value;
  if (firstHost) {
    room.selectedHost.set(ws, firstHost);
  }

  ws.send(JSON.stringify({
    type: 'joined',
    roomId: roomId
  }));

  console.log(`Client joined room: ${roomId} (${room.clients.size} clients)`);
}

// New: Check hosts for username without joining
function handleCheckUsername(ws, username) {
  if (!username) {
    ws.send(JSON.stringify({
      type: 'hosts-check-result',
      hosts: []
    }));
    return;
  }

  const roomId = usernameToRoomId(username);
  const room = rooms.get(roomId);

  if (!room || room.hosts.size === 0) {
    ws.send(JSON.stringify({
      type: 'hosts-check-result',
      username: username,
      hosts: []
    }));
    console.log(`Check for "${username}": no hosts`);
    return;
  }

  const hostList = Array.from(room.hosts.keys());

  ws.send(JSON.stringify({
    type: 'hosts-check-result',
    username: username,
    hosts: hostList
  }));

  console.log(`Check for "${username}": ${hostList.length} hosts available`);
}
function handleJoinUsername(ws, username) {
  if (!username) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Username is required'
    }));
    return;
  }

  const roomId = usernameToRoomId(username);
  const room = rooms.get(roomId);

  if (!room || room.hosts.size === 0) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'No hosts found for this username'
    }));
    console.log(`Client tried to join username "${username}" but no hosts found`);
    return;
  }

  room.clients.add(ws);
  socketInfo.set(ws, { roomId, role: 'client' });

  // Send list of available hosts
  const hostList = Array.from(room.hosts.keys());

  ws.send(JSON.stringify({
    type: 'hosts-available',
    username: username,
    hosts: hostList
  }));

  console.log(`Client joined username "${username}", ${hostList.length} hosts available`);
}

// New: Client selects which host to connect to
function handleSelectHost(ws, deviceName) {
  const info = socketInfo.get(ws);
  if (!info || info.role !== 'client') {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Must join a room first'
    }));
    return;
  }

  const room = rooms.get(info.roomId);
  if (!room) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Room not found'
    }));
    return;
  }

  if (!room.hosts.has(deviceName)) {
    ws.send(JSON.stringify({
      type: 'error',
      message: `Host "${deviceName}" not found`
    }));
    return;
  }

  room.selectedHost.set(ws, deviceName);

  ws.send(JSON.stringify({
    type: 'host-selected',
    deviceName: deviceName
  }));

  console.log(`Client selected host "${deviceName}" in room ${info.roomId}`);
}

function handleRequest(ws, message) {
  const info = socketInfo.get(ws);
  if (!info) {
    console.log('Request from socket not in any room');
    return;
  }

  const room = rooms.get(info.roomId);
  if (!room) {
    console.log('Request from socket in non-existent room');
    return;
  }

  // Find the host for this client
  const selectedDeviceName = room.selectedHost.get(ws);
  const host = selectedDeviceName ? room.hosts.get(selectedDeviceName) : room.hosts.values().next().value;

  if (host && host.readyState === WebSocket.OPEN) {
    host.send(JSON.stringify({
      type: 'request',
      requestId: message.requestId,
      data: message.data
    }));
    console.log(`Forwarded request ${message.requestId} to host "${selectedDeviceName || 'default'}"`);
  } else {
    ws.send(JSON.stringify({
      type: 'error',
      requestId: message.requestId,
      message: 'Host not available'
    }));
  }
}

function handleResponse(ws, message) {
  const info = socketInfo.get(ws);
  if (!info || info.role !== 'host') {
    console.log('Response from non-host socket');
    return;
  }

  const room = rooms.get(info.roomId);
  if (!room) {
    console.log('Response from host in non-existent room');
    return;
  }

  // Forward to clients that selected this host
  for (const client of room.clients) {
    const selectedHost = room.selectedHost.get(client);
    if ((selectedHost === info.deviceName || !selectedHost) && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'response',
        requestId: message.requestId,
        data: message.data
      }));
    }
  }

  console.log(`Forwarded response ${message.requestId} from host "${info.deviceName}"`);
}

function handleDisconnect(ws) {
  const info = socketInfo.get(ws);

  if (!info) {
    console.log('Disconnected socket not tracked');
    return;
  }

  const room = rooms.get(info.roomId);
  if (!room) {
    socketInfo.delete(ws);
    return;
  }

  if (info.role === 'host') {
    // Remove this host
    room.hosts.delete(info.deviceName);
    console.log(`Host "${info.deviceName}" disconnected from room: ${info.roomId}`);

    // Notify clients connected to this host
    for (const [client, selectedHost] of room.selectedHost.entries()) {
      if (selectedHost === info.deviceName && client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({
          type: 'error',
          message: `Host "${info.deviceName}" disconnected`
        }));
        room.selectedHost.delete(client);
      }
    }

    // Update remaining clients about available hosts
    const remainingHosts = Array.from(room.hosts.keys());
    for (const client of room.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({
          type: 'hosts-updated',
          hosts: remainingHosts
        }));
      }
    }

    // Delete room if no hosts left
    if (room.hosts.size === 0) {
      rooms.delete(info.roomId);
      console.log(`Room ${info.roomId} deleted (no hosts remaining)`);
    }
  } else {
    // Remove client
    room.clients.delete(ws);
    room.selectedHost.delete(ws);
    console.log(`Client disconnected from room: ${info.roomId} (${room.clients.size} clients remaining)`);
  }

  socketInfo.delete(ws);
}

// Heartbeat to detect dead connections
setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      return ws.terminate();
    }

    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('listening', () => {
  console.log(`✅ Relay server running on port ${PORT}`);
  console.log(`WebSocket URL: ws://localhost:${PORT}`);
});

wss.on('error', (error) => {
  console.error('Server error:', error);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, closing server...');
  wss.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
