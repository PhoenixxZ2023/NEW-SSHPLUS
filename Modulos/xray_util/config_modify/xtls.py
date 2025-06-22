#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import socket
import os
import sys
import uuid

from ..util_core.xray import restart, Xray
from ..util_core.writer import GroupWriter
from ..util_core.selector import GroupSelector
from ..util_core.utils import get_ip, gen_cert, readchar, is_ipv4, is_email, xtls_flow, ColorStr

class XTLSModifier:
    def __init__(self, group_tag, group_index, domain=''):
        self.domain = domain
        self.writer = GroupWriter(group_tag, group_index)

    @restart(True)
    def turn_on(self, need_restart=True, domain_arg=None, uuid_arg=None):
        # Se os argumentos foram passados, entra no modo automático
        if domain_arg and uuid_arg:
            print(f"Modo automático: usando domínio '{domain_arg}' e UUID '{uuid_arg}'")
            choice = '1' # Assume Let's Encrypt por padrão
            input_domain = domain_arg
            new_uuid = uuid_arg
            
            print(_("auto generate SSL certificate, please wait.."))
            Xray.stop()
            gen_cert(input_domain, "letsencrypt")
            crt_file = f"/root/.acme.sh/{input_domain}_ecc/fullchain.cer"
            key_file = f"/root/.acme.sh/{input_domain}_ecc/{input_domain}.key"

        # Senão, entra no modo interativo
        else:
            cert_list=["letsencrypt", "zerossl", "buypass"]
            print("")
            print(_("1. Let's Encrypt certificate"))
            print(_("2. ZeroSSL certificate"))
            print(_("3. BuyPass certificate"))
            print(_("4. Customize certificate file path"))
            print("")
            choice = readchar(_("please select: "))
            input_domain, input_email = self.domain, ""

            if choice in ("1", "2", "3"):
                # ... (lógica interativa para obter certificado) ...
                if not input_domain:
                    input_domain = input(_("please input your vps domain: "))
                # ...
                Xray.stop()
                gen_cert(input_domain, cert_list[int(choice) - 1], input_email)
                crt_file = f"/root/.acme.sh/{input_domain}_ecc/fullchain.cer"
                key_file = f"/root/.acme.sh/{input_domain}_ecc/{input_domain}.key"
            elif choice == "4":
                # ... (lógica para caminho customizado) ...
                crt_file = input(_("please input certificate cert file path: "))
                key_file = input(_("please input certificate key file path: "))
                if not input_domain:
                    input_domain = input(_("please input the certificate cert file domain: "))
            else:
                print(_("input error!"))
                return
            
            new_uuid = input(f"Digite o UUID para o usuário VLESS (ou pressione Enter para gerar um novo): ")
            if not new_uuid:
                new_uuid = str(uuid.uuid4())
                print(f"UUID gerado: {ColorStr.green(new_uuid)}")

        # --- Lógica Comum para Configurar o JSON ---
        if not os.path.exists(crt_file) or not os.path.exists(key_file):
            print(ColorStr.red(f"ERRO: Arquivos de certificado não encontrados após a geração! Verifique o log do acme.sh."))
            Xray.start() # Tenta reiniciar o Xray para não deixar o serviço parado
            return
            
        print(ColorStr.yellow("\nConfigurando inbound para VLESS + XTLS..."))
        
        inbound = self.writer.part_json
        inbound['port'] = 443
        inbound['protocol'] = 'vless'
        inbound['settings']['clients'] = [{"id": new_uuid, "flow": xtls_flow()[0], "level": 0}]
        inbound['settings']['decryption'] = 'none'
        inbound['streamSettings']['network'] = 'tcp'
        inbound['streamSettings']['security'] = 'xtls'
        inbound['streamSettings']['xtlsSettings'] = {
            "serverName": input_domain, "alpn": ["h2", "http/1.1"],
            "certificates": [{"certificateFile": crt_file, "keyFile": key_file}]
        }
        if 'tlsSettings' in inbound['streamSettings']:
            del inbound['streamSettings']['tlsSettings']

        self.writer.save()
        print(ColorStr.green("\nConfiguração VLESS + XTLS aplicada com sucesso!"))
        return need_restart

def modify():
    # Detecta se foi chamado com argumentos para o modo automático
    # Ex: xray xtls-direct dominio.com uuid
    if len(sys.argv) > 3 and sys.argv[1] == 'xtls-direct':
        domain = sys.argv[2]
        uuid = sys.argv[3]
        from ..util_core.loader import Loader
        profile = Loader().profile
        if not profile.group_list:
            print(ColorStr.red("Nenhum grupo de inbound encontrado para configurar."))
            return
        group = profile.group_list[0]
        xtls_modifier = XTLSModifier(group.tag, group.index)
        xtls_modifier.turn_on(domain_arg=domain, uuid_arg=uuid)
    else:
        # Lógica interativa original
        gs = GroupSelector(_('configure XTLS'))
        group = gs.group
        if group is None: return
        xtls_modifier = XTLSModifier(group.tag, group.index)
        xtls_modifier.turn_on()
