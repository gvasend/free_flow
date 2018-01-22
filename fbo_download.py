
#!/usr/bin/env python
import argparse
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
import ff_mongo as mg
from tika import parser

from py2neo import authenticate, Graph, Node, Relationship


import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Define a classification problem')
aparser.add_argument('--input_graph',default='*graph_output',help='Graph filename')
aparser.add_argument('-graph_output',default='tbd',help='Graph filename')
aparser.add_argument('--delete_all',default='False',help='Delete graph db (True/False)')
aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')



def neo_query(st):
    print('query:',st)
    return graph.run(st)

def train():
# train a give classifier
    graph.query('match (cp:classification_problem)')
 
 
def download_sol(sol,date):
    dirp = "./Files/%s"%sol
	abs_file(dirp, abs_dir),
	make_dir_if_not(abs_dir),
	solicitation_link(sol, link),
	get_url(link, reply),
	parse_files(reply, files),
	for name in files:
        url = 'http://www.fbo.gov'+file
        full_name = abs_dir+'/'+name
        doc_type = categorize_file(name)
        gr.add_node(FullName, file, [filename=File, url=URL, solnbr=SolNbr, doc_type=DocType]),
        once(
         	fcypher_query('match (n:SOLNBR) where n.iname="~w" return id(n)',[SolNbr],row([SolId]))
        ;
            SolId=SolNbr
        ),
        gr.add_edge(_, SolId, FullName, hasFile, [])
        


def download_file(link,fname): 
	http_open(link, Str, [cert_verify_hook(user:cert_verify)]), 
%	read_stream_to_codes(Str, Codes), 
%	atom_codes(Reply, Codes), 
	increment(download_attempt),
	open(File, write, W, [type(binary)]),
	copy_stream_data(Str, W),
	close(Str),
	close(W),
	increment(download_complete),
	log_message(download(Link,File)).
    
def run():
    res = graph.run('match (c:check) where c.type="download" and c.status="pending" return c')
    for row in res:
        check = row['c']
        sol = check['solnbr']
        check_download(sol)
            
def connect_neo():
    global graph
    authenticate('localhost:7474', 'neo4j', 'N7287W06')
    graph = Graph('localhost:7474/db/data/')

def make_cp():
# create a new classification problem
    print("creating classification problem")
    graph.run('CREATE CONSTRAINT ON (cp:classification_problem) ASSERT cp.iname IS UNIQUE ')
    cp = Node("classification_problem", iname=args.name+"_"+args.node+"_"+args.class_attribute+"_"+args.text_attribute, name=args.name, class_attribute=args.class_attribute, feature_attribute=args.text_attribute, state='created', node=args.node, select_category=args.select_category)

    graph.merge(cp)
    
    empirical = create_empirical(cp, training_label=args.training_label, classifier='classify_document')
    graph.create(Relationship(cp, "has_classifier", empirical))


def create_empirical(cp, training_label=None, classifier=None):
# register the "empirical" classifier
    t_label = training_label
    cl = classifier
    res = graph.run('match (f:%s) where f.%s="%s" and exists(f.%s) return count(f)'%(cp['node'],t_label,cp['select_category'],t_label))
    for cnt in res:
        total_cat = cnt['count(f)']
    res = graph.run('match (f:%s) return count(f)'%(cp['node']))
    for cnt in res:
        total_nodes = cnt['count(f)']
    coverage = float(total_cat)/float(total_nodes)
    cl = Node('classifier', label='classifier', training_label=t_label, classifier=cl, type='empirical')
    graph.merge(cl)
    cl['total_categorized'] = total_cat
    cl['total_nodes'] = total_nodes
    cl['coverage'] = coverage
    cl['accuracy'] = 1.0
    cl.push()
    return cl

def extract_text_direct():
# load document text into MongoDB
    global doc_id, current_sent, seq, fo, gr
    res = graph.run('match (f:file) where not exists(f.text) and exists(f.iname) return count(f)')
    for row in res:
        total_docs = row['count(f)']
    res = graph.run('match (f:file) where not exists(f.text) and exists(f.iname) return id(f), f')
    this_doc = 0
    for row in res:
        this_doc += 1
        frac_complete = float(this_doc) / float(total_docs)
        node_id = row['id(f)']
        fname = row['f']['iname']
        print('extracting ',this_doc,frac_complete,node_id,fname)
        text = get_text(fname)
        if not text == None:
            row['f']['text'] = mg.create_text(get_text(fname))
            row['f'].push()


def get_text(filename):
    try:
        parsed = parser.from_file(filename)
        return parsed["content"].encode('ascii','ignore') 
    except:
        print(str(sys.exc_info()[0]))
        return str(sys.exc_info()[0])

def capture_all_text():
    res = graph.run('match (f:file) where exists(f.text) return f')
    for row in res:
        node = row['f']
        text_id = mg.create_text(node['text'])
        node['text_id'] = text_id
        node['text'] = None
        node.push()

def mongo():
    res = graph.run('match (f:file) where exists(f.text) return f')
    for row in res:
        node = row['f']
        text_id = mg.create_text(node['text'])
        node['text_id'] = text_id
        node['text'] = None
        node.push()


import scrape as sc
sc.model_options(aparser)
sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


connect_neo()

    run()
    
