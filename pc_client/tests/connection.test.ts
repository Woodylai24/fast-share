import { WebSocket } from 'ws';

describe('WebSocket Connection Logic', () => {
  let ws: WebSocket;
  const WS_PORT = 8080;
  const WS_URL = `ws://localhost:${WS_PORT}`;

  afterEach(() => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.close();
    }
  });

  test('should connect to the WebSocket server', (done) => {
    ws = new WebSocket(WS_URL);

    ws.on('open', () => {
      expect(ws.readyState).toBe(WebSocket.OPEN);
      done();
    });

    ws.on('error', (err) => {
      done(err);
    });
  });

  test('should receive handshake from server on connection', (done) => {
    ws = new WebSocket(WS_URL);

    ws.on('message', (data) => {
      const message = JSON.parse(data.toString());
      if (message.type === 'handshake') {
        expect(message.message).toBe('Connected to PC');
        done();
      }
    });

    ws.on('error', (err) => {
      done(err);
    });
  });

  test('should handle handshake from mobile client', (done) => {
    ws = new WebSocket(WS_URL);

    ws.on('open', () => {
      const handshake = {
        type: 'handshake',
        deviceId: 'test-device-id',
        device: 'Test Device'
      };
      ws.send(JSON.stringify(handshake));
      
      // Since the server doesn't send a specific response to mobile handshake 
      // (it just logs it and forwards a generic message to renderer),
      // we just verify we don't get an error.
      setTimeout(() => {
        expect(ws.readyState).toBe(WebSocket.OPEN);
        done();
      }, 500);
    });

    ws.on('error', (err) => {
      done(err);
    });
  });
});
