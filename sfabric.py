

import sys, time, os, subprocess
from pprint import pprint
import json
import argparse
import shlex

parser = argparse.ArgumentParser(prog='run',description='Sentient Fabric')

parser.add_argument('action',help='command to execute in docker')

subparsers = parser.add_subparsers(help='types of commands')
#parser.add_argument("-v", ...)

action_parser = subparsers.add_parser("run")
connect_parser = subparsers.add_parser("connect")
get_parser = subparsers.add_parser("meta")

parser.add_argument('--bridge',help='which bridge to use')

args, remaining = parser.parse_known_args()

'''

run mk_circles --n_sampes 10000

run split

run mk_linear??

run('mk_circles | split | mk_linear ')

start stomp_bridge

start('kafka_bridge')

get metadata

get bridges

get actions

'''

bridges = {"udp":{"package":"udp_bridge","status":"inactive"}, "stomp":{"package":"stomp_bridge","status":"inactive"}, "kafka":{"package":"kafka_bridge","status":"inactive"}}
meta = {}
detach = False


def get_process_arguments(process,path,prog_name='python3'):
    cmd = '%s %s%s -h' % (prog_name,path,process)
    res = subprocess.check_output(shlex.split(cmd))
    parameters = {}
    for argument in str(res).split("--")[1:]:
        param = argument.split(" ")[0]
        descr = " ".join(argument.split(" ")[1:]).strip().replace("\\n","").replace("\t","")
        parameters[param] = {"description":descr}
    return parameters

def start_bridge(args):
    load_bridge(args.bridge)

def load_bridge(bridge):
    global detach
    name = bridges[bridge]['package']
#    name = "package." + name
    print('loading bridge:',name)
    mod = __import__(name, fromlist=[''])
    detach = True
    print('successfully installed bridge: %s'%bridge)
	
def action(args,remain):
    subprocess.check_output(args.action+" ".join(remain),shell=True)


def get_metadata():
    global meta
    print(meta.update(bridges))
    return meta

def get_output(cmd):
    print('shell:',cmd)
    try:
        result = subprocess.check_output(cmd,shell=True)
    except:
        result = 'not argparse format'
    print('result',result)
    return result

def file_contains(fname,sub):
  try:
    with open(fname,'r') as f:
        str = f.read()
        if sub in str:
            return True
        else:
            return False
  except:
    return False
	
def eval_process(cmd,output):
    dct = {"command":cmd, "output":output}
    return dct
	
def construct_cmd(dir,fname):
    return "python %s%s"%(dir,fname)

def save_metadata(data):
    st = json.dumps(data)
    with open('freeflow.json','w') as f:
        f.write(st)
    return data

def build_metadata():
    indir = './'
    meta = {}
    for root, dirs, filenames in os.walk(indir):
        for f in filenames:
          if '.py' in f:
            print(f)		
            abs_f = os.path.join(root, f),
            print(abs_f)
            if file_contains(abs_f[0],'argparse'):
#                cmd = construct_cmd(root,f)
                action = f.split(".")[0]
                meta[action] = {"path":root}
#                out = get_output(cmd+' --help')
                meta[action]['arguments'] = get_process_arguments(f,root)
            else:
                print(f,'not in argparse format')
    return meta

def get_actions():
    global meta
    meta = dict_from_file()

def get_bridges():
    return bridges
	
if args.action == 'run':
    action(args)
elif args.action == 'connect':
    start_bridge(args)
elif args.action == 'meta':
    pprint(get_metadata())
elif args.action == 'build':
    meta = save_metadata(build_metadata())    
	
if detach:
    print('detach')
    while True:
        time.sleep(10.0)
else:
    print('terminating')

		
