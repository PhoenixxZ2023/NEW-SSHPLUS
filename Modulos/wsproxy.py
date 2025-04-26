#!/usr/bin/env python3
# encoding: utf-8
import socket
import threading
import select
import sys
import time
import getopt
import base64
import hashlib

PASS = ''
LISTENING_ADDR = '0.0.0.0'
try:
    LISTENING_PORT = int(sys.argv[1])
except:
    LISTENING_PORT = 80
BUFLEN = 4096 * 2
TIMEOUT = 60
MSG = ''
COR = '<font color="null">'
FTAG = '</font>'
DEFAULT_HOST = "127.0.0.1:22"
RESPONSE = b"HTTP/1.1 101 Switching Protocols\r\n" \
           b"Upgrade: websocket\r\n" \
           b"Connection: Upgrade\r\n" \
           b"Sec-WebSocket-Accept: {key}\r\n\r\n"

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()
            
    def printLog(self, log):
        with self.logLock:
            print(log)
	
    def addConn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.append(conn)
                    
    def removeConn(self, conn):
        with self.threadsLock:
            self.threads.remove(conn)
                
    def close(self):
        self.running = False
        with self.threadsLock:
            threads = list(self.threads)
            for c in threads:
                c.close()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
            
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
        
            hostPort = self.findHeader(self.client_buffer, b'X-Real-Host')
            if hostPort == b'':
                hostPort = DEFAULT_HOST.encode()

            split = self.findHeader(self.client_buffer, b'X-Split')
            if split != b'':
                self.client.recv(BUFLEN)
            
            if hostPort != b'':
                passwd = self.findHeader(self.client_buffer, b'X-Pass')
				
                if len(PASS) != 0 and passwd.decode() == PASS:
                    self.method_CONNECT(hostPort.decode())
                elif len(PASS) != 0 and passwd.decode() != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.decode().startswith('127.0.0.1') or hostPort.decode().startswith('localhost'):
                    self.method_CONNECT(hostPort.decode())
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + b': ')
        if aux == -1:
            return b''

        aux = head.find(b':', aux)
        head = head[aux+2:]
        aux = head.find(b'\r\n')

        if aux == -1:
            return b''

        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 443

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def websocket_handshake(self):
        # Extrai a chave WebSocket do cabeçalho do cliente
        key = self.findHeader(self.client_buffer, b'Sec-WebSocket-Key').decode()
        if not key:
            self.client.send(b'HTTP/1.1 400 Bad Request\r\n\r\n')
            return False
        
        # Gera a resposta do handshake WebSocket
        accept_key = base64.b64encode(
            hashlib.sha1(key.encode() + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest()
        ).decode()
        response = RESPONSE.replace(b'{key}', accept_key.encode())
        self.client.sendall(response)
        return True

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        
        self.connect_target(path)
        if not self.websocket_handshake():  # Realiza o handshake WebSocket
            self.close()
            return
        
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break

def print_usage():
    print('Use: proxy.py -p <port>')
    print('       proxy.py -b <ip> -p <porta>')
    print('       proxy.py -b 0.0.0.0 -p 22')

def parse_args(argv):
    global LISTENING_ADDR, LISTENING_PORT
    try:
        opts, args = getopt.getopt(argv, "hb:p:", ["bind=", "port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)

def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\033[0;34m━"*8, "\033[1;32m PROXY WEBSOCKET", "\033[0;34m━"*8)
    print("\033[1;33mIP:\033[1;32m " + LISTENING_ADDR)
    print("\033[1;33mPORTA:\033[1;32m " + str(LISTENING_PORT))
    print("\033[0;34m━"*10, "\033[1;32m VPSMANAGER", "\033[0;34m━\033[1;37m"*11)
    
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()

    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Parando...')
            server.close()
            break

if __name__ == '__main__':
    parse_args(sys.argv[1:])
    main()
