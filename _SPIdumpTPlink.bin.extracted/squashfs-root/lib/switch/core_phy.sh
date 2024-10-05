######### Switch APIs for BCM490X/BCM675X board #########

. /lib/bcmenet/bcmenet_4908.sh

wan_ifname=""
wan_unit=""
wan_port=""
lan_ifnames=""

log()
{
    echo $@ >/dev/console
}

get_lan_wan_ifnames()
{
    local wan_sec=$(uci get switch.wan.switch_port)
    wan_ifname=$(uci get switch.${wan_sec}.ifname)
    wan_unit=$(uci get switch.${wan_sec}.unit)
    wan_port=$(uci get switch.${wan_sec}.port)

    lan_ifnames=""
    local lan4_sec=$(uci get switch.lan4.switch_port)
    local lan_list="lan1 lan2 lan3 ${lan4_sec}"
    for lan in ${lan_list}
    do
        local ifname=$(uci get switch.${lan}.ifname)
        [ -n "${lan_ifnames}" ] && lan_ifnames="${lan_ifnames} "
        lan_ifnames="${lan_ifnames}${ifname}"
    done

    #echo "WAN: $wan_ifname, unit $wan_unit port $wan_port" >/dev/console   
    #echo "LAN: $lan_ifnames" >/dev/console 
}

switch_port_ifname_check()
{
    local mismatch=0
    local wan_sec=$(uci get switch.wan.switch_port)
    local lan4_sec=$(uci get switch.lan4.switch_port)
    local interface_list="lan1 lan2 lan3 ${lan4_sec} ${wan_sec}"
    for interface in ${interface_list}
    do      
        local ifname=$(uci get switch.${interface}.ifname)
        local unit=$(uci get switch.${interface}.unit)
        local port=$(uci get switch.${interface}.port)
        local valid=$(uci get switch.${interface}.valid)
        local dev_name=$(ethswctl getifname $unit $port | egrep -o "eth.")
        [ -z "${dev_name}" ] && {
            echo "########## getifname of unit $unit port $port fail, maybe something wrong #######" >/dev/console
            [ x"$valid" == x"0" ] || {
                uci set switch.${interface}.valid=0
                uci set switch.${interface}.ifname="${ifname}_0"
                mismatch=1
            }
            continue
        }
        [ "${dev_name}" == "${ifname}" ] || {      
            echo "########## ifname of unit $unit port $port mismatch, correct #######" >/dev/console
            uci set switch.${interface}.ifname=${dev_name}
            mismatch=1
        }
        [ x"$valid" == x"0" ] && {
            echo "########## ifname of unit $unit port $port gets valid now #######" >/dev/console
            uci set switch.${interface}.valid=1
            mismatch=1
        }
    done

    [ $mismatch -ne 0 ] && {
        uci commit switch
    }
}

phy_port_is_linked () { # dev or dev list
    local dev_list=$1
    
    for dev in ${dev_list}
    do
        local res=$(ethctl $dev media-type | grep -i " Up ")
        if [ -n "$res" ]; then
            return 0
        fi
    done

    return 1
}

phy_lan_is_linked () {  
    phy_port_is_linked "$lan_ifnames"
    return $?
}

phy_wan_is_linked () {  
    phy_port_is_linked "$wan_ifname"
    return $?
}

link_down_phy_port () { # <dev>
    local dev=$1

    ethctl $dev phy-power down
}

link_up_phy_port () {   # <dev>
    local dev=$1

    ethctl $dev phy-power up
}

link_down_lan_ports() {
    for dev in ${lan_ifnames}
    do
        link_down_phy_port $dev
    done

    log "lan ports is linked down!"
}   

link_up_lan_ports () {
    for dev in ${lan_ifnames}
    do
        link_up_phy_port $dev
    done
    
    log "lan ports is linked up!"
}

link_down_wan_ports() {
    for dev in $wan_ifname
    do
        link_down_phy_port $dev
    done

    log "wan ports is linked down!"
}   

link_up_wan_ports () {
    for dev in $wan_ifname
    do
        link_up_phy_port $dev
    done
    
    log "wan ports is linked up!"
}

link_down_all_ports () {
    for dev in $lan_ifnames $wan_ifname
    do
        link_down_phy_port $dev
    done
    
    log "switch ports is linked down!"
}

link_up_all_ports () {
    for dev in $lan_ifnames $wan_ifname
    do
        link_up_phy_port $dev
    done
    
    log "switch ports is linked up!"
}

power_up_all_ports () {
    ethswctl -c powerset-enable -v 1
    link_up_all_ports
}

power_down_all_ports() {
    link_down_all_ports
    ethswctl -c powerset-enable -v 0
}

setup_wan_ports() {
    ethswctl -c wan -o enable -i $wan_ifname
}

unsetup_wan_ports() {
    ethswctl -c wan -o disable -i $wan_ifname
}

#
# add static arl entry of DUT LAN MAC
# non multiport case
#
bcm_set_cpu_lan_mac()
{
	local cpu_port=$(uci get switch.cpu.ports)
	local cpu_unit=$(uci get switch.cpu.unit)
	local mac=`getfirm MAC | sed 's/[-:]//g'`
	if [ $? -eq 0 ] ; then
		ethswctl -c arl -m $mac -x 0xc00${cpu_port} -n $cpu_unit
	fi	
}

pause_enable_lan_ports() { 
    local lan4_port=$(uci get switch.lan4.switch_port)
    local lan_list="lan1 lan2 lan3 ${lan4_port}"
    for lan in ${lan_list}
    do
        local unit=$(uci get switch.${lan}.unit)
        local port=$(uci get switch.${lan}.port)

        bcm_4908_set_pause $unit $port 2
    done
}

pause_disable_lan_ports() { 
    local lan4_port=$(uci get switch.lan4.switch_port)
    local lan_list="lan1 lan2 lan3 ${lan4_port}"
    for lan in ${lan_list}
    do
        local unit=$(uci get switch.${lan}.unit)
        local port=$(uci get switch.${lan}.port)

        bcm_4908_set_pause $unit $port 0
    done
}

setup_cpu_pause() {
    local cpu_unit=$(uci get switch.cpu.unit)
    local cpu_port=$(uci get switch.cpu.ports)
    # 2: enable tx and rx pause
    bcm_4908_set_pause $cpu_unit $cpu_port 2
}

setup_lan_pause() {
    # enable tx and rx pause
    pause_enable_lan_ports
}

setup_wan_pause() {
    # 4: enable rx pause
    bcm_4908_set_pause $wan_unit $wan_port 4
}

setup_all_pause() { 
    setup_wan_pause
    setup_lan_pause
    setup_cpu_pause
}

setup_phy_eee() {
    local if_list="eth0 eth1 eth2 eth3 eth4"
    for intf in ${if_list}
    do
        ethctl ${intf} eee off
    done
}

setup_phy_wirespeed() {
    local if_list="eth0 eth1 eth2 eth3 eth4"
    for intf in ${if_list}
    do
        ethctl ${intf} ethernet@wirespeed enable
    done
}

# 
# $1: auto, 2500F, 1000F, 1000H, 100F, 100H, 10F, 10H
#
bcm_set_wan_phy_mode ()
{
    local err_pre="***error bcm_set_wan_phy_mode()"
    local cmd=""
    local params1=""

    if [ $# -lt 1 ] ; then
        echo  "${err_pre}: at least 1 params required" >&2
        return 1
    fi

    if [ $1 == "auto" ] ; then
        params1="auto"
    elif [[ $1 == "2500F" || $1 == "1000F" || $1 == "1000H" || $1 == "100F" || $1 == "100H" || $1 == "10F" || $1 == "10H" ]] ; then 
        params1="${1}D"
    else
        echo  "${err_pre}: invalid value $1" >&2
        return 1        
    fi

    #local wan_sec=$(uci get switch.wan.switch_port)
    #local wan_ifname=$(uci get switch.${wan_sec}.ifname)

    # ethctl will sleep some seconds, 
    # we don't need waste time to wait it finish
    # so here, let it run at background,
    cmd="ethctl ${wan_ifname} media-type ${params1} &"

    if [ ${debug_this_script} -eq 1 ] ; then
        echo "${cmd}"
    fi

    eval ${cmd}
}

setup_wan_duplex() {
    local wan_sec=$(uci get switch.wan.switch_port)
    local profile=$(uci get switch.${wan_sec}.portspeed)
    local speedname=$(uci get portspeed.${profile}.current)
    
    # note: `ethctl ethx media-type auto' will power on wan phy
    if [ "$speedname" != "auto" ] ; then
        bcm_set_wan_phy_mode ${speedname}
    fi
}

# $1: lan index
get_lan_ifname()
{
    local index=$1
    local lan_sec=""
    
    if [ $index -eq 4 ];then
        lan_sec=$(uci get switch.lan4.switch_port)
    elif [ $index -ge 1 -a $index -le 3 ];then
        lan_sec=lan${index}
    else
        return
    fi
    
    ifname=$(uci get switch.${lan_sec}.ifname)
    echo $ifname
}

# $1 mode: hash algorithm, 0: src mac + dst mac, 1: DA, 2: SA
set_trunk_hashmode ()
{
    local mode=$1

    [ $# != 1 ] && return

    case $mode in
        "0")
            mode="sada"
            ;;
        "1")
            mode="da"
            ;;
        "2")
            mode="sa"
            ;;
        *)
            log "invalid trunk mode $mode!"
            return
            ;;
    esac
    
    ethswctl -c trunk -o $mode
    
    log "trunk hashmode is set to $mode!"
}

get_lan_wan_ifnames
