#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from ..util_core.loader import Loader
# MODIFICAÇÃO ÚNICA: Corrigido o nome do arquivo importado de 'v2ray' para 'xray'.
from ..util_core.xray import restart
from ..util_core.writer import GlobalWriter
from ..util_core.utils import readchar

@restart()
def manage():
    loader = Loader()

    profile = loader.profile

    print("{}: {}".format(_("Ban BT status"), profile.ban_bt))

    choice = readchar(_("Ban BT?(y/n): ")).lower()

    if not choice:
        return

    ban_bt = True if choice == 'y' else False

    gw = GlobalWriter(profile.group_list)

    gw.write_ban_bittorrent(ban_bt)

    print(_("modify success!"))
    
    return True
