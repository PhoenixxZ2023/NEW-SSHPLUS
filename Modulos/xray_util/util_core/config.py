#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import pkg_resources
import configparser
# MODIFICAÇÃO 1: Corrigido o nome do pacote importado
from xray_util import run_type

# MODIFICAÇÃO 2: Atualizado o caminho do arquivo de configuração
CONF_FILE = '/etc/xray_util/util.cfg'
# MODIFICAÇÃO 3: Lógica simplificada, pois o run_type será sempre 'xray'
DATA_FILE = 'xray.dat'

class Config:

    def __init__(self):
        self.config = configparser.ConfigParser()
        self.config_path = CONF_FILE
        # MODIFICAÇÃO 4: Atualizadas as referências internas ao nome do pacote
        self.data_path = pkg_resources.resource_filename('xray_util', DATA_FILE)
        self.json_path = pkg_resources.resource_filename('xray_util', "json_template")
        self.config.read(self.config_path)

    def get_path(self, key):
        if key == 'config_path' and run_type == 'xray':
            return '/etc/xray/config.json'
        return self.config.get('path', key)

    def get_data(self, key):
        return self.config.get('data', key)

    def set_data(self, key, value):
        self.config.set('data', key, value)
        self.config.write(open(self.config_path, "w"))
