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
import threading

from kafka import *
from pubsub import pub
import logging

kafka_logger = logging.getLogger('pubsub.udp_bridge')

kafka_logger.debug("importing udp_bridge")

connected = False
kafka_prod = None
kafka_con = None


  
def kafka_subscribe(topicObj=pub.AUTO_TOPIC, data=None):
    global kafka_con
    kafka_init()
    if kafka_con == None:
        print('cannot add topic, consumer not running')
        return
    topic = data['subscribe']['topic']
    kafka_con.add_topic(topic)

# pubsub to kafka

def kafka_send(topicObj=pub.AUTO_TOPIC, data=None):
    global kafka_prod
    kafka_init()
    if not connected:
        return None
    top = topicObj.getName().split('.source(',1)
    top0 = top[0]
    msg = stamp.create_stamp(top0, data)
    xml = xmltodict.unparse(msg)
#    print('before filter:', topicObj.getName(), data, xml)
    if "source(kafka)" not in topicObj.getName():								
        kafka_logger.debug('%d | kafka_send | %s | %s | message: "%s"' % (os.getpid(), topicObj.getName(), msg['publish']['message_id'], msg))
        topic = topicObj.getName().split('.')[0]
#        print('send kafka to ',topic)
        kafka_prod.send(topic, xml.encode('utf-8'))           		
    else:
#        print('block retransmit')
        pass
		
def kafka_init():
    global connected, kafka_con, kafka_prod, connect_str
    if connected == True:
        return
    connect_str = '10.0.1.25:9092'
    for arg in sys.argv:
        if '-c' in arg:
            connect_str = arg[2:]
    print('connecting to kafka at ',connect_str)
    kafka_prod = KafkaProducer(bootstrap_servers=connect_str)
    kafka_con = Consumer()
    kafka_con.start()

    connected = True

class Consumer(threading.Thread):
    daemon = True
    topics = []
    consumer = None
    def __init__(self,topic='aif'):
#        print('new consumer ',self)
        self.topics.extend([topic])
        self.start_time = int(time.time()) * 1000
        super(Consumer, self).__init__()
        
    def add_topic(self,topic):
        kafka_init()
        if topic in self.topics:
            return
        print("adding topic", topic)
        self.topics.extend([topic])
        if not self.consumer == None:
            self.consumer.subscribe(self.topics)
        else:
            print("cannot add topic, consumer not running")

    def run(self):
        self.consumer = KafkaConsumer(bootstrap_servers=connect_str,
                                 auto_offset_reset='earliest')
        self.consumer.subscribe(self.topics)

        for message in self.consumer:
#            print(message.timestamp-self.start_time)
            if message.timestamp < self.start_time:
                continue
            data = message.value.decode()
#            print(message)
            try:
                 kafka_receive(data)
            except:
                 print(sys.exc_info())
	
	


# Heartbeat
def heartbeat():
    while True:
        time.sleep(60)
        pub.sendMessage('aif.infrastructure.fabric.heartbeat',data={'heartbeat':'null'})
		
# _thread.start_new_thread( heartbeat, ())
																							
# kafka to pubsub

current_message = None
current_topic = None

def kafka_receive( data ):
#        print('kafka loop starting')
        kafka_logger.debug("%d | kafka receive | None | None | received data from %s" % (os.getpid(),str('xxx')))

        rcv_dict = xmltodict.parse(data)
        kafka_logger.debug("%d | udp_receive | %s | %s | data received %s" % (os.getpid(), rcv_dict['publish']['topic'],rcv_dict['publish']['message_id'],rcv_dict))
        publish = rcv_dict['publish']
        topic = publish['topic']
        current_topic = topic
        current_message = publish['message_id']
        msg = publish['message']
#        print('publishing to %s'%topic)
        pub.sendMessage(topic+'.source(kafka)', data=msg)
        current_message = None
        current_topic = None		
	
  
pub.subscribe(kafka_send, 'gdb')	
pub.subscribe(kafka_subscribe, 'local.subscribe')




