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
DEFAULT_HOST = "127.0.0.1:3478"  # Destino padrão para UDP/TCP (ex.: STUN)
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
        self.udp_targets = {}  # Mapeia cliente (addr) para destino UDP (host, port)
        self.udp_servers = {}  # Mapeia portas UDP para instâncias de UDPServer

    def run(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
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
            # Fechar todos os servidores UDP
            for udp_server in self.udp_servers.values():
                udp_server.close()

class UDPServer(threading.Thread):
    def __init__(self, host, port, tcp_server):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port  # Porta UDP do destino
        self.tcp_server = tcp_server
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.soc.bind((self.host, self.port))
        except Exception as e:
            self.printLog(f"Erro ao vincular porta {self.port}: {str(e)}")
            return
        self.running = True

        try:
            while self.running:
                try:
                    data, client_addr = self.soc.recvfrom(BUFLEN)
                    self.handle_udp_data(data, client_addr)
                except socket.timeout:
                    continue
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        with self.logLock:
            print(log)

    def handle_udp_data(self, data, client_addr):
        try:
            # Obter destino do cliente
            if client_addr in self.tcp_server.udp_targets:
                host, port = self.tcp_server.udp_targets[client_addr]
            else:
                # Usar destino padrão
                i = DEFAULT_HOST.find(':')
                host = DEFAULT_HOST[:i] if i != -1 else DEFAULT_HOST
                port = int(DEFAULT_HOST[i+1:]) if i != -1 else 3478

            self.printLog(f"UDP Proxy: {client_addr} -> {host}:{port}")

            # Enviar pacote UDP ao destino
            target_soc = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            target_soc.sendto(data, (host, port))

            # Receber resposta do destino e encaminhar ao cliente
            target_soc.settimeout(2)
            try:
                response, _ = target_soc.recvfrom(BUFLEN)
                self.soc.sendto(response, client_addr)
            except socket.timeout:
                pass
            finally:
                target_soc.close()

        except Exception as e:
            self.printLog(f"UDP error from {client_addr}: {str(e)}")

    def close(self):
        self.running = False
        self.soc.close()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)
        self.client_addr = addr

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
        
            # Extrair o método HTTP, caminho e versão
            first_line = self.client_buffer.split(b'\n')[0]
            try:
                method, uri, _ = first_line.split(b' ')
                method = method.decode()
            except:
                self.client.send(b'HTTP/1.1 400 Bad Request!\r\n\r\n')
                return

            # Extrair host de X-Real-Host
            hostPort = self.findHeader(self.client_buffer, b'X-Real-Host')
            if hostPort == b'':
                hostPort = DEFAULT_HOST.encode()

            # Separar cabeçalhos e corpo
            headers_end = self.client_buffer.find(b'\r\n\r\n')
            headers = self.client_buffer[:headers_end + 2] if headers_end != -1 else self.client_buffer
            body = self.client_buffer[headers_end + 4:] if headers_end != -1 else b''

            split = self.findHeader(self.client_buffer, b'X-Split')
            if split != b'':
                self.client.recv(BUFLEN)
            
            if hostPort != b'':
                passwd = self.findHeader(self.client_buffer, b'X-Pass')
                
                if len(PASS) != 0 and passwd.decode() == PASS:
                    # Armazenar destino UDP para o cliente
                    i = hostPort.decode().find(':')
                    host = hostPort.decode()[:i] if i != -1 else hostPort.decode()
                    port = int(hostPort.decode()[i+1:]) if i != -1 else 3478
                    self.server.udp_targets[self.client_addr] = (host, port)

                    # Iniciar UDPServer para a porta do destino, se necessário
                    with self.server.threadsLock:
                        if port not in self.server.udp_servers:
                            udp_server = UDPServer(LISTENING_ADDR, port, self.server)
                            udp_server.start()
                            self.server.udp_servers[port] = udp_server
                            self.server.printLog(f"Iniciando UDPServer na porta {port}")

                    if method == 'CONNECT':
                        self.method_CONNECT(hostPort.decode())
                    else:
                        self.method_HTTP(hostPort.decode(), method, uri.decode(), headers, body)
                elif len(PASS) != 0 and passwd.decode() != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.decode().startswith('127.0.0.1') or hostPort.decode().startswith('localhost'):
                    # Armazenar destino UDP para o cliente
                    i = hostPort.decode().find(':')
                    host = hostPort.decode()[:i] if i != -1 else hostPort.decode()
                    port = int(hostPort.decode()[i+1:]) if i != -1 else 3478
                    self.server.udp_targets[self.client_addr] = (host, port)

                    # Iniciar UDPServer para a porta do destino, se necessário
                    with self.server.threadsLock:
                        if port not in self.server.udp_servers:
                            udp_server = UDPServer(LISTENING_ADDR, port, self.server)
                            udp_server.start()
                            self.server.udp_servers[port] = udp_server
                            self.server.printLog(f"Iniciando UDPServer na porta {port}")

                    if method == 'CONNECT':
                        self.method_CONNECT(hostPort.decode())
                    else:
                        self.method_HTTP(hostPort.decode(), method, uri.decode(), headers, body)
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
            port = 80  # Porta padrão para HTTP

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def websocket_handshake(self):
        key = self.findHeader(self.client_buffer, b'Sec-WebSocket-Key').decode()
        if not key:
            self.client.send(b'HTTP/1.1 400 Bad Request\r\n\r\n')
            return False
        
        accept_key = base64.b64encode(
            hashlib.sha1(key.encode() + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest()
        ).decode()
        response = RESPONSE.replace(b'{key}', accept_key.encode())
        self.client.sendall(response)
        return True

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        
        self.connect_target(path)
        if not self.websocket_handshake():
            self.close()
            return
        
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def method_HTTP(self, host, method, uri, headers, body):
        self.log += f' - {method} {uri}'
        
        # Conectar ao servidor remoto
        self.connect_target(host)
        
        # Reconstruir a requisição HTTP
        request_line = f"{method} {uri} HTTP/1.1\r\n".encode()
        headers_str = headers.decode()
        if b'Host:' not in headers:
            headers_str += f"Host: {host}\r\n"
        full_request = request_line + headers_str.encode() + b"\r\n" + body
        
        # Enviar a requisição ao servidor remoto
        self.target.sendall(full_request)
        
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doHTTP()

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

    def doHTTP(self):
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
                                self.target.send(data)
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
    print('Uso: proxy.py -p <porta_tcp>')
    print('       proxy.py -b <ip> -p <porta_tcp>')
    print('Exemplo: proxy.py -b 0.0.0.0 -p 80')

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
    print("\033[0;34m━"*8, "\033[1;32m PROXY WEBSOCKET & UDP", "\033[0;34m━"*8)
    print("\033[1;33mIP:\033[1;32m " + LISTENING_ADDR)
    print("\033[1;33mPORTA TCP:\033[1;32m " + str(LISTENING_PORT))
    print("\033[0;34m━"*10, "\033[1;32m VPSMANAGER", "\033[0;34m━\033[1;37m"*11)
    
    # Iniciar servidor TCP
    tcp_server = Server(LISTENING_ADDR, LISTENING_PORT)
    tcp_server.start()

    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Parando...')
            tcp_server.close()
            break

if __name__ == '__main__':
    parse_args(sys.argv[1:])
    main()
