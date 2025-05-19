#!/usr/bin/env python3
# encoding: utf-8
# Socks Scott
import socket
import threading
import select
import signal
import sys
import time
from os import system

system("clear")

# Conexão
IP = '0.0.0.0'
try:
    PORT = int(sys.argv[1])
except IndexError:
    PORT = 80
UDP_PORT = 7300  # Porta fixa para UDP
PASS = ''
BUFLEN = 8196
TIMEOUT = 60
MSG = ''
COR = '<font color="null">'
FTAG = '</font>'
DEFAULT_HOST = '0.0.0.0:3478'  # Destino padrão para UDP (ex.: STUN para jogos/chamadas)
RESPONSE = f"HTTP/1.1 200 {COR}{MSG}{FTAG}\r\n\r\n".encode('utf-8')

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
        self.logLock.acquire()
        try:
            print(log)
        finally:
            self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()
            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class UDPServer(threading.Thread):
    def __init__(self, host, port, tcp_server):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port  # Porta 7300
        self.tcp_server = tcp_server  # Referência ao servidor TCP para acessar udp_targets
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.bind((self.host, self.port))
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
            # Obter destino do cliente (definido via TCP ou padrão)
            if client_addr in self.tcp_server.udp_targets:
                host, port = self.tcp_server.udp_targets[client_addr]
            else:
                # Usar destino padrão
                i = DEFAULT_HOST.find(':')
                host = DEFAULT_HOST[:i] if i != -1 else DEFAULT_HOST
                port = int(DEFAULT_HOST[i+1:]) if i != -1 else 3478

            self.printLog(f"UDP Proxy: {client_addr} -> {host}:{port}")

            # Enviar pacote UDP bruto ao destino
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
        self.log = 'Conexão: ' + str(addr)
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
            hostPort = self.findHeader(self.client_buffer.decode('utf-8'), 'X-Real-Host')

            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(self.client_buffer.decode('utf-8'), 'X-Split')

            if split != '':
                self.client.recv(BUFLEN)

            if hostPort != '':
                passwd = self.findHeader(self.client_buffer.decode('utf-8'), 'X-Pass')

                if len(PASS) != 0 and passwd == PASS:
                    # Armazenar destino UDP para o cliente
                    i = hostPort.find(':')
                    host = hostPort[:i] if i != -1 else hostPort
                    port = int(hostPort[i+1:]) if i != -1 else 3478
                    self.server.udp_targets[self.client_addr] = (host, port)
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith(IP):
                    # Armazenar destino UDP para o cliente
                    i = hostPort.find(':')
                    host = hostPort[:i] if i != -1 else hostPort
                    port = int(hostPort[i+1:]) if i != -1 else 3478
                    self.server.udp_targets[self.client_addr] = (host, port)
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - erro: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + ': ')
        if aux == -1:
            return ''
        aux = head.find(':', aux)
        head = head[aux+2:]
        aux = head.find('\r\n')
        if aux == -1:
            return ''
        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 443  # Porta padrão para CONNECT

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE)
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
                                self.client.sendall(data)
                            else:
                                self.target.sendall(data)
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

def main(host=IP, port=PORT):
    print("\033[0;34m━"*8, "\033[1;32m PROXY SOCKS & UDP", "\033[0;34m━"*8)
    print("\033[1;33mIP:\033[1;32m", IP)
    print("\033[1;33mPORTA TCP:\033[1;32m", port)
    print("\033[1;33mPORTA UDP:\033[1;32m", UDP_PORT)
    print("\033[0;34m━"*10, "\033[1;32m SCOTTSSH", "\033[0;34m━"*11)
    
    # Iniciar servidor TCP
    tcp_server = Server(host, port)
    tcp_server.start()

    # Iniciar servidor UDP na porta 7300
    udp_server = UDPServer(host, UDP_PORT, tcp_server)
    udp_server.start()

    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('\nParando...')
            tcp_server.close()
            udp_server.close()
            break

if __name__ == '__main__':
    main()
