#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import socket
import os
import sys # Importar sys para ler argumentos
import uuid

from ..util_core.xray import restart, Xray
from ..util_core.writer import GroupWriter
from ..util_core.selector import GroupSelector
from ..util_core.utils import get_ip, gen_cert, readchar, is_ipv4, is_email, xtls_flow, ColorStr

class XTLSModifier:
    # ... (o conteúdo da classe XTLSModifier continua o mesmo) ...
    def __init__(self, group_tag, group_index, domain=''):
        self.domain = domain
        self.writer = GroupWriter(group_tag, group_index)

    @restart(True)
    def turn_on(self, need_restart=True, domain_arg=None, uuid_arg=None): # Adicionados argumentos opcionais
        # ... (a lógica para escolher o tipo de certificado continua a mesma) ...
        cert_list=["letsencrypt", "zerossl", "buypass"]
        
        # Se os argumentos não foram passados, o script se torna interativo
        if domain_arg is None and uuid_arg is None:
            print("")
            print(_("1. Let's Encrypt certificate"))
            print(_("2. ZeroSSL certificate"))
            print(_("3. BuyPass certificate"))
            print(_("4. Customize certificate file path"))
            print("")
            choice = readchar(_("please select: "))
            # ... (toda a lógica interativa para pedir domínio, certificado, etc. continua aqui) ...

        # Se os argumentos foram passados, o script se torna automático
        else:
            choice = '1' # Assume Let's Encrypt por padrão no modo automático
            input_domain = domain_arg
            new_uuid = uuid_arg
            print(f"Modo automático: usando domínio '{input_domain}' e UUID '{new_uuid}'")
            
            print(_("auto generate SSL certificate, please wait.."))
            Xray.stop()
            gen_cert(input_domain, cert_list[int(choice) - 1])
            crt_file = "/root/.acme.sh/" + input_domain +"_ecc"+ "/fullchain.cer"
            key_file = "/root/.acme.sh/" + input_domain +"_ecc"+ "/"+ input_domain +".key"


        # --- Lógica Específica para VLESS + XTLS (agora usa as variáveis certas) ---
        print(ColorStr.yellow("\nConfigurando inbound para VLESS + XTLS..."))
        
        # Se estiver no modo interativo, pede o UUID
        if uuid_arg is None:
            new_uuid = input(f"Digite o UUID para o usuário VLESS (ou pressione Enter para gerar um novo): ")
            if not new_uuid:
                new_uuid = str(uuid.uuid4())
                print(f"UUID gerado: {ColorStr.green(new_uuid)}")
        
        config = self.writer.config
        inbound = self.writer.part_json

        inbound['port'] = 443
        inbound['protocol'] = 'vless'
        inbound['settings']['clients'] = [{"id": new_uuid, "flow": xtls_flow()[0], "level": 0}]
        inbound['settings']['decryption'] = 'none'
        inbound['streamSettings']['network'] = 'tcp'
        inbound['streamSettings']['security'] = 'xtls'
        inbound['streamSettings']['xtlsSettings'] = {
            "serverName": input_domain,
            "alpn": ["h2", "http/1.1"],
            "certificates": [{"certificateFile": crt_file, "keyFile": key_file}]
        }
        if 'tlsSettings' in inbound['streamSettings']:
            del inbound['streamSettings']['tlsSettings']

        self.writer.save()
        print(ColorStr.green("\nConfiguração VLESS + XTLS aplicada com sucesso!"))
        return need_restart

def modify():
    # Verifica se os argumentos foram passados pela linha de comando
    if len(sys.argv) > 2:
        domain = sys.argv[1]
        uuid = sys.argv[2]
        # Encontra o primeiro grupo para aplicar a configuração
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
        if group is None:
            return
        xtls_modifier = XTLSModifier(group.tag, group.index)
        xtls_modifier.turn_on()
