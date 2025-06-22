#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import gettext
import pkg_resources

lang = 'en'
# MODIFICAÇÃO 1: Corrigido o caminho para o arquivo de configuração.
if os.path.exists('/etc/xray_util/util.cfg'):
    from .config import Config
    lang = Config().get_data('lang')

if lang == 'zh':
    # MODIFICAÇÃO 2: Corrigido o nome do pacote para encontrar a pasta de tradução.
    trans = gettext.translation('lang', pkg_resources.resource_filename('xray_util', 'locale_i18n'), languages=['zh_CH'])
else:
    # MODIFICAÇÃO 3: Corrigido o nome do pacote para encontrar a pasta de tradução.
    trans = gettext.translation('lang', pkg_resources.resource_filename('xray_util', 'locale_i18n'), languages=['en_US'])
trans.install()
_ = trans.gettext
