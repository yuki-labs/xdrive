const WebSocket = require('ws');
const crypto = require('crypto');

const PORT = process.env.PORT || 8081;
const wss = new WebSocket.Server({ port: PORT });

// Track active rooms: roomId -> { host: WebSocket, clients: Set<WebSocket> }
const rooms = new Map();

// Track which WebSocket belongs to which room
const socketToRoom = new Map();

console.log(`Relay server starting on port ${PORT}...`);

// Generate a memorable room ID
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

// Find room for a given WebSocket
function findRoomForSocket(ws) {
  const roomId = socketToRoom.get(ws);
  return roomId ? rooms.get(roomId) : null;
}

wss.on('connection', (ws) => {
  console.log('New connection established');

  // Initialize heartbeat
  ws.isAlive = true;

  // Handle WebSocket-level pong responses  
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      console.log('Received message:', message.type);

      switch (message.type) {
        case 'register':
          handleRegister(ws);
          break;

        case 'join':
          handleJoin(ws, message.roomId);
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

function handleRegister(ws) {
  // Generate unique room ID
  let roomId;
  do {
    roomId = generateRoomId();
  } while (rooms.has(roomId));

  // Create room
  rooms.set(roomId, {
    host: ws,
    clients: new Set()
  });

  socketToRoom.set(ws, roomId);

  // Notify host
  ws.send(JSON.stringify({
    type: 'registered',
    roomId: roomId
  }));

  console.log(`Host registered with room ID: ${roomId}`);
}

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

  // Add client to room
  room.clients.add(ws);
  socketToRoom.set(ws, roomId);

  // Notify client
  ws.send(JSON.stringify({
    type: 'joined',
    roomId: roomId
  }));

  console.log(`Client joined room: ${roomId} (${room.clients.size} clients)`);
}

function handleRequest(ws, message) {
  const room = findRoomForSocket(ws);

  if (!room) {
    console.log('Request from client not in a room');
    return;
  }

  // Forward request to host
  if (room.host && room.host.readyState === WebSocket.OPEN) {
    room.host.send(JSON.stringify({
      type: 'request',
      requestId: message.requestId,
      data: message.data
    }));
    console.log(`Forwarded request ${message.requestId} to host`);
  } else {
    // Host not available
    ws.send(JSON.stringify({
      type: 'error',
      requestId: message.requestId,
      message: 'Host not available'
    }));
  }
}

function handleResponse(ws, message) {
  const room = findRoomForSocket(ws);

  if (!room) {
    console.log('Response from host not in a room');
    return;
  }

  // Forward response to all clients in room
  for (const client of room.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'response',
        requestId: message.requestId,
        data: message.data
      }));
    }
  }

  console.log(`Forwarded response ${message.requestId} to ${room.clients.size} clients`);
}

function handleDisconnect(ws) {
  const roomId = socketToRoom.get(ws);

  if (!roomId) {
    console.log('Disconnected socket not in any room');
    return;
  }

  const room = rooms.get(roomId);

  if (!room) {
    return;
  }

  // Check if disconnecting socket is the host
  if (room.host === ws) {
    console.log(`Host disconnected from room: ${roomId}`);

    // Notify all clients
    for (const client of room.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({
          type: 'error',
          message: 'Host disconnected'
        }));
      }
    }

    // Remove room
    rooms.delete(roomId);
    console.log(`Room ${roomId} deleted`);
  } else {
    // Remove client from room
    room.clients.delete(ws);
    console.log(`Client disconnected from room: ${roomId} (${room.clients.size} clients remaining)`);
  }

  socketToRoom.delete(ws);
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
