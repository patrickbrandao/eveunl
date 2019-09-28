#!/bin/sh

#
# Construir laboratorio EVE completo
#	Autor: Patrick Brandao, patrickbrandao@gmail.com, www.patrickbrandao.com
#	GIT: https://github.com/patrickbrandao/eveunl
#
export PATH="/bin:/sbin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/local/sbin:$PATH"

# Constantes
	# espaco minimo em disco, em kbytes
	MIN_FREE_SPACE="131072"

	# Cores
	ANSI_RESET='\033[0m'
	# Light
	ANSI_LIGHT_RED='\x1B[91m'          # Red
	ANSI_LIGHT_GREEN='\x1B[92m'        # Green
	ANSI_LIGHT_YELLOW='\x1B[93m'       # Yellow
	ANSI_LIGHT_BLUE='\x1B[94m'         # Blue
	ANSI_LIGHT_PINK='\x1B[95m'         # Purple
	ANSI_LIGHT_CYAN='\x1B[96m'               # Cyan
	ANSI_LIGHT_WHITE='\x1B[97m'              # White

	# Versoes do bugotik suportadas (lista atualizada pelo site)
	ALL_ROS_VERSIONS="
		6.44.5
		6.45.6
	"

	# Versoes do VyOS x86
	ALL_VYOS_VERSIONS="
		1.2.3
	"

	# Diretorio de downloads
	EVE_DOWNLOAD_DIR="/opt/unetlab/downloads"

	# Base remota de icones
	ICON_HTTP_BASE="https://raw.githubusercontent.com/patrickbrandao/eveunl/master/icons/"

	# Dados de repositorio particular IOL
	IOL_HTTP_BASE="http://www.ajustefino.com/downloads/iol"
	IOL_SIGLIST="index.md5"
	IOL_EVEDIR="/opt/unetlab/addons/iol/bin"
	IOL_URLSIGLIST="$IOL_HTTP_BASE/$IOL_SIGLIST"

	# Dados de repositorio particular Dynamips
	DYM_HTTP_BASE="http://www.ajustefino.com/downloads/dynamips"
	DYM_SIGLIST="index.md5"
	DYM_EVEDIR="/opt/unetlab/addons/dynamips"
	DYM_URLSIGLIST="$DYM_HTTP_BASE/$DYM_SIGLIST"

	# Base de imagens Q-EMU
	QEMU_HTTP_BASE="http://www.ajustefino.com/downloads/qemu"
	QEMU_SIGLIST="index.md5"
	QEMU_EVEDIR="/opt/unetlab/addons/qemu"
	QEMU_URLSIGLIST="$QEMU_HTTP_BASE/$QEMU_SIGLIST"













# Opcoes de instalacao interativa
    INST_ALL=0
    INST_INT=0

    INST_IOL=0
    INST_IOS=0

    INST_VYOS=0
    INST_MK=0

    whiptail --title "Selecione imagens" --checklist \
	"Selecione quais imagens deseja instalar no simulador" 20 78 8 \
	"ALL" "Instalar todas as imagens e versoes (+50g)" ON \
	"INT" "Instalacao interativa, escolher imagens" ON \
	"CISCO-IOL" "Instalar imagens Cisco IOL" OFF \
	"CISCO-IOS" "Instalar imagens Cisco IOS - Dynamips" OFF \
	"VYOS" "Instalar Linux VyOS" OFF \
	"MK-ROS" "Instalar Mikrotik Router OS" OFF \
	2> /tmp/inst_opt

    inst_opt=$(cat /tmp/inst_opt | sed 's#[^ a-z0-9A-Z-]##g' 2>/dev/null)
    inst_opt=$(echo $inst_opt)
    for x in $inst_opt; do
	[ "$x" = "ALL" ] && {
		INST_ALL=1
		INST_INT=1
		INST_IOL=1
		INST_IOS=1
		INST_MK=1
		INST_VYOS=1
	}
	[ "$x" = "INT" ] && INST_INT=1

	[ "$x" = "CISCO-IOL" ] && INST_IOL=1
	[ "$x" = "CISCO-IOS" ] && INST_IOS=1

	[ "$x" = "MK-ROS" ] && INST_MK=1
	[ "$x" = "VYOS" ] && INST_VYOS=1

    done

    echo "Opcoes de instalacao: $inst_opt"
    echo
    echo "   INST_ALL....: $INST_ALL"
    echo "   INST_INT....: $INST_INT"
    echo "   INST_IOL....: $INST_IOL"
    echo "   INST_IOS....: $INST_IOS"
    echo "   INST_VYOS...: $INST_VYOS"
    echo "   INST_MK.....: $INST_MK"
    echo

    # Incoerencias
    [ "$INST_ALL" = "0" -a "$INST_MK" = "0" -a "$INST_IOL" = "0" -a "$INST_IOS" = "0" -a "$INST_VYOS" = "0" ] && {
	echo
	echo "ERRO: Nenhuma opcao de instalacao foi selecionada"
	echo
	exit 9
    }


	_echo_lighred(){ /bin/echo -e "${ANSI_LIGHT_RED}$@$ANSI_RESET"; }
	_echo_lighgreen(){ /bin/echo -e "${ANSI_LIGHT_GREEN}$@$ANSI_RESET"; }
	_echo_lighyellow(){ /bin/echo -e "${ANSI_LIGHT_YELLOW}$@$ANSI_RESET"; }
	_echo_lighblue(){ /bin/echo -e "${ANSI_LIGHT_BLUE}$@$ANSI_RESET"; }
	_echo_lighpink(){ /bin/echo -e "${ANSI_LIGHT_PINK}$@$ANSI_RESET"; }
	_echo_lighcyan(){ /bin/echo -e "${ANSI_LIGHT_CYAN}$@$ANSI_RESET"; }
	_echo_lighwhite(){ /bin/echo -e "${ANSI_LIGHT_WHITE}$@$ANSI_RESET"; }
	_alert(){ echo; _echo_lighyellow "** Alerta: $1"; echo; }
	_abort(){ echo; _echo_lighred "** ABORTADO: $1"; echo; exit $2; }


	# obter arquivo via HTTP
	# - obter md5 de um arquivo
	_getmd5(){ md5sum "$1" | awk '{print $1}'; }
	# - obter md5 de um arquivo e comprar com md5 de referencia, retornar comparacao no stdno
	_testmd5(){ _m=$(_getmd5 "$1"); [ "x$_m" = "x$2" ] && return 0; return 1; }
	# - obter arquivo via HTTP
	_http_get(){
		_ipv6off
		_hg_url="$1"; _hg_file="$2"; _hg_md5="$3"; _hg_opt=""; _hg_debug=""
		_hg_eu=$(echo "$_hg_url" | cut -f1 -d'?')
		_echo_lighgreen "> HTTP-GET: Baixando: [$_hg_eu] -> [$_hg_file]"
		_hg_opt="-4 --retry-connrefused --no-cache --progress=bar:force:noscroll --no-check-certificate --timeout=5 --read-timeout=5 --tries=30 --wait=1 --waitretry=1 -O $_hg_file"
		wget $_hg_opt "$_hg_url?nocache=$RANDOM"; _hg_ret="$?"
		if [ "$_hg_ret" = "0" -a "x$_hg_md5" != "x" ]; then _testmd5 "$_hg_file" "$_hg_md5"; _hg_ret="$?"; fi
		return $_hg_ret
	}
	# - obter md5 armazenado num arquivo do site
	_http_get_md5(){
	    hmurl="$1"
	    [ "x$hmurl" = "x" ] && return 1
	    r=$(curl "$hmurl" 2>/dev/null)
	    #echo; echo "RL: $hmurl"; echo "RT: [$r]"; echo
	    [ "x$r" = "x" ] && return 2
	    n=$(echo -n "$r" | wc -c)
	    [ "x$n" = "x32" ] || return 3
	    echo "$r"
	}
	# - sincronizar arquivos via HTTP
	_http_sync(){
		# Parametros
		hs_localdir="$1"
		hs_baseurl="$2"
		hs_indexname="$3"
		hs_filter="$4"; [ "x$hs_filter" = "x" ] && hs_filter="."
		# Variaveis locais
		hs_indexurl="$hs_baseurl/$hs_indexname"
		hs_tmpindex="/tmp/httpsync-$hs_indexname"; rm -f "$hs_tmpindex" 2>/dev/null

		# Criar e acessar diretorio
		mkdir -p "$hs_localdir" 2>/dev/null
		cd "$hs_localdir" || {
			_echo_lighyellow "> HTTP-SYNC :: Erro ao acessar diretorio [$hs_localdir]"
			return 7
		}
		_echo_lighgreen "> HTTP-SYNC :: Diretorio....: [$hs_localdir]"
		_echo_lighgreen "> HTTP-SYNC :: Base URL.....: [$hs_baseurl]"
		_echo_lighgreen "> HTTP-SYNC :: Indice.......: [$hs_indexname]"

		# OBTER INDICE
		_http_get "$hs_indexurl" "$hs_tmpindex" 2>/dev/null || { _echo_lighyellow "> HTTP-SYNC :: Erro $? ao obter indice."; rm -f "$hs_tmpindex" 2>/dev/null; return 11; }

		# PROCESSAR INDICE aplicando filtro
		hs_filteredindex="/tmp/httpsync-filtered-$hs_indexname"; rm -f "$hs_filteredindex" 2>/dev/null
		cat "$hs_tmpindex" | egrep "$hs_filter" > $hs_filteredindex
		hs_idxcount=$(cat "$hs_filteredindex" | wc -l)
		if [ "$hs_idxcount" = "0" ]; then
			_echo_lighgreen "> HTTP-SYNC :: Nenhum arquivo na lista [filtro: $hs_filter]"
			return 0
		fi
		# Obter lista de MD5
		hs_list=$(cat "$hs_filteredindex" | awk '{print $1}')
		hs_count=0
		for hs_md5 in $hs_list; do
			
			hs_file=$(egrep "^$hs_md5" $hs_filteredindex | awk '{print $2}' | head -1)
			#_echo_lighcyan "  - HTTP-SYNC :: Processando $hs_md5 - $hs_file"

			# Sincronizar
			hs_tmp="/tmp/httpsync-$hs_file"
			hs_url="$hs_baseurl/$hs_file"
			hs_dstfile="$hs_localdir/$hs_file"

			# Arquivo ja existe, conferir assinatura
			[ -f "$hs_dstfile" ] && _testmd5 "$hs_dstfile" "$hs_md5" && {
				_echo_lighgreen "  - HTTP-SYNC [$hs_file]: Sincronizado"
				continue
			}

			# Procurar assinatura em algum arquivo existente e evitar baixar arquivo duplicado
			_echo_lighcyan "  - HTTP-SYNC :: Procurando arquivo duplicado [$hs_file";
			hs_filefound=x
			for hs_efile in *; do
				[ -f "$hs_efile" ] || continue
				hs_tmpmd5=$(_getmd5 "$hs_efile")
				[ "$hs_md5" = "$hs_tmpmd5" ] && hs_filefound="$hs_efile" && break
			done
			[ "$hs_filefound" = "x" ] || {
				_echo_lighcyan "  - HTTP-SYNC: [$hs_file]: Imagem OK [em $hs_filefound, $hs_md5]"
				continue
			}
			# Remover temporario e destino
			rm -f "$hs_tmp" 2>/dev/null; rm -f "$hs_dstfile" 2>/dev/null

			# Baixar
			_echo_lighcyan "  - HTTP-SYNC [$hs_file]: Obtendo via URL $hs_url"

			_http_get "$hs_url" "$hs_tmp"; hs_ret="$?"
			[ "$hs_ret" = "0" ] || {
				_echo_lighyellow "  - HTTP-SYNC [$hs_file]: Erro $hs_ret ao baixar [$hs_url] para [$hs_tmp]"
				continue;
			}

			# Verificar assinatura MD5
			hs_local_md5=$(_getmd5 "$hs_tmp")
			[ "$hs_local_md5" = "x" ] && {
				_echo_lighyellow "  - HTTP-SYNC [$hs_file]: Erro ao obter assinatura MD5 de [$hs_tmp]"
				continue
			}
			[ "$hs_md5" = "$hs_local_md5" ] || {
				_echo_lighyellow "  - HTTP-SYNC [$hs_file]: Download corrompido [$hs_md5] =/= [$hs_local_md5]"
				continue
			}

			# Tudo certo, instalar
			mv "$hs_tmp" "$hs_dstfile" || {
				_echo_lighyellow "  - HTTP-SYNC [$hs_file]: Erro ao mover [$hs_tmp] > [$hs_dstfile]"
				continue
			}
			_echo_lighgreen "  - HTTP-SYNC [$hs_file]: Sincronizado."
		done
	}


	# procurar binarios, e se nao existirem instalar o respectivo pacote
	_procedure_pkgs(){
		pp_important="
			/usr/bin/mcedit:mc /usr/sbin/iptraf:iptraf /usr/bin/bwm-ng:bwm-ng
			/usr/bin/rsync:rsync /usr/bin/host:host /usr/sbin/ntpdate:ntpdate
			/usr/bin/unzip:unzip /usr/sbin/arping:arping
			/usr/lib/quagga/zebra:quagga
			/usr/sbin/pppd:ppp
			/usr/bin/lsof:lsof
			/usr/sbin/xl2tpd:xl2tpd
			/usr/bin/nmap:nmap
			/usr/bin/curl:curl
		"
		pp_list="$pp_important /usr/bin/wget:wget /usr/bin/mysql:mysql-server /usr/bin/htop:htop"
		pp_vitalbins="/bin/date /usr/bin/md5sum /usr/bin/unzip /usr/bin/wget /usr/bin/unzip"
		_echo_lighgreen "> Verificando programas..."
		for ppitem in $pp_list; do
			_ipv6off
			ppbin=$(echo $ppitem | cut -f1 -d:); pppkg=$(echo $ppitem | cut -f2 -d:);
			[ -x "$ppbin" ] || { _echo_lighgreen "> Instalando: $ppbin / $pppkg"; apt-get -y install $pppkg; }
		done
		# Alertar de ausencias importantes
		for ppitem in $pp_important; do ppbin=$(echo $ppitem | cut -f1 -d:); [ -x "$ppbin" ] || _echo_lighyellow "Binario importante ausente: $ppbin"; done
		# Abortar se faltar algo indispensavel
		for ppvital in $pp_vitalbins; do [ -x "$ppvital" ] || _abort "Binario vital nao encontrado: $ppvital"; done
		_echo_lighgreen "> Programas OK"
	}

	# instalar pacotes auxiliares
	_procedure_auxpkgs(){
	    list="
		mtr
		mtr-tiny
		whois
		pptp
		snmp
		links
		tcpdump
		openswan
		xl2tpd
		l2tp-ipsec-vpn
		strace
	    "
	    for pkg in $list; do
		
		
		
		-y install $pkg
	    done
	}

	# verificar espaco livre, nunca deixar menos que minimo seguro
	_procedure_check_freespace(){
		# obter free-space em k orientado a pasta de armazenamento do EVE
		freespace=$(df /opt/unetlab | grep 'eve' | awk '{print $4}')
		[ "x$freespace" = "x" ] && return
		[ "$freespace" -lt "$MIN_FREE_SPACE" ] && _abort "Espaco livre em disco inferior ao minimo de seguranda: $MIN_FREE_SPACE"
	}




	# Ajustar permissoes do UNL/EVE
	_eve_fixpermissions(){ _echo_lighpink "> Ajustando permissoes UNL/EVE-NG"; /opt/unetlab/wrappers/unl_wrapper -a fixpermissions 2>/dev/null 1>/dev/null; }




	# Funcoes 05



# Variaveis
	today=$(date '+%Y%m%d')
	nowh=$(date '+%Y%m%d%H')

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= INICIANDO

	# x - espaco minimo
	_procedure_check_freespace

	# x - sem suporte a vm/kvm/vmx/svm
	tmp=$(cat /proc/cpuinfo| egrep "vmx|svm")
	[ "x$tmp" = "x" ] && _abort "O suporte a VMX/AMD-V/VT-X/KVM nao esta ativo."

	# - remover alias chato
	{ unalias cp; unalias mv; unalias rm; } 2>/dev/null 1>/dev/null

	# IPv6 atrapalha mais que ajuda
	_ipv6off(){
	    for i in $(seq 0 1 20); do
		ip -6 addr flush dev pnet$i 2>/dev/null
		ip -6 route flush dev pnet$i 2>/dev/null
		sysctl -w net.ipv6.conf.pnet$i.autoconfig=0 1>/dev/null 2>/dev/null
		sysctl -w net.ipv6.conf.pnet$i.accept_ra=0 1>/dev/null 2>/dev/null
	    done
	    sysctl -w net.ipv6.conf.all.autoconf=0 2>/dev/null 1>/dev/null
	    sysctl -w net.ipv6.conf.default.autoconf=0 2>/dev/null 1>/dev/null
	    sysctl -w net.ipv6.conf.all.accept_ra=0 2>/dev/null 1>/dev/null
	    sysctl -w net.ipv6.conf.default.accept_ra=0 2>/dev/null 1>/dev/null
	}
	_ipv6off






	# - Atualizar repositorios
	updtflag="/tmp/update-done-$today"
	if [ ! -f "$updtflag" ]; then
		_echo_lighgreen "> Atualizando repositorios"
		apt-get -y update && touch $updtflag
	fi
	[ -f "$updtflag" ] || _abort "Falhou ao realizar update, tente novamente"
	[ -f "$updtflag" ] && _echo_lighgreen "> Atualizacao de repositorios OK"


# Instalar EVE
    _echo_lighpink "> Instalando EVE-NG"
    apt autoremove
    apt-get -y install eve-ng
    apt-get -y install eve-ng

	# 0 - timezone
	tzflag="/tmp/tzdata-done"
	if [ ! -f "$tzflag" ]; then
		dpkg-reconfigure tzdata && touch $tzflag
	fi


	# - testar INTERNET
	_echo_lighgreen "> Testando acesso a internet"
	inetflag="/tmp/internet-done-$nowh"
	if [ ! -f "$inetflag" ]; then
		# Teste usando PING
		_echo_lighblue "   - PING 8.8.8.8"
		timeout 5s ping -q 8.8.8.8 -c 3 >/dev/null; r1="$?"; [ "$r1" = "0" ] || r1=1
		_echo_lighblue "   - PING 4.2.2.2"
		timeout 5s ping -q 4.2.2.2 -c 3 >/dev/null; r2="$?"; [ "$r2" = "0" ] || r2=1
		_echo_lighblue "   - PING 200.160.2.3"
		timeout 5s ping -q 200.160.2.3 -c 3 >/dev/null; r3="$?"; [ "$r3" = "0" ] || r3=1
		# Teste usando resolucao DNS
		rsdns=""
		[ -x /usr/bin/resolveip ] && rsdns="/usr/bin/resolveip"
		[ -x /usr/bin/host ] && rsdns="/usr/bin/host"
		[ "x$rsdns" = "x" ] && _abort "Nenhum programa de teste de dns encontrado (resolveip, host)"
		_echo_lighblue "   - DNS google.com"
		timeout 5s $rsdns google.com >/dev/null; r4="$?"; [ "$r4" = "0" ] || r4=1
		_echo_lighblue "   - DNS registro.br"
		timeout 5s $rsdns registro.br >/dev/null; r5="$?"; [ "$r5" = "0" ] || r5=1
		# Falhou em todos os testes
		[ "$r1$r2$r3$r4$r5" = "11111" ] && _abort "Incapaz de contactar internet (Ping, DNS), verifique sua conexao."
		touch "$inetflag"
	fi
	_echo_lighgreen "> Internet OK"


	# - Instalar binarios necessarios
	_procedure_pkgs

	# - Instalar pacotes auxiliares para deixar o sistema completo
	_procedure_auxpkgs


	# 4 - Upgrade de sistema
	upgflag="/tmp/upgrade-done-$today"
	if [ ! -f "$upgflag" ]; then
		_echo_lighgreen "> Atualizando pacotes"
    	    apt-get -y upgrade && touch $upgflag
    	    [ -f "$upgflag" ] && apt -y autoremove
	fi
	[ -f "$upgflag" ] || _abort "Falhou ao realizar UPGRADE de pacotes, tente novamente"
	[ -f "$upgflag" ] && _echo_lighgreen "> Atualizacao de pacotes OK"


	# Instalar novamente para garantir sanidade apos upgrade e autoremove
	_procedure_pkgs
	_procedure_check_freespace


#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Preparar EVE-NG

	# 1 - ta instalado e com os binarios vitais ?
	echo
	_echo_lighcyan "> Verificando EVE-NG..."
	[ -d /opt/unetlab ] || _abort "EVE-NG nao esta instalado"
	# wrapper
	[ -x /opt/unetlab/wrappers/dynamips_wrapper ] || _abort "EVE-NG incompleto (dynamips_wrapper)"
	[ -x /opt/unetlab/wrappers/iol_wrapper ] || _abort "EVE-NG incompleto (iol_wrapper)"
	[ -x /opt/unetlab/wrappers/nsenter ] || _abort "EVE-NG incompleto (nsenter)"
	[ -x /opt/unetlab/wrappers/qemu_wrapper ] || _abort "EVE-NG incompleto (qemu_wrapper)"
	[ -x /opt/unetlab/wrappers/unl_wrapper ] || _abort "EVE-NG incompleto (unl_wrapper)"
	# qemu std
	[ -x /opt/qemu/bin/qemu-img ] || _abort "EVE-NG incompleto (STD qemu-img)"
	[ -x /opt/qemu/bin/qemu-system-i386 ] || _abort "EVE-NG incompleto (STD qemu-system-i386)"
	[ -x /opt/qemu/bin/qemu-system-x86_64 ] || _abort "EVE-NG incompleto (STD qemu-system-x86_64)"
	# qemu 1.3.1
	[ -x /opt/qemu-1.3.1/bin/qemu-img ] || _abort "EVE-NG incompleto (1.3.1 qemu-img)"
	[ -x /opt/qemu-1.3.1/bin/qemu-system-i386 ] || _abort "EVE-NG incompleto (1.3.1 qemu-system-i386)"
	[ -x /opt/qemu-1.3.1/bin/qemu-system-x86_64 ] || _abort "EVE-NG incompleto (1.3.1 qemu-system-x86_64)"
	# qemu 2.0.2
	[ -x /opt/qemu-2.0.2/bin/qemu-img ] || _abort "EVE-NG incompleto (2.0.2 qemu-img)"
	[ -x /opt/qemu-2.0.2/bin/qemu-system-i386 ] || _abort "EVE-NG incompleto (2.0.2 qemu-system-i386)"
	[ -x /opt/qemu-2.0.2/bin/qemu-system-x86_64 ] || _abort "EVE-NG incompleto (2.0.2 qemu-system-x86_64)"
	# diretorios de destino de imagens
	[ -d /opt/unetlab/addons/qemu ] || _abort "EVE-NG incompleto: not-found /opt/unetlab/addons/qemu"
	[ -d /opt/unetlab/addons/iol/bin ] || _abort "EVE-NG incompleto: not-found /opt/unetlab/addons/iol/bin"

	_echo_lighcyan "> Verificando EVE-NG OK"
	echo


#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Imagens MIKROTIK
if [ "x$INST_MK" = "x1" ]; then
	echo
	_echo_lighcyan "> Adicionando imagens MIKROTIK"

	# Funcao para instalar pela versao
	_install_ros_version(){
		rosver="$1"
		[ "x$rosver" = "x" ] && return 99
		# - verificar se ja existe
		rosrundir="/opt/unetlab/addons/qemu/mikrotik-$rosver"
		qcow2file="$rosrundir/hda.qcow2"
		[ -f "$qcow2file" ] && { _echo_lighcyan " -> Mikrotik-$rosver: Imagem OK"; return 0; }
		# Apagar lixo anterior
		rm -rf "$rosrundir" 2>/dev/null
		# download da imagem do site da mititiki
		rosvmdkurl="http://download2.mikrotik.com/routeros/$rosver/chr-$rosver.img.zip"
		_echo_lighcyan " -> Mikrotik-$rosver: Obtendo via URL $rosvmdkurl"
		rosoutfile="/tmp/chr-$rosver.img.zip"
		rosoutfileunzipped="/tmp/chr-$rosver.img"
		rm -f $rosoutfile 2>/dev/null
		_http_get "$rosvmdkurl" "$rosoutfile"; wr="$?"
		[ "$wr" = "0" ] || { _echo_lighyellow "Mikrotik-$rosver: Erro ao baixar [$rosvmdkurl] para [$rosoutfile]"; return 91; }
		_echo_lighcyan " -> Mikrotik-$rosver: Download concluido - $rosoutfile"
		# Descompactar
		cd /tmp || _abort "Erro $? ao acessar diretorio /tmp"
		[ -f "$rosoutfileunzipped" ] && rm -f "$rosoutfileunzipped" 2>/dev/null
		unzip "$rosoutfile" || _abort "Erro $? ao descomprimir $rosoutfile"
		[ -f "$rosoutfileunzipped" ] || _abort "Arquivo resultante do unzip nao encontrado: $rosoutfileunzipped"
		# Converter para qCow2
		mkdir -p "$rosrundir" || _abort "Erro $? ao criar diretorio [$rosrundir]"
		_echo_lighcyan " -> Mikrotik-$rosver: Convertendo [$rosoutfile] para [$qcow2file]"
		qcmd="/opt/qemu/bin/qemu-img convert -f raw -O qcow2 '$rosoutfileunzipped' '$qcow2file'"
		_echo_lighcyan " -> # $qcmd"
		eval "$qcmd" || _abort "Erro $? ao converter vmdk: $qcmd"
		# remover arquivo original baixado
		rm -f "$rosoutfile" 2>/dev/null
		rm -f "$rosoutfileunzipped" 2>/dev/null
		_echo_lighgreen " -> Mikrotik-$rosver: Nova imagem instalada com sucesso: $rosver"
	}

	# Detectar ultima versao long-term (lt), ultima versao stable (le) e ultima beta (lb)
	lastlt=""; lastle=""; lastlb=""
	wget https://mikrotik.com/download/changelogs -O /tmp/mikrotik-changelogs.html && {
		# Filtrar ultima versao Long-term: Long-term release tree
		v=$(egrep -n 'Long-term release tree' /tmp/mikrotik-changelogs.html | head -2 | \
			tail -n1 | cut -f1 -d: | \
			while read seclineid; do \
				egrep -n . /tmp/mikrotik-changelogs.html | \
				egrep "^$seclineid:" -A 20 | \
				grep Release
			done | sed 's#Release.#|#g' | cut -f2 -d'|' | cut -f1 -d'<'
		)
		echo $v | egrep '^[0-9]+\.[0-9]+\.[0-9]+' >/dev/null && lastlt="$v"
		# Filtrar ultima versao Stable: Stable release tree
		v=$(egrep -n 'Stable release tree' /tmp/mikrotik-changelogs.html | head -2 | \
			tail -n1 | cut -f1 -d: | \
			while read seclineid; do \
				egrep -n . /tmp/mikrotik-changelogs.html | \
				egrep "^$seclineid:" -A 20 | \
				grep Release
			done | sed 's#Release.#|#g' | cut -f2 -d'|' | cut -f1 -d'<'
		)
		echo $v | egrep '^[0-9]+\.[0-9]+\.[0-9]+' >/dev/null && lastle="$v"
		# Filtrar ultima versao beta: Testing release tree
		v=$(egrep -n 'Testing release tree' /tmp/mikrotik-changelogs.html | head -2 | \
			tail -n1 | cut -f1 -d: | \
			while read seclineid; do \
				egrep -n . /tmp/mikrotik-changelogs.html | \
				egrep "^$seclineid:" -A 20 | \
				grep Release
			done | sed 's#Release.#|#g' | cut -f2 -d'|' | cut -f1 -d'<'
		)
		echo $v | egrep '^[0-9]+\.[0-9]+' >/dev/null && lastlb="$v"
	}
	# Agregar versoes descobertas na lista
	ALL_ROS_VERSIONS="$ALL_ROS_VERSIONS $lastlt $lastle $lastlb"

	# Instalar todas as versoes
	for rosv in $ALL_ROS_VERSIONS; do _install_ros_version "$rosv"; _procedure_check_freespace; done

	_echo_lighcyan "> Concluido: Imagens MIKROTIK"
	echo
else
	_echo_lighyellow "> DESATIVADO: imagens MIKROTIK"
fi




#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Imagens IOL
if [ "x$INST_IOL" = "x1" ]; then
	echo
	_echo_lighcyan "> Adicionando imagens Cisco-IOL"

	# Sincronizar imagens
		_http_sync "$IOL_EVEDIR" "$IOL_HTTP_BASE" "$IOL_SIGLIST" 

	# Ativar NETMAP
		_echo_lighcyan "> Cisco-IOL: Ativando NETMAP"
		IOLNETMAP="/opt/unetlab/addons/iol/bin/NETMAP"
		rm -f "$IOLNETMAP" 2>/dev/null
		touch "$IOLNETMAP" 2>/dev/null || _echo_lighyellow "Cisco-IOL: Erro ao criar NETMAP [$IOLNETMAP]"

	# Licenca IOU
	# falta

	_echo_lighcyan "> Concluido: Imagens Cisco-IOL"
	echo
else
    _echo_lighyellow "> DESATIVADO: imagens Cisco-IOL"
fi

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Imagens DYNAMIPS
if [ "x$INST_IOS" = "x1" ]; then
	echo
	_echo_lighcyan "> Adicionando imagens Dynamips"

	# Sincronizar imagens
		mkdir -p "$EVE_DOWNLOAD_DIR" 2>/dev/null
		_http_sync "$EVE_DOWNLOAD_DIR" "$DYM_HTTP_BASE" "$DYM_SIGLIST" 

	# Descompactando
	cd $EVE_DOWNLOAD_DIR && {
		for dymfile in *.txz *.bin; do
			[ -f "$dymfile" ] || continue

			_ext=$(echo "$dymfile" | rev | cut -f1 -d. | rev)

			# XZ
			[ "$_ext" = "txz" ] && {
				_echo_lighgreen " -> Dynamips: $dymfile XZ Image"

				n=$(basename "$dymfile" .txz)
				i="$DYM_EVEDIR/$n.image"

				# ja foi descompactada
				[ -f "$i" ] && { _echo_lighgreen " -> Dynamips: $dymfile -----> $i OK"; continue; }

				# descompactar
				tar -xf "$dymfile" -C "$DYM_EVEDIR/" || { _echo_lighyellow " -> Dynamips: $dymfile, erro $? ao descompactar imagem"; continue; }
				[ -f "$i" ] || { _echo_lighyellow " -> Dynamips: $dymfile, arquivo '$i' nao encontrado apos descompactar"; continue; }
				_echo_lighgreen " -> Dynamips: $dymfile -----> $i OK"
			}
			# BIN
			[ "$_ext" = "bin" ] && {
				_echo_lighgreen " -> Dynamips: $dymfile BIN Package"
				n=$(basename "$dymfile" .bin)
				i="$DYM_EVEDIR/$n.image"

				# ja foi descompactada
				[ -f "$i" ] && { _echo_lighgreen " -> Dynamips: $dymfile -----> $i OK"; continue; }

				# descompactar
				unzip -p "$n" > $i
				_echo_lighgreen " -> Dynamips: $dymfile -----> $i OK"
			}
			# IMAGE
			[ "$_ext" = "image" ] && {
				_echo_lighgreen " -> Dynamips: $dymfile IMAGE"
				i="$DYM_EVEDIR/$dymfile"

				# ja foi descompactada
				[ -f "$i" ] && { _echo_lighgreen " -> Dynamips: $dymfile -----> $i OK"; continue; }

				# copiar
				cat $dymfile > $i
				_echo_lighgreen " -> Dynamips: $dymfile -----> $i OK"
			}

		done
	}

	# Conferir assinaturas
	DYMSIGLIST="$EVE_DOWNLOAD_DIR/dynamips-images.md5"
	if [ -f "$DYMSIGLIST" ]; then
		# conferir a sanidade das imagens descompactadas
		cd "$DYM_EVEDIR" && {
			_echo_lighgreen "> Dynamips: conferindo assinatura de imagens (aguarde)"
			md5sum -c $DYMSIGLIST 2>&1 | egrep -v 'OK$' | grep FAILED | cut -f1 -d: | while read imgbug; do
				_echo_lighyellow " -> Dynamips: imagem danificada: $imgbug"
				rm -f "$DYM_EVEDIR/$imgbug" 2>/dev/null
			done
		}
	else
		_echo_lighyellow "> Dynamips: arquivo de assinagura de imagens ausente: $DYMSIGLIST";
	fi

	_echo_lighcyan "> Concluido: Imagens Dynamips"
	echo
else
    _echo_lighyellow "> DESATIVADO: imagens Cisco-IOS"
fi


#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Imagens VyOS
if [ "x$INST_VYOS" = "1" ]; then
	echo
	_echo_lighcyan "> Adicionando imagens VyOS"

	# Funcao para instalar pela versao
	_install_vyos_version(){
		vyosver="$1"
		[ "x$vyosver" = "x" ] && return 98
		# - verificar se ja existe
		vyosrundir="/opt/unetlab/addons/qemu/vyos-$vyosver"
		qcow2file="$vyosrundir/hda.acow2"
		[ -f "$qcow2file" ] && { _echo_lighcyan " -> VyOS-$vyosver: Imagem OK"; return 0; }
		rm -rf "$vyosrundir" 2>/dev/null
		# download da imagem do site da mititiki
		vyosqcow2url="$QEMU_HTTP_BASE/vyos-$vyosver.qcow2"
		vyosqcow2md5="$QEMU_HTTP_BASE/vyos-$vyosver.md5"
		# obter MD5 para validar integridade do arquivo
		_http_get_md5 "$vyosqcow2md5"
		vyosmd5=$(_http_get_md5 "$vyosqcow2md5"); r="$?"
		if [ "x$vyosmd5" = "x" ]; then
			_echo_lighyellow "VyOS-$vyosver: Erro $r ao obter md5 ($vyosqcow2md5)"
			return 81
		fi
		_echo_lighcyan " -> VyOS-$vyosver: Obtendo via URL $vyosqcow2url"
		vyosoutfile="/tmp/vyos-$vyosver.qcow2"
		rm -f $vyosoutfile 2>/dev/null
		_http_get "$vyosqcow2url" "$vyosoutfile"; wr="$?"
		[ "$wr" = "0" ] || { _echo_lighyellow "VyOS-$vyosver: Erro ao baixar [$vyosqcow2url] para [$vyosoutfile]"; return 91; }
		_echo_lighcyan " -> VyOS-$vyosver: Download concluido - $vyosoutfile"
		# conferir md5 do arquivo baixado com o arquivo assinado no site
		vmd5=$(_getmd5 "$vyosoutfile")
		if [ "$vmd5" = "$vyosmd5" ]; then
		    # movendo para local oficial
		    mkdir -p "$vyosrundir" || _abort "Erro $? ao criar diretorio: $vyosrundir"
		    mv "$vyosoutfile" "$qcow2file" || _abort "Erro $? ao mover qcow2: [$vyosoutfile] [$qcow2file]"
		    _echo_lighgreen " -> VyOS-$vyosver: Nova imagem instalada com sucesso: $qcow2file"
		else
		    # corrompeu
		    _echo_lighyellow "VyOS-$vyosver: Erro ao obter md5 [$vmd5] wrong [$vyosmd5]"
		    return 82
		fi
	}

	# Instalar todas as versoes
	for vyosv in $ALL_VYOS_VERSIONS; do _install_vyos_version "$vyosv"; _procedure_check_freespace; done

	_echo_lighcyan "> Concluido: Imagens VyOS"
	echo
else
    _echo_lighyellow "> DESATIVADO: imagens VyOS"
fi




#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Melhorar estilo

    # Obter master.zip do projeto eveunl
    eveunlmaster="/tmp/eveunl-master.zip"
    if [ -f "$eveunlmaster" ]; then
	_echo_lighcyan "> Pacote de personalizacao ja aplicado ($eveunlmaster)"
    else
	_http_get "https://github.com/patrickbrandao/eveunl/archive/master.zip" "$eveunlmaster"
	if [ -f "$eveunlmaster" ]; then
	    rm -rf /tmp/eveunl 2>/dev/null
	    mkdir /tmp/eveunl 2>/dev/null
	    cd /tmp/eveunl || _abort "> Falhou ao entrar em /tmp/eveunl"
	    unzip $eveunlmaster; sn="$?"
	    if [ "$sn" = "0" ]; then
		cp eveunl-master/icons/* /opt/unetlab/html/images/icons/ || _alert "> Problema ao copiar icones 1"
		cp eveunl-master/icons/Cloud.png /opt/unetlab/html/images/cloud.png || _alert "> Problema ao copiar icones 2"
	    else
		rm $eveunlmaster 2>/dev/null
		_alert "> Falhou ao descompactar $eveunlmaster"
	    fi
	else
	    _echo_lighyellow "> Incapaz de personalizar, arquivo nao foi baixado";
	fi
    fi


#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= Acabou

	_eve_fixpermissions
	_echo_lighpink "* EVE-NG Concluido!"
	echo



