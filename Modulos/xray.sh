#!/bin/bash
# EDIT: @TURBONET2023
# github: https://github.com/PhoenixxZ2023/NEW-SSHPLUS

# Horário de execução da tarefa agendada (horário de Pequim, 0~23)
BEIJING_UPDATE_TIME=3

# Registrar o caminho inicial do script
BEGIN_PATH=$(pwd)

# Modo de instalação: 0 para instalação nova, 1 para atualização mantendo configuração
INSTALL_WAY=0

# Variáveis de controle: 0 para não, 1 para sim
HELP=0
REMOVE=0
CHINESE=0
V2RAY_MODE=0  # 0 para XRay (padrão), 1 para V2Ray

# URLs base para recursos
BASE_SOURCE_PATH="https://multi.netlify.app"

# Caminhos para utilitários do XRay
UTIL_PATH="/etc/xray_util/util.cfg"
UTIL_CFG="$BASE_SOURCE_PATH/xray_util/util_core/util.cfg"
BASH_COMPLETION_SHELL="$BASE_SOURCE_PATH/xray"
CLEAN_IPTABLES_SHELL="$BASE_SOURCE_PATH/xray_util/global_setting/clean_iptables.sh"

# URL do go.sh hospedado no GitHub
GO_SH_URL="https://raw.githubusercontent.com/PhoenixxZ2023/NEW-SSHPLUS/main/Modulos/go.sh"

# Cancelar temporariamente aliases no CentOS
[[ -f /etc/redhat-release && -z $(echo $SHELL|grep zsh) ]] && unalias -a

# Definir arquivo de ambiente baseado no shell
[[ -z $(echo $SHELL|grep zsh) ]] && ENV_FILE=".bashrc" || ENV_FILE=".zshrc"

####### Códigos de cor #######
RED="31m"    # Mensagem de erro
GREEN="32m"  # Mensagem de sucesso
YELLOW="33m" # Mensagem de aviso
BLUE="36m"   # Mensagem informativa
FUCHSIA="35m"

colorEcho(){
    COLOR=$1
    echo -e "\033[${COLOR}${@:2}\033[0m"
}

####### Processar parâmetros #######
while [[ $# > 0 ]]; do
    key="$1"
    case $key in
        --remove)
        REMOVE=1
        ;;
        -h|--help)
        HELP=1
        ;;
        -k|--keep)
        INSTALL_WAY=1
        colorEcho ${BLUE} "Manter configuração para atualização\n"
        ;;
        --zh)
        CHINESE=1
        colorEcho ${BLUE} "Instalando versão em chinês..\n"
        ;;
        --v2ray)
        V2RAY_MODE=1
        colorEcho ${BLUE} "Instalando V2Ray em vez de XRay\n"
        ;;
        *)
                # Opção desconhecida
        ;;
    esac
    shift
done
#############################

help(){
    echo "bash xray.sh [-h|--help] [-k|--keep] [--remove] [--v2ray]"
    echo "  -h, --help           Exibir ajuda"
    echo "  -k, --keep           Manter o config.json para atualização"
    echo "      --remove         Remover XRay (ou V2Ray com --v2ray)"
    echo "      --v2ray          Instalar V2Ray em vez de XRay"
    echo "                       Sem parâmetros para instalar XRay"
    return 0
}

removeCore() {
    # Definir variáveis com base no modo (XRay ou V2Ray)
    if [[ $V2RAY_MODE == 1 ]]; then
        KEY="v2ray"
        CONFIG_PATH="/etc/v2ray"
        LOG_PATH="/var/log/v2ray"
        GO_PARAM=""
    else
        KEY="xray"
        CONFIG_PATH="/etc/xray"
        LOG_PATH="/var/log/xray"
        GO_PARAM="--xray"
    fi

    # Parar e desativar o serviço
    systemctl stop $KEY >/dev/null 2>&1
    systemctl disable $KEY >/dev/null 2>&1

    # Remover usando go.sh
    bash <(curl -L -s "$GO_SH_URL") --remove $GO_PARAM >/dev/null 2>&1

    # Limpar arquivos de configuração e logs
    rm -rf $CONFIG_PATH >/dev/null 2>&1
    rm -rf $LOG_PATH >/dev/null 2>&1

    # Limpar regras de iptables
    bash <(curl -L -s $CLEAN_IPTABLES_SHELL) >/dev/null 2>&1

    # Remover utilitários
    pip uninstall xray_util -y >/dev/null 2>&1
    rm -rf /usr/share/bash-completion/completions/$KEY >/dev/null 2>&1
    rm -rf /etc/bash_completion.d/$KEY.bash >/dev/null 2>&1
    rm -rf /usr/local/bin/$KEY >/dev/null 2>&1
    rm -rf /etc/xray_util >/dev/null 2>&1

    # Remover tarefas cron
    crontab -l | sed "/$KEY/d" > crontab.txt
    crontab crontab.txt >/dev/null 2>&1
    rm -f crontab.txt >/dev/null 2>&1

    # Reiniciar serviço cron
    if [[ ${PACKAGE_MANAGER} == 'dnf' || ${PACKAGE_MANAGER} == 'yum' ]]; then
        systemctl restart crond >/dev/null 2>&1
    else
        systemctl restart cron >/dev/null 2>&1
    fi

    # Limpar variáveis de ambiente
    sed -i "/$KEY/d" ~/$ENV_FILE
    source ~/$ENV_FILE

    colorEcho ${GREEN} "Desinstalado $KEY com sucesso!"
}

closeSELinux() {
    # Desativar SELinux
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    if command -v getenforce >/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
        colorEcho ${YELLOW} "SELinux ainda está ativo. Forçando desativação."
        setenforce 0
        if [ $? -ne 0 ]; then
            colorEcho ${RED} "Falha ao desativar SELinux. Isso pode causar problemas de permissão."
        fi
    fi
}

checkSys() {
    # Verificar se é root
    [ $(id -u) != "0" ] && { colorEcho ${RED} "Erro: Você deve ser root para executar este script"; exit 1; }

    # Identificar gerenciador de pacotes
    if [[ `command -v apt-get` ]]; then
        PACKAGE_MANAGER='apt-get'
    elif [[ `command -v dnf` ]]; then
        PACKAGE_MANAGER='dnf'
    elif [[ `command -v yum` ]]; then
        PACKAGE_MANAGER='yum'
    else
        colorEcho $RED "Sistema operacional não suportado!"
        exit 1
    fi
}

installDependent() {
    # Instalar dependências
    if [[ ${PACKAGE_MANAGER} == 'dnf' || ${PACKAGE_MANAGER} == 'yum' ]]; then
        ${PACKAGE_MANAGER} install socat crontabs bash-completion which -y
    else
        ${PACKAGE_MANAGER} update
        ${PACKAGE_MANAGER} install socat cron bash-completion ntpdate -y
    fi

    # Instalar Python 3 e pip
    source <(curl -sL https://python3.netlify.app/install.sh)
    if ! command -v pip >/dev/null 2>&1; then
        colorEcho ${RED} "Falha ao instalar pip. Instale Python e pip manualmente."
        exit 1
    fi
}

updateProject() {
    # Verificar se o pip está instalado
    [[ ! $(type pip 2>/dev/null) ]] && colorEcho $RED "pip não instalado!" && exit 1

    # Limpar instalações anteriores
    if [[ ${INSTALL_WAY} == 0 ]]; then
        colorEcho ${BLUE} "Limpando instalações anteriores..."
        rm -rf /usr/bin/xray /usr/bin/v2ray /usr/local/bin/xray /usr/local/bin/v2ray >/dev/null 2>&1
    fi

    # Instalar ou atualizar xray_util
    pip install -U xray_util

    if ! pip show xray_util >/dev/null 2>&1; then
        colorEcho ${RED} "Falha ao instalar xray_util. Verifique sua instalação do pip e tente novamente."
        exit 1
    fi

    # Configurar utilitários
    if [[ -e $UTIL_PATH ]]; then
        [[ -z $(cat $UTIL_PATH|grep lang) ]] && echo "lang=en" >> $UTIL_PATH
    else
        mkdir -p /etc/xray_util
        curl $UTIL_CFG > $UTIL_PATH
    fi

    [[ $CHINESE == 1 ]] && sed -i "s/lang=en/lang=zh/g" $UTIL_PATH

    # Criar links simbólicos
    rm -f /usr/local/bin/xray >/dev/null 2>&1
    ln -s $(which xray-util) /usr/local/bin/xray
    if [[ $V2RAY_MODE == 1 ]]; then
        rm -f /usr/local/bin/v2ray >/dev/null 2>&1
        ln -s $(which xray-util) /usr/local/bin/v2ray
    fi

    # Remover scripts de autocompletar antigos
    [[ -e /etc/bash_completion.d/xray.bash ]] && rm -f /etc/bash_completion.d/xray.bash
    [[ -e /usr/share/bash-completion/completions/xray.bash ]] && rm -f /usr/share/bash-completion/completions/xray.bash
    [[ -e /etc/bash_completion.d/v2ray.bash ]] && rm -f /etc/bash_completion.d/v2ray.bash
    [[ -e /usr/share/bash-completion/completions/v2ray.bash ]] && rm -f /usr/share/bash-completion/completions/v2ray.bash

    # Atualizar scripts de autocompletar
    curl $BASH_COMPLETION_SHELL > /usr/share/bash-completion/completions/xray
    if [[ $V2RAY_MODE == 1 ]]; then
        curl $BASH_COMPLETION_SHELL > /usr/share/bash-completion/completions/v2ray
    fi
    if [[ -z $(echo $SHELL|grep zsh) ]]; then
        source /usr/share/bash-completion/completions/xray
        [[ $V2RAY_MODE == 1 ]] && source /usr/share/bash-completion/completions/v2ray
    fi

    # Instalar núcleo XRay (ou V2Ray, se especificado)
    if [[ ${INSTALL_WAY} == 0 ]]; then
        if [[ $V2RAY_MODE == 1 ]]; then
            bash <(curl -L -s "$GO_SH_URL")
        else
            bash <(curl -L -s "$GO_SH_URL") --xray
        fi
        if [[ $? -ne 0 ]]; then
            colorEcho ${RED} "Falha ao instalar usando go.sh. Verifique sua rede ou o script em $GO_SH_URL."
            exit 1
        fi
    fi
}

timeSync() {
    if [[ ${INSTALL_WAY} == 0 ]]; then
        colorEcho ${BLUE} "Sincronizando horário..."
        if [[ `command -v ntpdate` ]]; then
            ntpdate pool.ntp.org
        elif [[ `command -v chronyc` ]]; then
            chronyc -a makestep
        fi

        if [[ $? -eq 0 ]]; then 
            colorEcho ${GREEN} "Sincronização de horário bem-sucedida"
            colorEcho ${GREEN} "Agora: `date -R`"
        else
            colorEcho ${YELLOW} "Falha na sincronização de horário. Isso pode causar problemas com solicitações de rede."
        fi
    fi
}

profileInit() {
    # Limpar variáveis de ambiente antigas
    [[ $(grep xray ~/$ENV_FILE) ]] && sed -i '/xray/d' ~/$ENV_FILE
    [[ $(grep v2ray ~/$ENV_FILE) ]] && sed -i '/v2ray/d' ~/$ENV_FILE
    source ~/$ENV_FILE

    # Configurar codificação Python
    [[ -z $(grep PYTHONIOENCODING=utf-8 ~/$ENV_FILE) ]] && echo "export PYTHONIOENCODING=utf-8" >> ~/$ENV_FILE && source ~/$ENV_FILE

    # Criar nova configuração para XRay (ou V2Ray)
    if [[ ${INSTALL_WAY} == 0 ]]; then
        if [[ $V2RAY_MODE == 1 ]]; then
            v2ray new
        else
            xray new
        fi
    fi
}

installFinish() {
    cd ${BEGIN_PATH}
    [[ ${INSTALL_WAY} == 0 ]] && WAY="instalação" || WAY="atualização"
    if [[ $V2RAY_MODE == 1 ]]; then
        colorEcho ${GREEN} "V2Ray ${WAY} concluída com sucesso!\n"
    else
        colorEcho ${GREEN} "XRay ${WAY} concluída com sucesso!\n"
    fi

    if [[ ${INSTALL_WAY} == 0 ]]; then
        clear
        if [[ $V2RAY_MODE == 1 ]]; then
            echo -e "\n\033[1;32mV2RAY INSTALADO COM SUCESSO!\033[0m"
            v2ray info
            echo -e "Use o comando 'v2ray' para gerenciar o V2Ray\n"
        else
            echo -e "\n\033[1;32mXRAY INSTALADO COM SUCESSO!\033[0m"
            xray info
            echo -e "Use o comando 'xray' para gerenciar o XRay\n"
        fi
    fi
}

main() {
    [[ ${HELP} == 1 ]] && help && return
    [[ ${REMOVE} == 1 ]] && removeCore && return
    if [[ $V2RAY_MODE == 1 ]]; then
        [[ ${INSTALL_WAY} == 0 ]] && colorEcho ${BLUE} "Nova instalação do V2Ray\n"
    else
        [[ ${INSTALL_WAY} == 0 ]] && colorEcho ${BLUE} "Nova instalação do XRay\n"
    fi

    checkSys
    installDependent
    closeSELinux
    timeSync
    updateProject
    profileInit
    installFinish
}

main
