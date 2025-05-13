#!/bin/bash
# Script para instalar XRay ou V2Ray
# @TURBONET2023

# Função para exibir mensagens coloridas
colorEcho() {
    COLOR=$1
    echo -e "\033[0;${COLOR}m${@:2}\033[0m"
}

# Definir cores
BLUE="34"
RED="31"
GREEN="32"

# Processar parâmetros
V2RAY_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --v2ray)
            V2RAY_MODE=1
            colorEcho ${BLUE} "Modo V2Ray ativado"
            ;;
        *)
            colorEcho ${RED} "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
    shift
done

# Definir variáveis
if [[ $V2RAY_MODE == 1 ]]; then
    KEY="v2ray"
    BIN_PATH="/usr/bin/v2ray"
    CONFIG_PATH="/etc/v2ray"
    LOG_PATH="/var/log/v2ray"
    DOWNLOAD_URL="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip"
else
    KEY="xray"
    BIN_PATH="/usr/bin/xray"
    CONFIG_PATH="/etc/xray"
    LOG_PATH="/var/log/xray"
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v25.4.30/Xray-linux-64.zip"
fi

# Função para instalar dependências
installDependencies() {
    colorEcho ${BLUE} "Instalando dependências..."
    apt-get update
    apt-get install -y wget unzip coreutils
}

# Função para baixar e instalar o binário
installCore() {
    colorEcho ${BLUE} "Baixando ${KEY^}..."
    mkdir -p ${BIN_PATH} ${CONFIG_PATH} ${LOG_PATH}
    wget -O /tmp/${KEY}.zip "${DOWNLOAD_URL}"
    if [[ $? -ne 0 ]]; then
        colorEcho ${RED} "Falha ao baixar ${KEY^}."
        exit 1
    fi
    unzip /tmp/${KEY}.zip -d ${BIN_PATH}
    if [[ $V2RAY_MODE == 1 ]]; then
        mv ${BIN_PATH}/v2ray ${BIN_PATH}/${KEY}
        mv ${BIN_PATH}/v2ctl ${BIN_PATH}/${KEY}-ctl
    else
        mv ${BIN_PATH}/xray ${BIN_PATH}/${KEY}
    fi
    chmod +x ${BIN_PATH}/${KEY}
    rm -f /tmp/${KEY}.zip
    colorEcho ${GREEN} "${KEY^} instalado com sucesso!"
}

# Função principal
main() {
    installDependencies
    installCore
}

main
