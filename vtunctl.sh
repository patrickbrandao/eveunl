#!/bin/sh

#
# Script de gerenciamento de tuneis VPN usando VTUN (vtund)
# http://vtun.sourceforge.net/
#
# Autor: Patrick Brandao <patrickbrandao@gmail.com>
#        http://www.patrickbrandao.com
#
# Execute: sh vtunctl.sh help
#
# Exemplos no final do arquivo
#

# Variaveis
#==========================================================================================================

VTUND=/usr/sbin/vtund
PPPD=/usr/sbin/pppd
IFCONFIG=/sbin/ifconfig
ROUTE=/sbin/route
FIREWALL=/sbin/iptables
IP=/sbin/ip
SELFSCRIPT="$0"
CMDLINE="$0 $@"

CNFDIR=/etc/vtun
CMD=""
SERVER=""
PEERIP=""
LOCALIP=""
PORT=7100
PROTO=tcp
SECRET=thebestvpn
CRYPT="no"
COMPRESS="no"
KEEPALIVE="yes"
PERSIST="yes"
MODE=tun
DEVICE=tun0

DEBUG=0

# Funcoes
#==========================================================================================================
_abort(){ echo; echo "ABORTADO: $1"; echo; exit $2; }
_abort_empty(){ [ "x$1" = "x" ] && _abort "$2" $3; }
_help(){
	echo
	echo "vtunctl (stop|start|restart|list|add|test|delete|help) [options]"
	echo
	echo "Criar cliente vtun:"
	echo "  add -n VNAME -s SERVER -l LOCALIP -r PEERIP -p PORT -x SECRET"
	echo
	echo "Argumentos:"
	echo "  -n VNAME    : Nome da VPN"
	echo "  -s SERVER   : IP do servidor"
	echo "  -m MODE     : Modo da VPN (l2/ether, l3/tun, pipe, tty), padrao l3/tun"
	echo "  -l LOCALIP  : IP do tunel local"
	echo "  -r PEERIP   : IP do tunel remoto"
	echo "  -x SECRET   : Senha de criptografia"
	echo "  -p PORT     : Porta do servidor"
	echo "  -c CRYPT    : metodo de criptografia [no, yes, ...]"
	echo "  -d DEVICE  : propor nome de interface de rede, padrao tunN"
	echo "  -Z ZIPMODE  : ativar compressao e escolher algo (zlib, lzo,zlib:N, lzo:N)"
	echo "  -z          : ativar compressao"
	echo "  -K          : desativar keepalive"
	echo "  -P          : desativar persistencia"
	echo
	echo "Controlar cliente:"
	echo "  stop     VNAME      : parar vpn cliente"
	echo "  restart  VNAME      : parar vpn cliente"
	echo "  start    VNAME      : iniciar vpn"
	echo "  test     VNAME      : testar vpn"
	echo "  list                : listar clientes"
	echo
}
_empty_help(){ if [ "x$1" = "x" ]; then _help; exit $2; fi; }

_setup(){
	which vtund >/dev/null || {
		echo "SETUP: vtund not found, try to install"
		apt-get -y update
		apt-get -y install vtund
	}
	which vtund >/dev/null || {
		echo "SETUP: failure, vtund not found"
		exit 9
	}
	VTUND=$(which vtund)
	# link IP
	[ -x /usr/sbin/ip ] || [ -x /sbin/ip ] && ln -s /sbin/ip /usr/sbin/ip 2>/dev/null
	# instalar-se no sistema
	[ -x /usr/sbin/vtunctl ] || (
		cp -f $SELFSCRIPT /usr/sbin/vtunctl
		chmod +x /usr/sbin/vtunctl
	) 2>/dev/null 1>/dev/null
}

_get_bins(){
	x1=$(which pppd); [ "x$x1" = "x" ] || PPPD=$x1
	x1=$(which ifconfig); [ "x$x1" = "x" ] || IFCONFIG=$x1
	x1=$(which route); [ "x$x1" = "x" ] || ROUTE=$x1
	x1=$(which iptables); [ "x$x1" = "x" ] || FIREWALL=$x1
	x1=$(which ip); [ "x$x1" = "x" ] || IP=$x1
}


_run(){ echo "START vtund"; modprobe tun; modprobe tap; $VTUND -s -f $CNF; }
_kill(){
	echo "KILL vtund"
	killall vtund 2>/dev/null || return
	sleep 1; killall vtund 2>/dev/null || return
	sleep 1; killall -9 vtund 2>/dev/null || return
	sleep 1
}
_isrunning(){ r=$(ps ax | grep vtund | grep -v grep); [ "x$r" = "x" ] && return 1; return 0; }
_keeprunning(){
	while sleep 1; do
		[ -f /tmp/vtun-stop ] && { rm /tmp/vtun-stop; exit 0; }
		_isrunning; isr="$?"
		[ "$isr" = "0" ] && { _kill; _run; }
	done
}
_check(){ _isrunning; exit $?; }
_rerun(){ _isrunning; [ "$?" = "0" ] || { _kill; _run; }; }
# verificar se a opcao de criptografia e' suportada
_filter_crypt_opt(){
	cryptlist="
		yes no
		blowfish128ecb blowfish128cbc blowfish128cfb blowfish128ofb blowfish256ecb blowfish256cbc blowfish256cfb blowfish256ofb
		aes128ecb aes128cbc aes128cfb aes128ofb aes256ecb aes256cbc aes256cfb aes256ofb
	"
	opt_input="$1"
	opt_found="no"
	for opt in $cryptlist; do
		[ "$opt" = "$opt_input" ] && { opt_found="$opt"; break; }
	done
	echo "$opt_found"
}
_filter_compress_opt(){
	# lzo
	# zlib
	compresslist="
		yes no
		zlib:1 zlib:2 zlib:3 zlib:4 zlib:5 zlib:6 zlib:7 zlib:8 zlib:9
		lzo:1 lzo:2 lzo:3 lzo:4 lzo:5 lzo:6 lzo:7 lzo:8 lzo:9
	"
	opt_input="$1"
	opt_found="no"
	for opt in $compresslist; do
		[ "$opt" = "$opt_input" ] && { opt_found="$opt"; break; }
	done
	echo "$opt_found"
}
_filter_yes_no(){
	opt_input="$1"
	opt_found="no"
	[ "$opt_input" = "1" ] && opt_found="yes"
	[ "$opt_input" = "yes" ] && opt_found="yes"
	[ "$opt_input" = "ye" ] && opt_found="yes"
	[ "$opt_input" = "y" ] && opt_found="yes"
	[ "$opt_input" = "true" ] && opt_found="yes"
	echo "$opt_found"		
}
_filter_mode(){
	opt_input="$1"
	opt_found="tun"
	[ "$opt_input" = "tun" ] && opt_found="tun"
	[ "$opt_input" = "l3" ] && opt_found="tun"
	[ "$opt_input" = "ip" ] && opt_found="tun"
	[ "$opt_input" = "ether" ] && opt_found="ether"
	[ "$opt_input" = "l2" ] && opt_found="ether"
	[ "$opt_input" = "bridge" ] && opt_found="ether"
	[ "$opt_input" = "tty" ] && opt_found="tty"
	[ "$opt_input" = "pipe" ] && opt_found="pipe"
	[ "$opt_input" = "true" ] && opt_found="yes"
	echo "$opt_found"		
}
_cfg_get_var(){
	_file="$1"
	_vname="$2"
	_vdefault=""
	#echo "INPUT: _cfg_get_var = _file[$_file] _vname[$_vname] _vdefault[$_vdefault]"
	_vle=$(egrep "#@$_vname=" "$_file" | head -1 | cut -f2 -d=)
	#echo "GET FROM FILE: $_vle"
	[ "x$_vle" = "x" ] && _vle="$_vdefault"
	echo "$_vle"
}
_print_cfg_info(){
	_cfg="$1"
	_server=$(_cfg_get_var "$_cfg" "SERVER")
	_name=$(_cfg_get_var "$_cfg" "NAME")
	_localip=$(_cfg_get_var "$_cfg" "LOCALIP")
	_peerip=$(_cfg_get_var "$_cfg" "PEERIP")
	_mode=$(_cfg_get_var "$_cfg" "MODE" "$MODE")
	_secret=$(_cfg_get_var "$_cfg" "SECRET" "$SECRET")
	_crypt=$(_cfg_get_var "$_cfg" "CRYPT" "$CRYPT")
	_compress=$(_cfg_get_var "$_cfg" "COMPRESS" "$COMPRESS")
	_keepalive=$(_cfg_get_var "$_cfg" "KEEPALIVE" "$KEEPALIVE")
	_persistent=$(_cfg_get_var "$_cfg" "PERSIST" "$PERSIST")
	_port=$(_cfg_get_var "$_cfg" "PORT" "$PORT")
	_proto=$(_cfg_get_var "$_cfg" "PROTO" "$PROTO")
	_device=$(_cfg_get_var "$_cfg" "DEVICE" "$DEVICE")
	echo "* $_name"
	echo "   > config-path...: $_cfg"
	echo "   > server........: $_server $_proto port $_port"
	echo "   > tunnel........: $_mode $_device ~ $_localip <===> $_peerip"
	echo "   > encrypt.......: $_crypt"
	echo "   > options.......: compress=$_compress, keepalive=$_keepalive, persistent=$_persistent"
}
_vpn_status(){
	_cfg="$1"
	_server=$(_cfg_get_var "$_cfg" "SERVER")
	_name=$(_cfg_get_var "$_cfg" "NAME")
	_localip=$(_cfg_get_var "$_cfg" "LOCALIP")
	_peerip=$(_cfg_get_var "$_cfg" "PEERIP")
	# Testar:
	# 1 - obter rota para o ip local
	iprol=$(ip ro get "$_localip" 2>/dev/null | grep 'dev lo')
	[ "x$iprol" = "x" ] && {
		echo "Status: VPN DOWN, local ip down: $_localip"
		return 1
	}
	# 2 - obter rota para o ip remoto
	devpeer=$(ip -o ro get "$_peerip" | sed 's#dev.#|#g;s#.src.#|#g; s#\ ##g' | cut -f2 -d'|' | grep tun)
	[ "x$devpeer" = "x" ] && {
		echo "Status: VPN DOWN, peer ip down: $_peerip"
		return 2
	}
	# OK
	echo "Status: VPN UP, dev $devpeer :: $_localip <===> $_peerip"
	return 0
}
_vpn_client_list(){
	cd "$CNFDIR" || _abort "diretorio nao encontrado: $CNFDIR"
	echo
	echo "VPN VTUN Client List"
	echo "-----------------------------------------------------------------"
	list=$(ls -1 client-* 2>/dev/null)
	if [ "x$list" = "x" ]; then
		echo " (no clients found)"
	else
		# listar
		for _cli in $list; do
			_cfg="$CNFDIR/$_cli"
			echo
			_print_cfg_info "$_cfg"
			# printf '%-10s %-10s\n' $one $four
		done
		echo
	fi
	echo "-----------------------------------------------------------------"
	echo
}
# analisar tuneis criados e obter a interface "tunN"
# livre
_get_free_tundev(){
	tunid="$1"
	[ "x$tunid" = "x" ] && tunid="tun0"
	cd $CNFDIR || { echo "$tunid"; return; }
	# pegar tudo!
	tlist1=$(cat * 2>/dev/null | grep device | awk '{print $2}'| grep tun | sed 's#[^ntu0-9]##g')
	tlist2=$(cat * 2>/dev/null | grep '#@DEVICE=' | cut -f2 -d= | grep tun | sed 's#[^ntu0-9]##g')
	tlist="$tlist1 $tlist2"
	# verificar se o nome desejado pode ser utilizado
	dfound=0
	for dn in $tlist; do [ "$dn" = "$tunid" ] && { dfound=1; break; }; done
	# nao achou, usar o proposto/padrao
	[ "$dfound" = "0" ] && { echo "$tunid"; return 0; }
	# achou, procurar um nome livre
	# LIMITE 128 tuneis, se precisar de mais...
	for tid in $(seq 1 1 128); do
		tn="tun$tid"
		dfound=0
		for dn in $tlist; do [ "$dn" = "$tn" ] && { dfound=1; break; }; done
		[ "$dfound" = "1" ] && continue
		# nao achou, usar esse
		tunid="$tn"
		break
	done
	echo "$tunid"
}

# Coletar argumentos:
#==========================================================================================================
	ARGS="$@"
	while [ 0 ]; do
		#echo "1=[$1] 2=[$2] 3=[$3] 4=[$4] 5=[$5] 6=[$6] 7=[$7] 8=[$8]"
		# Ajuda
		if [ "$1" = "-h" -o "$1" = "--h" -o "$1" = "--help" -o "$1" = "help" ]; then
			_help; exit 0;
		# Comando
		elif [ "$1" = "stop" -o "$1" = "start" -o "$1" = "restart" ]; then
			CMD="$1"; shift; continue
		# Controle
		elif [ "$1" = "list" -o "$1" = "add" -o "$1" = "delete" -o "$1" = "test" ]; then
			CMD="$1"; shift; continue
		# Nome do cliente
		elif [ "$1" = "-n" -o "$1" = "-name" -o "$1" = "--name" ]; then
			_empty_help "$2" 11; NAME="$2"; shift 2; continue
		# Porta do servidor
		elif [ "$1" = "-port" -o "$1" = "--port" -o "$1" = "-p" ]; then
			_empty_help "$2" 12; PORT="$2"; shift 2; continue
		# Protocolo UDP ou TCP
		elif [ "$1" = "-proto" -o "$1" = "--proto" -o "$1" = "-P" ]; then
			_empty_help "$2" 13; PROTO="$2"; shift 2; continue
		# Senha de autenticacao e criptografia
		elif [ "$1" = "-crypt" -o "$1" = "--crypt" -o "$1" = "-c" ]; then
			_empty_help "$2" 14; CRYPT=$(_filter_crypt_opt "$2"); shift 2; continue
		# Nome de interface de rede
		elif [ "$1" = "-d" -o "$1" = "--dev" -o "$1" = "--devname" -o "$1" = "--dev-name" -o "$1" = "--device" ]; then
			_empty_help "$2" 14; DEVICE="$2"; shift 2; continue
		# UDP
		elif [ "$1" = "-u" -o "$1" = "--udp" -o "$1" = "-U" ]; then
			PROTO="udp"; shift; continue
		# TCP
		elif [ "$1" = "-t" -o "$1" = "--tcp" -o "$1" = "-T" ]; then
			PROTO="tcp"; shift; continue
		# Compressao
		elif [ "$1" = "-z" -o "$1" = "--zip" -o "$1" = "-compress" -o "$1" = "compress" ]; then
			COMPRESS="yes"; shift; continue
		# Modo de compressao
		elif [ "$1" = "-Z" ]; then
			_empty_help "$2" 14; COMPRESS=$(_filter_compress_opt "$2"); shift 2; continue
		# Keepalive
		elif [ "$1" = "-K" -o "$1" = "--no-keep" ]; then
			KEEPALIVE="no"; shift; continue
		# Keepalive
		elif [ "$1" = "-P" -o "$1" = "--no-persist" -o "$1" = "--no-persistent" ]; then
			PERSIST="no"; shift; continue
		# IP do servidor
		elif [ "$1" = "-srv" -o "$1" = "--server" -o "$1" = "-s" ]; then
			_empty_help "$2" 15; SERVER="$2"; shift 2; continue
		# IP local no tunel
		elif [ "$1" = "-local" -o "$1" = "--local" -o "$1" = "-l" ]; then
			_empty_help "$2" 16; LOCALIP="$2"; shift 2; continue
		# IP remoto do tunel
		elif [ "$1" = "-r" -o "$1" = "--remote" -o "$1" = "-remote" -o "$1" = "-peer" -o "$1" = "--peer" ]; then
			_empty_help "$2" 17; PEERIP="$2"; shift 2; continue
		# Senha de criptografia
		elif [ "$1" = "-x" -o "$1" = "--secret" -o "$1" = "-secret" -o "$1" = "-pass" -o "$1" = "--pass" -o "$1" = "--password" ]; then
			_empty_help "$2" 18; SECRET="$2"; shift 2; continue
		# DEBUG
		elif [ "$1" = "--debug" -o "$1" = "-D" ]; then
			DEBUG=1
			shift
			continue
		else
			# argumento padrao: NAME
			if [ "x$NAME" = "x" ]; then
				NAME="$1"
				[ "x$1" = "x" ] || { shift; continue; }
			fi
			break
		fi
	done

# Programa
#==========================================================================================================

# Defaults
[ "$PROTO" = "tcp" ] || PROTO=udp
# Debug de variaveis
[ "$DEBUG" = "1" ] && {
	echo "[DEBUG]"
	echo "  CMD.........: $CMD"
	echo
	echo "  VTUND.......: $VTUND"
	echo "  PPPD........: $PPPD"
	echo "  IFCONFIG....: $IFCONFIG"
	echo "  ROUTE.......: $ROUTE"
	echo "  FIREWALL....: $FIREWALL"
	echo "  IP..........: $IP"
	echo "  SELFSCRIPT..: $SELFSCRIPT"
	echo
	echo "  CNFDIR......: $CNFDIR"
	echo
	echo "  NAME........: $NAME"
	echo "  MODE........: $MODE"
	echo "  DEVICE......: $DEVICE"
	echo "  CRYPT.......: $CRYPT"
	echo "  SECRET......: $SECRET"
	echo "  COMPRESS....: $COMPRESS"
	echo "  KEEPALIVE...: $KEEPALIVE"
	echo "  PERSIST.....: $PERSIST"
	echo "  SERVER......: $SERVER"
	echo "  PEERIP......: $PEERIP"
	echo "  LOCALIP.....: $LOCALIP"
	echo "  PORT........: $PORT"
	echo "  PROTO.......: $PROTO"
	echo
}

# Binario vtund precisa estar instalado
_setup

# Adicionar config cliente
#----------------------------------------------------------------------------------------------------------
div="#--------------------------------------------------------"
if [ "$CMD" = "add" ]; then
	_abort_empty "$NAME" "[ADD] Informe o nome da VPN" 51
	_abort_empty "$SERVER" "[ADD] Informe o IP/FQDN do servidor" 52
	_abort_empty "$LOCALIP" "[ADD] Informe o IP local do tunel" 53
	_abort_empty "$PEERIP" "[ADD] Informe o IP remoto do tunel" 54
	_abort_empty "$PORT" "[ADD] Informe a porta do servidor" 55
	_abort_empty "$PROTO" "[ADD] Informe o protocolo (tcp ou udp) do servidor" 56
	_abort_empty "$SECRET" "[ADD] Informe a senha de criptografia e autenticacao do tunel" 56

	# obter nome de interface ou conferir a proposta
	DEVICE=$(_get_free_tundev "$DEVICE")

	_get_bins
	mkdir -p "$CNFDIR" 2>/dev/null
	CFG="$CNFDIR/client-$NAME.conf"
	touch "$CFG"
	# Montar config
	(
		echo "# CMDLINE: $CMDLINE"
		echo
		echo "#@SERVER=$SERVER"
		echo "#@NAME=$NAME"
		echo "#@LOCALIP=$LOCALIP"
		echo "#@PEERIP=$PEERIP"
		echo "#@MODE=$MODE"
		echo "#@SECRET=$SECRET"
		echo "#@CRYPT=$CRYPT"
		echo "#@COMPRESS=$COMPRESS"
		echo "#@KEEPALIVE=$KEEPALIVE"
		echo "#@PERSIST=$PERSIST"
		echo "#@PORT=$PORT"
		echo "#@PROTO=$PROTO"
		echo "#@DEVICE=$DEVICE"
		echo
		echo "options {"
		echo "  timeout   60;"
		echo "  port      $PORT;"
		echo "  syslog    daemon;"
		echo "  ppp       $PPPD;"
		echo "  ifconfig  $IFCONFIG;"
		echo "  route     $ROUTE;"
		echo "  firewall  $FIREWALL;"
		echo "  ip        $IP;"
		echo "}"
		echo "default {"
		echo "  compress $COMPRESS;"
		echo "  speed 0;"
		echo "  proto $PROTO;"
		echo "  type  $MODE;"
		echo "  encrypt  $CRYPT;"
		echo "  keepalive $KEEPALIVE;"
		echo "  persist $PERSIST;"
		echo "}"
		echo
		echo "$NAME {"
		echo "  passwd $SECRET;"
		[ "x$DEVICE" = "x" ] || echo "  device $DEVICE;"
		echo "  up {"
		echo "    ip \"addr add $LOCALIP/32 peer $PEERIP dev %%\";"
		echo "    ip \"link set up dev %%\";"
		echo "  };"
		echo "}"
		echo
	) > $CFG
	echo
	echo "[ADD] Adicionado: $NAME config-path $CFG"
	echo
	exit 0
fi


# Iniciar cliente
#----------------------------------------------------------------------------------------------------------
if [ "$CMD" = "start" ]; then
	_abort_empty "$NAME" "[START] Informe o nome da VPN" 51
	_cfg="$CNFDIR/client-$NAME.conf"
	[ -f "$_cfg" ] || _abort "[START] Cliente nao configurado [$NAME] cfg [$_cfg]"

	# coletar endereco do servidor
	_server=$(_cfg_get_var "$_cfg" "SERVER")
	[ "x$_server" = "x" ] || SERVER="$_server"
	_abort_empty "$SERVER" "[START] Informe o IP/FQDN do servidor" 52

	# exibir informacoes
	_print_cfg_info "$_cfg"

	# verificar se ja esta conectado
	status_msg=$(_vpn_status "$_cfg")
	status_stdno="$?"
	[ "$status_stdno" = "0" ] && {
		echo
		echo "[START] Conexao ja esta UP"
		echo "[START] $status_msg"
		echo
		exit 0
	}

	# subir modulo do kernel
	modprobe tun 2>/dev/null 1>/dev/null

	# gerar link simbolico do binario com o nome da vpn
	XNAME="vtund-$NAME"
	VTUNLINK="/var/run/$XNAME"
	rm -f "$VTUNLINK" 2>/dev/null 1>/dev/null
	ln -s "$VTUND" "$VTUNLINK"

	echo "[START] Iniciando VPN [$NAME] => [$SERVER] : $VTUNLINK -f '$_cfg' '$NAME' '$SERVER'"	
	$VTUNLINK -f "$_cfg" "$NAME" "$SERVER"
	stdno="$?"
	[ "$stdno" = "0" ] || _abort "[START] erro $stdno ao executar: $VTUNLINK -f '$_cfg' '$NAME' '$SERVER'" $stdno
	exit $stdno
fi

# Testar cliente
#----------------------------------------------------------------------------------------------------------
if [ "$CMD" = "test" ]; then
	_abort_empty "$NAME" "[TEST] Informe o nome da VPN" 51
	_cfg="$CNFDIR/client-$NAME.conf"
	[ -f "$_cfg" ] || _abort "[TEST] Cliente nao configurado [$NAME] cfg [$_cfg]"

	# coletar endereco do servidor
	_server=$(_cfg_get_var "$_cfg" "SERVER")
	[ "x$_server" = "x" ] || SERVER="$_server"
	_abort_empty "$SERVER" "[TEST] Informe o IP/FQDN do servidor" 52

	# exibir informacoes
	echo
	echo "[TEST]"
	_print_cfg_info "$_cfg"
	echo

	# status
	status_msg=$(_vpn_status "$_cfg")
	status_stdno="$?"
	echo
	echo "$status_msg"
	echo
	exit $status_stdno

fi

# Listar clientes
#----------------------------------------------------------------------------------------------------------
if [ "$CMD" = "list" ]; then _vpn_client_list; exit 0; fi

# Deletar e parar cliente
#----------------------------------------------------------------------------------------------------------
if [ "$CMD" = "delete" ]; then 
	_abort_empty "$NAME" "[DELETE] Informe o nome da VPN" 51
	_cfg="$CNFDIR/client-$NAME.conf"
	[ -f "$_cfg" ] || _abort "[DELETE] Cliente nao configurado [$NAME] cfg [$_cfg]"

	# Parar
	XNAME="vtund-$NAME"
	VTUNLINK="/var/run/$XNAME"
	killall "$XNAME"

	# Remover
	rm -f "$_cfg" 2>/dev/null

	exit
fi


# Parar cliente
#----------------------------------------------------------------------------------------------------------
if [ "$CMD" = "stop" ]; then 
	_abort_empty "$NAME" "[STOP] Informe o nome da VPN" 51
	_cfg="$CNFDIR/client-$NAME.conf"
	[ -f "$_cfg" ] || _abort "[STOP] Cliente nao configurado [$NAME] cfg [$_cfg]"

	XNAME="vtund-$NAME"
	VTUNLINK="/var/run/$XNAME"
	killall "$XNAME"

	exit
fi

# Reiniciar cliente
#----------------------------------------------------------------------------------------------------------
if [ "$CMD" = "restart" ]; then 
	( $SELFSCRIPT stop $NAME )
	( $SELFSCRIPT start $NAME )
	exit $?
fi


# Nenhum comando capturado, exibir ajuda
_help
exit 1


# Exemplos:
#==========================================================================================================

# Preparar (execute no lado servidor e no lado cliente):
apt-get -y update
apt-get -y install vtund
modprobe tun
mkdir /etc/vtun/


# Exemplo 1 - VPNs L3 - Pacote IPv4/IPv6 sobre VPN vtun IPv4 (ptp)
#----------------------------------------------------------------------------------------------------------

# ********* LADO SERVIDOR:
# Confira se o caminho dos binarios existe, caso seja diferente corrija abaixo:
touch /etc/vtun/server-l3.conf
vi /etc/vtun/server-l3
#--------- [inicio do arquivo]
options {
    timeout   60;
    port      7100;
    syslog    daemon;
    ppp       /usr/sbin/pppd;
    ifconfig  /sbin/ifconfig;
    route     /sbin/route;
    firewall  /sbin/iptables;
    ip        /usr/sbin/ip;
}
default {
    compress no;
    speed 0;
    proto tcp;
    type  tun;
    encrypt  yes;
    keepalive yes;
    persist yes;
}
evevpn01 {
    passwd thebestvpn;
    up {
        ip "addr add 10.247.101.1/32 peer 10.247.101.2 dev %%";
        ip "link set up dev %%";
    };
}
evevpn02 {
    passwd thebestvpn;
    up {
        ip "addr add 10.247.102.1/32 peer 10.247.102.2 dev %%";
        ip "link set up dev %%";
    };
}
#--------- [fim do arquivo]

# executar servidor:
vtund -s -f /etc/vtun/server-l3


# ********* LADO CLIENTE:
#

# Baixe o Script vtunctl.sh
wget https://raw.githubusercontent.com/patrickbrandao/eveunl/master/vtunctl.sh -O /root/vtunctl.sh

# Instale no sistema local:
cp /root/vtunctl.sh /usr/sbin/vtunctl
chmod +x /root/vtunctl.sh /usr/sbin/vtunctl

# Adicione o cliente VTUN:
#  - no exemplo 90.90.90.90 deve ser trocado pelo ip PUBLICO do servidor
#  - aceita redirecionamento de portas de um roteador com ip PUBLICO para um servidor ou VPS/Docker
#
vtunctl add -n evevpn02 -s 90.90.90.90 -l 10.247.102.2 -r 10.247.102.1 -x thebestvpn -c yes -z -p 7100 -d eve02

# Listar VPNs:
vtunctl list

# Inicie a VPN:
vtunctl start evevpn02

# Parar a VPN:
vtunctl stop evevpn02

# Parar e Deletar a VPN:
vtunctl delete evevpn02










