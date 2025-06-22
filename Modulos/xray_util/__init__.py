__version__ = '3.11.4'

# MODIFICAÇÃO: Definindo 'xray' como o tipo de execução padrão.
# Removemos a lógica antiga que também suportava 'v2ray' para focar apenas em Xray.
run_type = 'xray'

# Importa a função de tradução, que é usada em outras partes do painel.
from .util_core.trans import _
