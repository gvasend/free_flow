import time
import sys
import xmltodict
import os
try:
    import _thread
    version = '3.X'
except:
    import thread as _thread
    version = '2.7'
import stamp

import socket
from pubsub import pub
import logging

udplogger = logging.getLogger()

udplogger.debug("importing udp_bridge")

connected = False

# udp_bridge - exchange broadcasts between internal pubsub and UDP

UDP_IP = '10.0.1.25'
UDP_PORT_BASE = 8889

sock = socket.socket(socket.AF_INET, # Internet
                     socket.SOCK_DGRAM) # UDP

def set_addr(addr):
    global UDP_IP
    UDP_IP = addr
    reset_udp()
def set_port(port):
    global UDP_PORT_BASE
    UDP_PORT_BASE = port
    reset_udp()

def reset_udp():	
    global connected
    ip_delta = 0					 
    while True:
        try:
            sock.bind(('', UDP_PORT_BASE+ip_delta))					# Continue incrementing port number if port is already taken. This allows multiple bridges to be running on the same host.
            udplogger.debug("connected udp_bridge: %s %d" % (UDP_IP, UDP_PORT_BASE+ip_delta))
            connected = True
            break
        except:
            ip_delta += 1
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        udp_rcv = _thread.start_new_thread( udp_receive, ("udp_receive", ) )
        udp_receive.daemon = True																# TODO - thread needs to be flagged as a daemon. Also needs to be ported to new _thread module as thread is depreciated.
    except:
        udplogger.error("unable to start udp receive thread")
   
#todo udp_configure not fully implemented/tested. 

def udp_configure(topicObj=pub.AUTO_TOPIC, data=None):
    global sock, UDP_IP, UDP_PORT_BASE
    udp_bridge_data = data['udp_bridge']
    UDP_PORT_BASE = udp_bridge_data['port']
    udplogger.debug("configure udp: %s"%(str(udp_bridge_data)))
    socket.disconnect()
    sock = socket.socket(socket.AF_INET, # Internet
                     socket.SOCK_DGRAM) # UDP
    ip_delta = 0					 
    while True:
        try:
            sock.bind((UDP_IP, UDP_PORT_BASE+ip_delta))					# Continue incrementing port number if port is already taken. This allows multiple bridges to be running on the same host.
            print("connected udp_bridge: ", UDP_IP, UDP_PORT_BASE+ip_delta)
            break
        except:
            ip_delta += 1
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
	

# pubsub to UDP

def udp_send(topicObj=pub.AUTO_TOPIC, data=None):
    global sock
    udplogger.info("udp send")
    if not connected:
        return None
    top = topicObj.getName().split('.source(',1)
    top0 = top[0]
    msg = stamp.create_stamp(top0, data)
    xml = xmltodict.unparse(msg)
#    print('before filter:', topicObj.getName(), data, xml)
    if "source(udp)" not in topicObj.getName():								
        udplogger.debug('%d | udp_send | %s | %s | message: "%s"' % (os.getpid(), topicObj.getName(), msg['publish']['message_id'], msg))
        if version == '3.X':
            sock.sendto(bytes(xml,'utf-8'), ('<broadcast>', UDP_PORT_BASE))				
            sock.sendto(bytes(xml,'utf-8'), ('<broadcast>', UDP_PORT_BASE+1))
        else:
            sock.sendto(xml, ('<broadcast>', UDP_PORT_BASE))									# TODO - this is cheating a bit. Ideally need to track which ports are being used and rebroadcast on all those ports.
            sock.sendto(xml, ('<broadcast>', UDP_PORT_BASE+1))									# TODO - this is cheating a bit. Ideally need to track which ports are being used and rebroadcast on all those ports.
            		

# Heartbeat
def heartbeat():
    while True:
        time.sleep(60)
        pub.sendMessage('aif.infrastructure.fabric.heartbeat',data={'heartbeat':'null'})
		
# _thread.start_new_thread( heartbeat, ())
																							
# UDP to pubsub

current_message = None
current_topic = None

def udp_receive( threadName ):
    global current_message, current_topic
#    self.daemon = True
    udplogger.debug("udp receiver thread starting")
    while True:
        data, addr = sock.recvfrom(1024) # buffer size is 1024 bytes						# UDP is limited in size. All messages will need to fit in this this size. Need to configure to max size (TODO)
        udplogger.debug("%d | receive | None | None | received data from %s" % (os.getpid(),str(addr)))
        if False:
            continue
        rcv_dict = xmltodict.parse(data)
        udplogger.debug("%d | udp_receive | %s | %s | data received %s" % (os.getpid(), rcv_dict['publish']['topic'],rcv_dict['publish']['message_id'],rcv_dict))
        publish = rcv_dict['publish']
        topic = publish['topic']
        current_topic = topic
        current_message = publish['message_id']
        msg = publish['message']
        msg['received_from'] = addr															# Add sender address to message. Should not interfere with normal use of the message.
#        print("UDP to pubsub:", "(", addr, ")", topic, _thread.get_ident(), msg)
#        print "publish:", topic, msg
        pub.sendMessage(topic+'.source(udp)', data=msg)
        current_message = None
        current_topic = None		
	
def host_self(h2):
    udplogger.info("log: %s"%h2)
    h1 = socket.gethostname()
    h1a = socket.gethostbyaddr(h1)[0]
    h2a = socket.gethostbyaddr(h2)[0]
    if h1a in h2a or h2a in h1a:
#        print("host is self")
        return True
    else:
#        print("host is not self")
        return False

pub.subscribe(udp_configure, 'ff.udp_configure')	
   
pub.subscribe(udp_send, 'ff')	


