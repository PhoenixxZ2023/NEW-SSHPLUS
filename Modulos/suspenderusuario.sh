#!/bin/bash
clear
###############################################################
# Programa para bloquear temporariamente e desbloquear contas de usuario
###############################################################
# SMIGOL PRO MANAGER
###############################################################

# Clear the screen at the start
clear

# Loop to display the menu until the user chooses to exit
while [ "$op" != "0" ]; do
  clear
  echo -e "\E[44;1;37m             BLOQUEAR USUÁRIO SSH            \E[0m"
  echo ""
  echo -e "\n"
  echo -e "\033[1;34m[\033[1;37m01 •\033[1;34m]\033[1;37m ➩ \033[1;33mBLOQUEAR USUÁRIO \033[0;32m"
  echo -e "\033[1;34m[\033[1;37m02 •\033[1;34m]\033[1;37m ➩ \033[1;33mDESBLOQUEAR USUÁRIO \033[1;37m"
  echo -e "\033[1;34m[\033[1;37m03 •\033[1;34m]\033[1;37m ➩ \033[1;33mLISTAR USUÁRIOS BLOQUEADOS \033[0;32m"
  echo -e "\033[1;34m[\033[1;37m00 •\033[1;34m]\033[1;37m ➩ \033[1;33mSAIR \033[0;32m"
  echo -e "\n"

  # Read user input for the menu option
  read -p "Escolha uma opção: " op

  case $op in
    1)  # Block user
      clear
      echo -e "\E[44;1;37m Usuario         Senha       limite      validade \E[0m"
      echo ""

      for users in $(awk -F : '$3 > 900 { print $1 }' /etc/passwd | sort | grep -v "nobody" | grep -vi polkitd | grep -vi system-); do
        if [[ $(grep -cw $users $HOME/usuarios.db) == "1" ]]; then
          lim=$(grep -w $users $HOME/usuarios.db | cut -d' ' -f2)
        else
          lim="1"
        fi

        if [[ -e "/etc/SSHPlus/senha/$users" ]]; then
          senha=$(cat /etc/SSHPlus/senha/$users)
        else
          senha="Null"
        fi

        datauser=$(chage -l $users | grep -i co | awk -F : '{print $2}')
        if [ "$datauser" == "never" ]; then
          data="\033[1;33mNunca\033[0m"
        else
          databr=$(date -d "$datauser" +"%Y%m%d")
          hoje=$(date -d today +"%Y%m%d")
          if [ "$hoje" -ge "$databr" ]; then
            data="\033[1;31mVenceu\033[0m"
          else
            dat=$(date -d"$datauser" '+%Y-%m-%d')
            data=$(echo -e "$((($(date -ud $dat +%s) - $(date -ud $(date +%Y-%m-%d) +%s)) / 86400)) \033[1;37mDias\033[0m")
          fi
        fi

        Usuario=$(printf ' %-15s' "$users")
        Senha=$(printf '%-13s' "$senha")
        Limite=$(printf '%-10s' "$lim")
        Data=$(printf '%-1s' "$data")
        echo -e "\033[1;33m$Usuario \033[1;37m$Senha \033[1;37m$Limite \033[1;32m$Data\033[0m"
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
      done

      echo ""
      _tuser=$(awk -F: '$3>=1000 {print $1}' /etc/passwd | grep -v nobody | wc -l)
      _ons=$(ps -x | grep sshd | grep -v root | grep priv | wc -l)
      [[ "$(cat /etc/SSHPlus/Exp)" != "" ]] && _expuser=$(cat /etc/SSHPlus/Exp) || _expuser="0"
      [[ -e /etc/openvpn/openvpn-status.log ]] && _onop=$(grep -c "10.8.0" /etc/openvpn/openvpn-status.log) || _onop="0"
      [[ -e /etc/default/dropbear ]] && _drp=$(ps aux | grep dropbear | grep -v grep | wc -l) _ondrp=$(($_drp - 1)) || _ondrp="0"
      _onli=$(($_ons + $_onop + $_ondrp))
      echo -e "\033[1;33m• \033[1;36mTOTAL USUARIOS\033[1;37m $_tuser \033[1;33m• \033[1;32mONLINES\033[1;37m: $_onli \033[1;33m• \033[1;31mVENCIDOS\033[1;37m: $_expuser \033[1;33m•\033[0m"

      echo " DIGITE O NOME DE USUÁRIO QUE DESEJA BLOQUEAR : "
      read lock
      passwd -l $lock && echo "$lock" >> /root/bloqueado
      echo -e "\033[1;34m\033[1;37m\033[1;34m\033[1;37m \033[1;33mUSUÁRIO BLOQUEADO COM SUCESSO \033[0;32m"
      echo -e ""
      echo -ne "\n\033[1;33mENTER \033[1;33mPARA VOLTAR AO \033[1;33mMENU!\033[0m"
      read
      ;;
    2)  # Unblock user
      clear
      cat /root/bloqueado
      echo " DIGITE O NOME DE USUÁRIO QUE DESEJA DESBLOQUEAR : "
      read unlock
      passwd -u $unlock
      echo -e "\033[1;34m\033[1;37m\033[1;34m\033[1;37m \033[1;33mUSUÁRIO DESBLOQUEADO COM SUCESSO \033[0;32m"
      echo -e ""
      echo -ne "\n\033[1;33mENTER \033[1;33mPARA VOLTAR AO \033[1;33mMENU!\033[0m"
      read
      ;;
    3)  # List blocked users
      clear
      if [ -e /root/bloqueado ]; then
        echo -e "\E[44;1;37m USUÁRIOS BLOQUEADOS \E[0m"
        cat /root/bloqueado
      else
        echo -e "\033[1;31mNenhum usuário bloqueado encontrado.\033[0m"
      fi
      echo -e ""
      echo -ne "\n\033[1;33mENTER \033[1;33mPARA VOLTAR AO \033[1;33mMENU!\033[0m"
      read
      ;;
    0)  # Exit
      clear
      echo "RETORNANDO...."
      exit 0
      menu
      ;;
    *)  # Invalid option
      clear
      echo "Opcao Invalida ..."
      ;;
  esac
done
