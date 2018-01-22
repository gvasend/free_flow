import time
import sys
import uuid
import datetime
import socket
import os

# create a stamp to mark each publish message 

def create_stamp(topic, message):
    now = datetime.datetime.now().strptime("30 Nov 00", "%d %b %y")
    message_topic = topic.replace(".",".")
    host = socket.gethostname()
#    pid = thread.get_ident()
    ipid = os.getpid()
    pid = "python_"+str(ipid)
    msg_id = uuid.uuid1()
    dct = { 'publish': {'time':now, 'pid':pid, 'host':host, 'topic':message_topic, 'message_id':msg_id, 'message':message} }
    return dct



st = create_stamp('aif.knowledge.gdb', 'test message')

