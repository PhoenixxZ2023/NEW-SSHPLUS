#!/bin/bash
# Script para instalar XRay com suporte opcional ao V2Ray
# Modificado para usar v2ray_util em vez de xray_util
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
        --remove)
            REMOVE=1
            ;;
        *)
            colorEcho ${RED} "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
    shift
done

# Definir variáveis com base no modo
if [[ $V2RAY_MODE == 1 ]]; then
    KEY="v2ray"
    CONFIG_PATH="/etc/v2ray"
    LOG_PATH="/var/log/v2ray"
else
    KEY="xray"
    CONFIG_PATH="/etc/xray"
    LOG_PATH="/var/log/xray"
fi

# Função para verificar e instalar dependências
installDependencies() {
    colorEcho ${BLUE} "Atualizando pacotes..."
    apt-get update
    apt-get install -y bash-completion cron socat ntpdate wget
    if ! pip --version >/dev/null 2>&1; then
        apt-get install -y python3-pip
    fi
}

# Função para sincronizar horário
syncTime() {
    colorEcho ${BLUE} "Sincronizando horário..."
    ntpdate pool.ntp.org
    if [[ $? -eq 0 ]]; then
        colorEcho ${GREEN} "Sincronização de horário bem-sucedida"
        date
    else
        colorEcho ${RED} "Falha na sincronização de horário"
        exit 1
    fi
}

# Função para limpar instalações anteriores
cleanInstall() {
    colorEcho ${BLUE} "Limpando instalações anteriores..."
    systemctl stop ${KEY} >/dev/null 2>&1
    systemctl disable ${KEY} >/dev/null 2>&1
    rm -rf /usr/bin/${KEY} /usr/local/bin/${KEY} ${CONFIG_PATH} ${LOG_PATH}
    rm -f /etc/systemd/system/${KEY}.service
    systemctl daemon-reload >/dev/null 2>&1
}

# Função para instalar v2ray_util
updateProject() {
    colorEcho ${BLUE} "Instalando v2ray_util..."
    pip install -U v2ray_util
    if ! pip show v2ray_util >/dev/null 2>&1; then
        colorEcho ${RED} "Falha ao instalar v2ray_util. Verifique sua instalação do pip e tente novamente."
        exit 1
    fi
    ln -sf $(which v2ray) /usr/local/bin/xray
}

# Função para instalar o XRay/V2Ray
installCore() {
    colorEcho ${BLUE} "Instalando ${KEY^}..."
    GO_SH_URL="https://raw.githubusercontent.com/PhoenixxZ2023/NEW-SSHPLUS/main/Modulos/go.sh"
    if [[ $V2RAY_MODE == 1 ]]; then
        bash <(wget -qO- ${GO_SH_URL}) --v2ray
    else
        bash <(wget -qO- ${GO_SH_URL}) --xray
    fi
    if [[ ! -f /usr/bin/${KEY}/${KEY} ]]; then
        colorEcho ${RED} "Falha ao instalar ${KEY^}. Verifique o script go.sh."
        exit 1
    fi
}

# Função para configurar o serviço
setupService() {
    colorEcho ${BLUE} "Configurando serviço ${KEY}..."
    cat <<EOF >/etc/systemd/system/${KEY}.service
[Unit]
Description=${KEY^} Service
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/${KEY}/${KEY} -config ${CONFIG_PATH}/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${KEY}
}

# Função para configurar o XRay/V2Ray
configureCore() {
    colorEcho ${BLUE} "Configurando ${KEY^}..."
    mkdir -p ${CONFIG_PATH} ${LOG_PATH}
    v2ray new
    if [[ ! -f ${CONFIG_PATH}/config.json ]]; then
        colorEcho ${RED} "Falha ao criar configuração inicial."
        exit 1
    fi
    systemctl start ${KEY}
    colorEcho ${GREEN} "${KEY^} configurado com sucesso!"
    v2ray info
}

# Função para remover o XRay/V2Ray
removeCore() {
    colorEcho ${BLUE} "Removendo ${KEY^}..."
    cleanInstall
    pip uninstall -y v2ray_util >/dev/null 2>&1
    colorEcho ${GREEN} "${KEY^} removido com sucesso!"
    exit 0
}

# Função principal
main() {
    if [[ $REMOVE == 1 ]]; then
        removeCore
    fi
    installDependencies
    syncTime
    cleanInstall
    updateProject
    installCore
    setupService
    configureCore
}

main
