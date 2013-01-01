#!/bin/sh
#
# Höfundur: Samúel Jón Gunnarsson
# Dags: 20130101
#
# Smá debugging tips: watch iptables -nvL sýnir þér hvaða reglur 
# er verið að nota og þú sérð teljarana hækka með aðstoð watch. 
################################################################
echo "Set upp eldvegg með tómat sinnep og steiktum..."
#Hér eru grunnskilgreiningar fyrir eldvegginn þeas. hvaða 
# netkort á að nota fyrir innri og ytri traffík. Hvaða ip-tölur 
# eru á netinu hjá okkur.
################################################################
INNRANET="192.168.11.0/24"
INNRITALA="192.168.11.2/24"
INNRANETKORT="eth0"
YTRANETKORT="eth1"
YTRITALA="`/sbin/ifconfig eth1 | grep 'inet addr' | awk '{print $2}' | sed -e 's/.*://'`"
INTERNET="0/0"
################################################################
echo "    Hleð inn viðbótum í kjarna fyrir NAT og utanumhald tenginga..."
# Byrjum á því að uppfæra "dependencies" fyrir á kjarnamódúla sem eru inni.
/sbin/depmod -a
# Setjum inn þau kjarnamódúl sem hafa með iptables og nöttun að gera.
/sbin/modprobe ip_tables
/sbin/modprobe ip_conntrack
/sbin/modprobe ip_conntrack_ftp
/sbin/modprobe ip_conntrack_irc
/sbin/modprobe iptable_nat
/sbin/modprobe ip_nat_ftp
/sbin/modprobe ip_nat_irc
echo "        Virkja stuðning i kjarna f. IP áframsendingar..."
echo "1" > /proc/sys/net/ipv4/ip_forward
echo "1" > /proc/sys/net/ipv4/ip_dynaddr
echo "        Ytra Netkort er: $YTRANETKORT"
echo "        Ytra Vistfang (iptala) er: $YTRITALA"
echo "        Hleð inn eldveggjareglur..."
echo "            Hreinsa eldri reglur..."
# Hreinsum burt öll reglusett sem voru til fyrir og setjum sjálfgefnar reglur um umferð.
iptables -P INPUT DROP
iptables -F INPUT
iptables -P OUTPUT DROP
iptables -F OUTPUT
iptables -P FORWARD DROP
iptables -F FORWARD
iptables -t nat -F
# Sturta IPTABLES keðju ef hún er tilstaðar.
if [ "`iptables -L | grep hundsa-og-skra`" ]; then
   iptables -F hundsa-og-skra
fi
# Eyða öllum IPTABLES keðjum sem stofnaðar hafa verið af notendum.
iptables -X
# Núllsetja IPTABLES teljara
iptables -Z
# Stofna keðju þar fyrir umferð sem á að hundsa og skrá
iptables -N hundsa-og-skra
iptables -A hundsa-og-skra -j LOG --log-level info
iptables -A hundsa-og-skra -j REJECT
echo -e "          Hleð inn INPUT reglum"
#######################################################################
# INPUT keðjan: Öll traffík sem á að fara inn í gegnum eldveggin.
#######################################################################
iptables -A INPUT -i $INNRANETKORT -s $INNRANET -d 224.0.0.0/4 -j ACCEPT -m comment --comment "Multicast RFC 5771"
iptables -A INPUT -i $INNRANETKORT -s $INNRANET -d 255.255.255.255 -j ACCEPT -m comment --comment "Broadcast - RFC 919"
# Öll umferð inn á loopback neti er leyfð.
iptables -A INPUT -i lo -s $INTERNET -d $INTERNET -j ACCEPT
# Öll umferð inn á innranetkort frá innra neti er leyfð
iptables -A INPUT -i $INNRANETKORT -s $INNRANET -d $INTERNET -j ACCEPT
# Opnanir f. DHCP þjón.
iptables -A INPUT -i $INNRANETKORT -m state --state NEW -m tcp -p tcp --dport 67 -j ACCEPT -m comment --comment "DHCP"
iptables -A INPUT -i $INNRANETKORT -m state --state NEW -m udp -p udp --dport 67 -j ACCEPT -m comment --comment "DHCP"
iptables -A INPUT -i $INNRANETKORT -m state --state NEW -m tcp -p tcp --dport 68 -j ACCEPT -m comment --comment "DHCP"
iptables -A INPUT -i $INNRANETKORT -m state --state NEW -m udp -p udp --dport 68 -j ACCEPT -m comment --comment "DHCP"
# Hundsa traffík og skrá frá ytri tölum sem þykjast vera á innraneti (IP SPoofing). 
iptables -A INPUT -i $YTRANETKORT -s $INNRANET -d $INTERNET -j hundsa-og-skra
# Leyfa tengdri NAT umferð að flæða inn.
iptables -A INPUT -i $YTRANETKORT -s $INTERNET -d $YTRITALA -m state --state ESTABLISHED,RELATED -j ACCEPT
echo "            Opna fyrir umferð frá umheiminum inn á miðlarann"
iptables -A INPUT -i $YTRANETKORT -m state --state NEW,ESTABLISHED,RELATED -p tcp -s $INTERNET -d $YTRITALA --dport 80 -j ACCEPT -m comment --comment "HTTP"
iptables -A INPUT -i $YTRANETKORT -m state --state NEW,ESTABLISHED,RELATED -p tcp -s $INTERNET -d $YTRITALA --dport 443 -j ACCEPT -m comment --comment "HTTPS"
iptables -A INPUT -i $YTRANETKORT -m state --state NEW,ESTABLISHED,RELATED -p tcp -s $INTERNET -d $YTRITALA --dport 8000 -j ACCEPT -m comment --comment "HTTP AJENTI"
iptables -A INPUT -i $YTRANETKORT -m state --state NEW,ESTABLISHED,RELATED -p tcp -s $INTERNET -d $YTRITALA --dport 22 -j ACCEPT -m comment --comment "SSH"
iptables -A INPUT -i $YTRANETKORT -m state --state NEW,ESTABLISHED,RELATED -p udp -s $INTERNET -d $YTRITALA --dport 53 -j ACCEPT -m comment --comment "DNS"
iptables -A INPUT -i $YTRANETKORT -m state --state NEW,ESTABLISHED,RELATED -p tcp -s $INTERNET -d $YTRITALA --dport 53 -j ACCEPT -m comment --comment "DNS"
# Að lokum er öll önnur umferð hundsuð og skráð.
iptables -A INPUT -s $INTERNET -d $INTERNET -j hundsa-og-skra
echo "        Hleð inn OUTPUT reglum"
#######################################################################
# OUTPUT keðjan: Öll traffík sem á að fara út gegnum eldveggin.
#######################################################################
# Öll traffík á loopback netkorti er leyfð.
iptables -A OUTPUT -o lo -s $INTERNET -d $INTERNET -j ACCEPT -m comment --comment "lo -> internet"
# Traffík frá innra netkorti inn á innranet er leyfð.
iptables -A OUTPUT -o $INNRANETKORT -s $INNRITALA -d $INNRANET -j ACCEPT -m comment --comment "eth0 -> INNRITALA -> INNRANET"
# Leyfum multicast og broadcast traffík fyrir UPNP,MDNS og önnur skemmtilegheit.
iptables -A OUTPUT -o $INNRANETKORT -s $INNRANET -d 224.0.0.0/4 -j ACCEPT -m comment --comment "Multicast RFC 5771"
iptables -A OUTPUT -o $INNRANETKORT -s $INNRANET -d 255.255.255.255 -j ACCEPT -m comment --comment "Broadcast - RFC 919"
# Traffík frá ytraneti á ytri tölu inn á innranet er ekki leyfð og því hundsuð og skráð.
iptables -A OUTPUT -o $YTRANETKORT -s $INTERNET -d $INNRANET -j hundsa-og-skra
# Önnur traffík á ytra netkorti er leyfð.
iptables -A OUTPUT -o $YTRANETKORT -s $YTRITALA -d $INTERNET -j ACCEPT
# Að lokum er öll önnur umferð hundsuð og skráð.
iptables -A OUTPUT -s $INTERNET -d $INTERNET -j hundsa-og-skra
echo "         Hled inn FORWARD reglum"
#######################################################################
# FORWARD keðjan: Virkja áframsendingar þeas. IPMASQ. Leyfa allar tengingar út og skilyrtar tengingar inn.
#######################################################################
iptables -A FORWARD -i $YTRANETKORT -o $INNRANETKORT -m state --state ESTABLISHED,RELATED -j ACCEPT -m comment --comment "Umferd fra eth1 inn a eth0"
iptables -A FORWARD -i $INNRANETKORT -o $YTRANETKORT -j ACCEPT -m comment --comment "Umferd fra eth0 inn a eth1"
# Virkja NAT (MASQUERADE) á $YTRANETKORT-i
iptables -t nat -A POSTROUTING -o $YTRANETKORT -j MASQUERADE
echo  "    Eldveggur hefur er nu virkur."
