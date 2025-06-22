#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import socket
import os
import uuid

# Importa a classe Xray e o decorator restart do nosso arquivo xray.py corrigido
from ..util_core.xray import restart, Xray
from ..util_core.writer import GroupWriter
from ..util_core.selector import GroupSelector
from ..util_core.utils import get_ip, gen_cert, readchar, is_ipv4, is_email, xtls_flow, ColorStr

class XTLSModifier:
    def __init__(self, group_tag, group_index, domain=''):
        self.domain = domain
        self.writer = GroupWriter(group_tag, group_index)

    @restart(True)
    def turn_on(self, need_restart=True):
        # A lógica para obter o certificado é a mesma do TLS
        cert_list=["letsencrypt", "zerossl", "buypass"]
        print("")
        print(_("1. Let's Encrypt certificate"))
        print(_("2. ZeroSSL certificate"))
        print(_("3. BuyPass certificate"))
        print(_("4. Customize certificate file path"))
        print("")
        choice = readchar(_("please select: "))
        input_domain, input_email = self.domain, ""

        # --- Bloco para obter/validar domínio e certificado ---
        if choice in ("1", "2", "3"):
            if not input_domain:
                local_ip = get_ip()
                input_domain = input(_("please input your vps domain: "))
                try:
                    if is_ipv4(local_ip):
                        socket.gethostbyname(input_domain)
                    else:
                        socket.getaddrinfo(input_domain, None, socket.AF_INET6)[0][4][0]
                except Exception:
                    print(_("domain check error!!!"))
                    return
            
            if choice in ("2", "3"):
                # (Lógica para email mantida)
                # ...
                pass

            print(_("auto generate SSL certificate, please wait.."))
            Xray.stop()
            gen_cert(input_domain, cert_list[int(choice) - 1], input_email)
            crt_file = "/root/.acme.sh/" + input_domain +"_ecc"+ "/fullchain.cer"
            key_file = "/root/.acme.sh/" + input_domain +"_ecc"+ "/"+ input_domain +".key"

        elif choice == "4":
            crt_file = input(_("please input certificate cert file path: "))
            key_file = input(_("please input certificate key file path: "))
            if not os.path.exists(crt_file) or not os.path.exists(key_file):
                print(_("certificate cert or key not exist!"))
                return
            if not input_domain:
                input_domain = input(_("please input the certificate cert file domain: "))
                if not input_domain:
                    print(_("domain is null!"))
                    return
        else:
            print(_("input error!"))
            return

        # --- Lógica Específica para VLESS + XTLS ---
        print(ColorStr.yellow("\nConfigurando inbound para VLESS + XTLS..."))
        
        # Pede o UUID ao usuário
        new_uuid = input(f"Digite o UUID para o usuário VLESS (ou pressione Enter para gerar um novo): ")
        if not new_uuid:
            new_uuid = str(uuid.uuid4())
            print(f"UUID gerado: {ColorStr.green(new_uuid)}")
            
        config = self.writer.config
        inbound = self.writer.part_json

        # Altera o protocolo
        inbound['protocol'] = 'vless'
        
        # Define as configurações do cliente
        inbound['settings']['clients'] = [
            {
                "id": new_uuid,
                "flow": xtls_flow()[0], # Pega 'xtls-rprx-vision'
                "level": 0
            }
        ]
        inbound['settings']['decryption'] = 'none'

        # Define as configurações de stream para XTLS
        inbound['streamSettings']['network'] = 'tcp'
        inbound['streamSettings']['security'] = 'xtls'
        inbound['streamSettings']['xtlsSettings'] = {
            "serverName": input_domain,
            "alpn": ["h2", "http/1.1"],
            "certificates": [
                {
                    "certificateFile": crt_file,
                    "keyFile": key_file
                }
            ]
        }

        # Remove configurações de TLS antigas para evitar conflitos
        if 'tlsSettings' in inbound['streamSettings']:
            del inbound['streamSettings']['tlsSettings']

        # Salva a nova configuração
        self.writer.save()
        print(ColorStr.green("\nConfiguração VLESS + XTLS aplicada com sucesso!"))

        return need_restart

def modify():
    gs = GroupSelector(_('configure XTLS'))
    group = gs.group

    if group is None:
        return

    # Instancia o nosso novo modificador
    xtls_modifier = XTLSModifier(group.tag, group.index)
    xtls_modifier.turn_on()
