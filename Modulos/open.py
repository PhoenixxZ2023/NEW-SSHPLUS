#!/usr/bin/env python3
# encoding: utf-8
import socket
import threading
import select
import signal
import sys
import time
import logging
from os import system
from configparser import ConfigParser

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('proxy.log')
    ]
)
logger = logging.getLogger(__name__)

# Carregar configurações de um arquivo (se existir) ou usar padrões
config = ConfigParser()
config.read('proxy.ini')
IP = config.get('DEFAULT', 'IP', fallback='0.0.0.0')
try:
    PORT = int(config.get('DEFAULT', 'PORT', fallback=sys.argv[1] if len(sys.argv) > 1 else '8080'))
except ValueError:
    PORT = 8080
PASS = config.get('DEFAULT', 'PASS', fallback='')
BUFLEN = int(config.get('DEFAULT', 'BUFLEN', fallback='8196'))
TIMEOUT = int(config.get('DEFAULT', 'TIMEOUT', fallback='60'))
MSG = config.get('DEFAULT', 'MSG', fallback='ALERT')
DEFAULT_HOST = config.get('DEFAULT', 'DEFAULT_HOST', fallback='0.0.0.0:1194')
RESPONSE = f"HTTP/1.1 101 {MSG}\r\n\r\n"

system("clear")

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
        try:
            self.soc.bind((self.host, self.port))
            self.soc.listen(0)
            self.running = True
            logger.info(f"Servidor iniciado em {self.host}:{self.port}")
        except socket.error as e:
            logger.error(f"Erro ao iniciar o servidor: {e}")
            return

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                except socket.error as e:
                    logger.error(f"Erro ao aceitar conexão: {e}")
                    continue
                
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.close()

    def printLog(self, log):
        with self.logLock:
            logger.info(log)
    
    def addConn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.append(conn)
                    
    def removeConn(self, conn):
        with self.threadsLock:
            if conn in self.threads:
                self.threads.remove(conn)
                
    def close(self):
        self.running = False
        with self.threadsLock:
            for conn in list(self.threads):
                conn.close()
        if hasattr(self, 'soc'):
            try:
                self.soc.close()
            except socket.error as e:
                logger.error(f"Erro ao fechar socket do servidor: {e}")
        logger.info("Servidor encerrado")

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = ''
        self.server = server
        self.log = f'Conexão: {addr}'
        self.method = 'CONNECT'

    def close(self):
        try:
            if not self.clientClosed:
                try:
                    self.client.shutdown(socket.SHUT_RDWR)
                    self.client.close()
                except socket.error as e:
                    logger.error(f"Erro ao fechar socket do cliente: {e}")
                finally:
                    self.clientClosed = True
            
            if not self.targetClosed:
                try:
                    self.target.shutdown(socket.SHUT_RDWR)
                    self.target.close()
                except socket.error as e:
                    logger.error(f"Erro ao fechar socket do destino: {e}")
                finally:
                    self.targetClosed = True
        except Exception as e:
            logger.error(f"Erro inesperado ao fechar conexão: {e}")

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN).decode('utf-8', errors='ignore')
        
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            
            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(self.client_buffer, 'X-Split')

            if split != '':
                self.client.recv(BUFLEN)
            
            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')
                
                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send('HTTP/1.1 400 WrongPass!\r\n\r\n'.encode())
                elif hostPort.startswith(IP):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send('HTTP/1.1 403 Forbidden!\r\n\r\n'.encode())
            else:
                logger.warning('Nenhum X-Real-Host fornecido')
                self.client.send('HTTP/1.1 400 NoXRealHost!\r\n\r\n'.encode())

        except socket.error as e:
            self.log += f' - erro de socket: {e}'
            self.server.printLog(self.log)
        except Exception as e:
            self.log += f' - erro inesperado: {e}'
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        try:
            aux = head.find(header + ': ')
            if aux == -1:
                return ''
            aux = head.find(':', aux)
            head = head[aux+2:]
            aux = head.find('\r\n')
            if aux == -1:
                return ''
            return head[:aux]
        except Exception as e:
            logger.error(f"Erro ao analisar cabeçalho {header}: {e}")
            return ''

    def connect_target(self, host):
        try:
            i = host.find(':')
            if i != -1:
                port = int(host[i+1:])
                host = host[:i]
            else:
                port = 443 if self.method == 'CONNECT' else 22

            if not (1 <= port <= 65535):
                raise ValueError("Número de porta inválido")

            (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
            self.target = socket.socket(soc_family, soc_type, proto)
            self.target.settimeout(5)
            self.target.connect(address)
            self.targetClosed = False
        except (ValueError, socket.gaierror, socket.timeout) as e:
            logger.error(f"Erro ao conectar ao destino {host}:{port}: {e}")
            self.client.send(f'HTTP/1.1 400 Host Inválido: {str(e)}\r\n\r\n'.encode())
            raise

    def method_CONNECT(self, path):
        self.log += f' - CONNECT {path}'
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = ''
        self.server.printLog(self.log)
        self.doCONNECT()
                    
    def doCONNECT(self):
        socs = [self.client, self.target]
        start_time = time.time()
        while True:
            try:
                recv, _, err = select.select(socs, [], socs, 3)
                if err:
                    logger.error(f"Erro de socket detectado: {err}")
                    break
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
                                start_time = time.time()
                            else:
                                break
                        except socket.error as e:
                            logger.error(f"Erro ao processar dados: {e}")
                            return
                if time.time() - start_time >= TIMEOUT:
                    logger.warning("Conexão expirada por inatividade")
                    break
            except Exception as e:
                logger.error(f"Erro inesperado em doCONNECT: {e}")
                break

def main(host=IP, port=PORT):
    print("\033[0;34m━"*8, "\033[1;32m PROXY SOCKS", "\033[0;34m━"*8, "\n")
    print(f"\033[1;33mIP:\033[1;32m {IP}")
    print(f"\033[1;33mPORTA:\033[1;32m {port}\n")
    print("\033[0;34m━"*10, "\033[1;32m SSHPLUS", "\033[0;34m━\033[1;37m"*11, "\n")
    
    server = Server(IP, PORT)
    server.start()

    def signal_handler(sig, frame):
        print('\nParando...')
        server.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        while True:
            time.sleep(2)
    except KeyboardInterrupt:
        print('\nParando...')
        server.close()

if __name__ == '__main__':
    main()
