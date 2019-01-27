
#!/usr/bin/env python
import argparse
import datetime
import uuid
import time
import threading
import re
import networkx as nx
import json
#import stomp_bridge
# from pylinkgrammar.linkgrammar import Parser, Linkage, ParseOptions, Link
#import udp_bridge
from pubsub import pub
import xmltodict
import sys
import matplotlib.pyplot as plt
import config
import ff_mongo as mg

try:
    import _thread
    version = '3.X'
except:
    import thread as _thread
    version = '2.7'

from py2neo import authenticate, Graph, Node, Relationship


import logging
print('args',sys.argv)

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Trigger DAG based on a cypher query')

aparser.add_argument('--dag_run',help='dag run id')
aparser.add_argument('--cypher',help='cypher command that generates the query')
aparser.add_argument('--dag_id',help='Id of DAG to trigger')
aparser.add_argument('--limit',type=int,help='limit number of triggers per execution')
aparser.add_argument('--mode',default='execute_v2',choices=['create','execute', 'both','execute_v2','mongo_rcvr'],help='create or execute triggers')
aparser.add_argument('--workflow',default='airflow',choices=['airflow','akka'],help='select workflow system to execute')
aparser.add_argument('--output_dir')
aparser.add_argument('--enable',default='file;text;trigger')


import scrape as sc

sc.neo4j_options(aparser)
sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


import json
import subprocess

def trigger_dag(gr,dag,abs_path='/',context={}, run_id=None):
#    ctx = '"'+json.dumps(context).replace('"','\\"')+'"'
    ctx = "\\'"+json.dumps(context)+"\\'"
    run_id_str = ''
    if run_id:
        run_id_str = ' -r %s ' % run_id
    try:
        cmd = 'airflow trigger_dag %s %s --conf %s'%(run_id_str,dag,ctx)
        print('trigger',cmd)
        if args.mode == 'create':
            airflow_trigger_file(gr,cmd,dag,ctx)
        else:
            airflow_trigger_now(gr,cmd,dag,ctx)            
    except:
        print('trigger failed',dag,abs_path,context)

def process_all_triggers():
    config_dct = config.get_all_config_dct()
    print('configs:',config_dct)
    for cfg in config_dct:
      try:
        data = config_dct[cfg]
        print('data:',data)
        authenticate(data['gdb_url'], data['gdb_user'], data['gdb_password'])
        graph_url = 'http://%s%s'%(data['gdb_url'],data['gdb_path'])
        print('graph url:',graph_url)
        gr = Graph(graph_url)
        if args.mode == 'create' or args.mode == 'both':
            process_triggers(gr,limit_str,{"config_key":cfg})
        if args.mode == 'execute_v2':
            execute_triggers_v2(gr,limit_str,config={"config_key":cfg})
      except Exception as e:
        print('error processing: ',e,cfg)

def graph_run(graph,query):
    print('query:',query)        
    return graph.run(query)

#***********************************

import pymongo

def connect_service(ip, port):
    global fs, client, db, text_collections, change_log
#    print('connect:',ip,port)
    client = pymongo.MongoClient(ip, port)
    db = client.aif_document_db
    change_log = db.change_log
    print('connected to mongo',ip,port)
    
# Recieve Neo4j triggers via Mongo to initiate DAGs

def trigger_dag_node(tr):
    if 'trigger_props' in tr:
        tr.update(tr['trigger_props'])
        del tr['trigger_props']
    if 'createdAt' in tr:
        del tr['createdAt']
    trigger_node = tr['node_id']
    dag_id = tr['dag_id']
    config_key = tr['config_key']
    run_id = tr['run_id']
#    run_id = config_key+"__"+dag_id+"__"+str(trigger_node)
    if '_id' in tr:
        del tr['_id']  # not JSON serializable
    trigger_dag(None,dag_id,context=tr,run_id=run_id)

def new_file(data):
    print('new_file',data)
    fid = data['fid']
    n = argparse.Namespace(addr='73.180.97.70',mongo_port=27017, database='aif_document_db', collection='text_collection', target='.')
    mg.set_namespace(n)
    mg.get_document_name(fid, file_key='filename', output_dir=args.output_dir, overwrite=True)

train_trigger = {}
TRAIN_TRIGGER_DELAY = 600.0
    
def store_text(tr):
    global train_trigger
    print('store_text',tr)
    text_node = tr['node_id']
    text = tr['text']
    config_key = tr['config_key']
    config_dct = config.get_config(config_key)
    if not config_key in train_trigger:
        train_trigger[config_key] = {}
    train_trigger[config_key]['lastChange'] = datetime.datetime.now()        
#    n = argparse.Namespace(config_key=config_dct['config_key'], addr=config_dct['mongo_host'],mongo_port=config_dct['mongo_port'], database=config_dct['mongo_db'], collection=config_dct['mongo_text'], target='.')
    v = vars(args)
    v.update(config_dct)
#    v['config_key'] = config_dct['config_key']
    mg.set_namespace(args)
    mg.create_text(text, node_id=text_node)

"""
def check_model_triggers():
    now = time.now()
    for item in train_trigger:
        if now-item['createdAt'] > TRAIN_TRIGGER_DELAY:
            trigger_dag()
"""
    
# Heartbeat
def heartbeat():
    while True:
        time.sleep(60)
#        check_model_triggers()
_thread.start_new_thread( heartbeat, ())    

def mongo_rcvr():
    connect_service('10.0.1.25',27017)
    try:
        with db.change_log.watch([{'$match': {'operationType': 'insert'}}]) as stream:
            for insert_change in stream:
            # Do something
                doc = insert_change['fullDocument']
                print(doc)
                if 'trigger' in args.enable and doc['subtype'] == 'trigger':
                    trigger_dag_node(doc)
                if 'file' in args.enable and doc['subtype'] == 'file':
                    new_file(doc)
                if 'text' in args.enable and doc['subtype'] == 'text':
                    store_text(doc)                
    except pymongo.errors.PyMongoError:
         # The ChangeStream encountered an unrecoverable error or the
         # resume attempt failed to recreate the cursor.
         raise

def mongo_rcvr_start():    
    _thread.start_new_thread( mongo_rcvr, ())

#*****************
        
def execute_triggers_v2(graph,limit,config={}):
    context = {}
    context.update(config)
    where_str = ' WHERE NOT (t)-[:PROCESSING]->() ' # TODO need to support multiple dags on same node
                                                    # The first processing rel may block rest
                                                    # Maybe ok since like triggers will process at same time
    if not args.dag_id == None:
        where_str += ' AND t.dag_id = "%s" '%args.dag_id
    res = graph_run(graph,'match (t:AirflowTrigger) %s return id(t), t %s '%(where_str,limit_str))
    cnt = 0
    for row in res:
        dag_id = row['t']['dag_id']
        tid = row['id(t)']
        nid = row['t']['node_id']
        try:  
            if args.workflow == 'airflow':
                context.update({"node_id":nid,"trig_id":tid,"dag_id":dag_id})
                ctx = json.dumps(context)
                run_id = config['config_key']+"__"+dag_id+"__"+str(nid)
                cmd = 'airflow trigger_dag %s -r %s --conf \'%s\'' % (dag_id,run_id,ctx)
                print("execute: ",cmd,cnt)
                cnt += 1
                output = subprocess.check_output(cmd,shell=True)
                print(output)
                graph_run(graph,'MATCH (t:AirflowTrigger), (node) WHERE id(node)=%d and id(t)=%d MERGE (t)-[:PROCESSING {state:"running",dag_id:"%s"}]->(node)' % (nid,tid,dag_id))
        except:
            print("execute trigger failed")
        
"""
    Options to record:
        - store in each config gdb 
        - store in central gdb 
        - append to file
        - Message Broker with persistence
        - http server
"""

def airflow_trigger_now(gr,cmd,dag_id,ctx):
    cmd = cmd.replace('\\','')
    subprocess.check_output(cmd, shell=True)

def airflow_trigger_file(gr,cmd,dag_id,ctx):
    cmd = cmd.replace('\\','')
    with open('/home/gvasend/nfs/Simbolika/app/trigger_queue.sh','a') as outf:
        outf.write(cmd+'\n')
            
def airflow_trigger(gr,cmd,dag_id,ctx):
    neo_query(gr,"CREATE (:TriggerCommand {command:'%s', dag_id: '%s', context:'%s' })"%(cmd,dag_id,ctx))

def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def neo_query(graph,q):
    print('neoq',q)
    return graph.run(q)

def get_sol_node(graph,sol):
    data = neo_query(graph,'MATCH (s:SOLNBR)  where s.iname="%s" return s'%(sol))
    sol_node = None
    for s in data:
        sol_node = s['s']
    print('lookup sol',sol_node)
    return sol_node
	
def clean_trigger(query):
    return query.split('return')[0]

return_str = " return id(n), n "
	
def process_triggers(graph,limit_str,config={}):
    where_str = ''
    if not args.dag_id == None:
        where_str = ' WHERE t.dag_id = "%s" '%args.dag_id
    res = graph.run('match (t:trigger {enabled:True}) %s return t'%where_str)
    trigger = None
    for row in res:
        print("processing trigger",row)
        trigger = row['t']
        cypher = clean_trigger(trigger['cypher'])
        print('cypher:',cypher+return_str+limit_str)
        where_str = " and not exists(n.%s) "%trigger['dag_id']
        res1 = graph.run(cypher+where_str+return_str+limit_str)
        n_trigger = 0
        for row1 in res1:
            if not trigger['dag_id'] in row1['n']:
                n_trigger += 1
                row1['n'][trigger['dag_id']] = True
                graph.run("MATCH (n) where id(n)=%d SET n.%s=1"%(row1['id(n)'],trigger['dag_id']))
                config.update({'node_id':row1['id(n)']})
                trigger_dag(graph,trigger['dag_id'],context=config)
        print("total triggers",n_trigger,trigger['cypher'])
        
def execute_triggers(graph,limit_str):
    where_str = ''
    if not args.dag_id == None:
        where_str = ' WHERE t.dag_id = "%s" '%args.dag_id
    res = graph.run('match (t:TriggerCommand) %s return id(t), t '%(where_str)+limit_str)
    cnt = 0
    for row in res:
        cmd = row['t']['command']
        nid = row['id(t)']
        try:
            if args.workflow == 'airflow':
                print("execute: ",cmd,cnt)
                cnt += 1
                output = subprocess.check_output(cmd,shell=True)
                graph.run('MATCH (t:TriggerCommand) WHERE id(t)=%d DETACH DELETE t'%nid)
        except:
            print("execute trigger failed")



# node_trigger
#   cypher: match (f:file) where not exists(f.text) return id(n)
#   freq: hourly
#   dag_id

import os
def trigger_dags(dag_id,query):
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))

    data = neo_query(graph,query)
    for node in data:
        trigger_dag(dag_id, context=node['n'])

def delete_me():
    print('sol dir:',indir)
    for root, dirs, filenames in os.walk(indir):
        for f in filenames:
            fname = os.path.join(root, f)
            finame = fname+"_file"
            data = neo_query(graph,'MATCH (s:SOLNBR)-[]-(f:file) where s.iname="%s" and f.iname="%s" return count(f)'%(sol,finame))
            print(data)
            file_exists = 0
            for cnt in data:
                file_exists = cnt['count(f)']
            print('file exists:',file_exists)
            if file_exists == 0:
                fnode = Node("File", iname=finame, filename=fname)
                graph.create(fnode)
                graph.create(Relationship(sol_node, "has_file", fnode))

                trigger_dag('graph_doc1',context={'document':fname})

if args.mode == 'mongo_rcvr':
    print('Running mongo receiver')
    mongo_rcvr_start()
    while True:
        time.sleep(60)
limit_str =''
if not args.limit == None:
    limit_str = ' limit %s'%args.limit
# process_all_triggers()
print("before auth")
authenticate(args.gdb_url, args.user, args.password)
gr = Graph('%s%s'%(args.gdb_url,args.gdb_path))
if args.mode == 'create' or args.mode == 'both':
    process_triggers(gr,limit_str)
if args.mode == 'execute':
    execute_triggers(gr,limit_str)
if args.mode == 'execute_v2':
    execute_triggers_v2(gr,limit_str)

