import logging
import sys
import time
import subprocess
import re
import daemon
import logging

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

import argparse

monitor_file = 'monitor'

parser = argparse.ArgumentParser(description='Trigger airflow dag based on file events.')

parser.add_argument('--path',required=True,help='Pathname to monitor')
	
parser.add_argument('--pattern',required=True,help='filepatten to match (e.g. .*csv for csv files)')

parser.add_argument('--create', default='None',help='dag_id for create events')

parser.add_argument('--modify', default='None',help='dag_id for modify events')

parser.add_argument('--delete', default='None',help='dag_id for delete events')

parser.add_argument('--move', default='None',help='dag_id for move events')

parser.add_argument('--comment',help='add a comment to monitor file')



args = parser.parse_args()

logging.basicConfig(level=logging.ERROR)

def log_info(msg):
    with open('/home/gvasend/monitor.log','a') as outf:
        outf.write("%s\n"%msg)

class MyEventHandler(FileSystemEventHandler):
    dags = {}
    def __init__(self, observer, pattern):
        self.observer = observer
        self.pattern = pattern

    def on_modified(self, event):
        self.file_event(event.src_path, event, "modify")

    def on_created(self, event):
        self.file_event(event.src_path, event, "create")
        
    def on_deleted(self, event):
        self.file_event(event.src_path, event, "delete")
        
    def on_moved(self, event):
        self.file_event(event.src_path, event, "move")
#            print(arguments)
#            self.observer.unschedule_all()
#            self.observer.stop()

    def file_event(self, filename, event, ev_type):
        log_info("monitor detected event %s for file %s"%(ev_type,event.src_path))
        if monitor_file in filename and ev_type == 'delete':
            print("file monitoring terminated")
            sys.exit(0)
        try:
            m = re.search(self.pattern, event.src_path)
        except:
            log_info("syntax error in regex pattern:%s"%self.pattern)
            raise Exception("syntax error in regex pattern:%s"%self.pattern)
        if not m == None:
            if ev_type in self.dags:
                arguments = ["airflow","trigger_dag","--run_id",event.src_path,"-c",'{"dag_input_file":"%s"}'%event.src_path,self.dags[ev_type]]
                log_info(" ".join(arguments))
                try:
                    subprocess.call(arguments)
                except:
                    log_info("error triggering dag")
        


def init_logger():
    global logger
    logger = logging.getLogger('monitor_logging_daemon')
    logger.addHandler(logging.handlers.SysLogHandler(address='/dev/log'))
    logger.setLevel(logging.INFO)



def main(argv=None):
    path = args.path
    pattern = args.pattern

    observer = Observer()
    event_handler = MyEventHandler(observer, pattern)
    if not args.create == 'None':
        event_handler.dags['create'] = args.create
    if not args.modify == 'None':
        event_handler.dags['modify'] = args.modify
    if not args.delete == 'None':
        event_handler.dags['delete'] = args.delete
    if not args.move == 'None':
        event_handler.dags['move'] = args.move

    observer.schedule(event_handler, path, recursive=False)
    print("monitoring for files in ",path)
    with open(path+monitor_file, 'w') as outf:
        if not args.comment == None:
            outf.write('#%s\n'%args.comment)
        outf.write('%s\n{"pattern":"%s"}\n'%(event_handler.dags,pattern))
    observer.start()
    observer.join()

    return 0

#if __name__ == "__main__":
#    sys.exit(main(sys.argv))



def run():
    with daemon.DaemonContext():
        main(sys.argv)

if __name__ == "__main__":
    run()
