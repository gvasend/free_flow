
#!/usr/bin/env python
print("extractor.py")

"""
node extract 
   1) Fetch node
   2) Localize file
   3) Extract text
   4) Store Text node
   
   fetch_local_extract_text
"""

import boto3
import botocore
import subprocess
import argparse
from ffparse import FFParse
import uuid
import time
import threading
import re
import networkx as nx
import json
#import stomp_bridge
# from pylinkgrammar.linkgrammar import Parser, Linkage, ParseOptions, Link
#import udp_bridge
import tika
import xmltodict
import sys
tika.initVM()
from tika import parser
import ff_mongo as mg

from py2neo import authenticate, Graph, Node, Relationship

current_sent = None

import logging


print("extractor")

fo = None

seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = FFParse(description='Graph document')

aparser.add_argument('--document',help='Document filename')

aparser.add_argument('--iname',help='Alternative document filename')
	
aparser.add_argument('--project',default='none',help='Project the document is associated with')

aparser.add_argument('--doc_type',help='Type of document')
	
aparser.add_argument('--document_id',default='this_doc',help='Document ID')

aparser.add_argument('-output_file',help='Grahp output')

aparser.add_argument('--graph_format',choices=['GraphML','GEXF','Neo4j'],default='GraphML',help='')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')
aparser.add_argument('--node')
aparser.add_argument('--filename_attribute')
aparser.add_argument('--mode',choices=['file','direct','text_file','node_graph','node_direct','test'],help='')
aparser.add_argument('--node_id',help='')
aparser.add_argument('--limit',default=1000,type=int,help='max number of files to retrieve')
aparser.add_argument('--stdout')
aparser.add_argument('--node_label',default='Text')
aparser.add_argument('--store',choices=['node','mongo'],default='node')


aparser.all_options()

args = aparser.parse_args()

aparser.log("extractor %s" % args)

def uid():
    return str(uuid.uuid1())

def n_lower_chars(string):
    return sum(1 for c in string if c.islower())

def passtwo(textin):
    sent_list = []
    text1 = textin.split("\n")
    for line in text1:
#        print "passtwo ",line
        ln = len(line)
        if ln < 5:
 #           print "line dropped, too short ",line
            continue
        lower_count = n_lower_chars(line)
        lower_percent = float(lower_count)/float(ln)
 #       print "total ",ln," lower ",lower_percent
        if lower_percent > 0.1 or line.endswith('.'):
            sent_list.append(line)
        elif lower_percent <= 0.1:
            process_sentence(line)
    sent = ' '.join(sent_list)
    process_sentence(sent)
	
	
def extract_file(filename,proj,doc_type,id):
    try:
        extract_file1(filename,proj,doc_type,id)
    except:
        print("error processing ",filename)

import os

def connect_neo():
  
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    return Graph('http://%s/db/data/'%args.gdb_url)
        

def extract_text_direct_all():
    global doc_id, current_sent, seq, fo, gr
  
    graph = connect_neo()

    dt_filter = ''
    if not args.doc_type == None:
        dt_filter = ' and f.doc_type="%s" '%args.doc_type
        print('document type',dt_filter)

    res = graph.run('match (f:file) where exists(f.iname) and not exists(f.text) %s return id(f), f limit %d'%(dt_filter, args.limit))
    total_docs = 0
    for row in res:
        total_docs += 1
        node_id = row['id(f)']
        fname = row['f']['iname']
        print('extracting ',total_docs,node_id,fname)
        text = get_text(fname)
        if not text == None:
            row['f']['text'] = mg.create_text(text)
            row['f'].push()

def extract_text_file(fname):
    global gr
    text = get_text(fname)
    print(text)
        
def extract_text_direct(file_node):
    global doc_id, current_sent, seq, fo, gr

    print("connect to %s"%args.gdb_url)  
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    graph = Graph('http://%s/db/data/'%args.gdb_url)

    dt_filter = ''
    if not args.doc_type == None:
        dt_filter = ' and f.doc_type="%s" '%args.doc_type
        print('document type',dt_filter)
    res = graph.run('match (f:file) where id(f)=%s and not exists(f.text) return id(f), f'%file_node)
    total_docs = 0
    for row in res:
        total_docs += 1
        node_id = row['id(f)']
        fname = row['f']['iname']
        print("extracting ",fname)
        if '_file' in fname:
            fname = fname.split("_file")[0]
        print('extracting ',total_docs,node_id,fname)
        text = get_text(fname)
        if not args.stdout == None:
            print(text)
        if not text == None:
            row['f']['text'] = mg.create_text(text)
            row['f'].push()
    print("total documents",total_docs)


def get_text(filename):
    try:
        parsed = parser.from_file(filename)
        return parsed["content"].encode('ascii','ignore') 
    except:
        print('warning, no text found')
        return b'<NO_TEXT>'
    
def get_text1(filename):
        print("get_text",filename)
        parsed = parser.from_file(filename)
        print(parsed)
        return parsed["content"].encode('ascii','ignore') 

def node_localize_extract_store():
    node()
    localize()
    extract()
    store()

# Building blocks

node_dct = None
local_filename = None
extracted_text = None

def node():
    global node_dct
    neo = connect_neo()
    qry = 'match (f) where id(f)=%s return f'% (args.node_id)
    print('fetch node: ',qry)
    res = neo.run(qry)
    for row in res:
        node_dct = row['f']
    if node_dct == None:
        raise Exception('Node id not found')
        
def localize():
    global local_filename
    storage = node_dct.get('storage_type','local')
    if storage == 'local':
        local_filename = node_dct['abs_path']
    elif storage == 's3':
        path = node_dct['abs_path']
        path_lst = path.split(':::')
        arn_name = path_lst[0]
        bucket_filename = path_lst[1]
        file_lst = bucket_filename.split('/')
        bucket_name = file_lst[0]
        filename = "/".join(file_lst[1:])
        local_filename = '/tmp/'+filename
        print(path,path_lst,bucket_filename,file_lst,filename,local_filename)
        download_file(bucket_name,filename,local_filename)        
        subprocess.call('ls -l %s' % local_filename,shell=True) # debug purposes

def download_file(bucket,key,local_file):
    s3 = boto3.resource('s3')
    try:
        s3.Bucket(bucket).download_file(key, local_file)
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            print("The object does not exist.")
        else:
            raise
        
def extract():
    global extracted_text
    try:
        parsed = parser.from_file(local_filename)
        extracted_text = parsed["content"]
    except Exception as e:
        print('warning, no text found',e)
        extracted_text = None
#    print('extracted text:',extracted_text)
        
def store():
    global extracted_text
    neo = connect_neo()
    if extracted_text:
        extracted_text = extracted_text.replace('\\','\\\\').replace("'","\\'").replace('"','\\"')
        if args.store == 'mongo':
#            n = argparse.Namespace(addr='73.180.97.70',mongo_port=27017, database='aif_document_db', collection='text_collection', text_store='mongo')
            mg.set_namespace(args)
            extracted_text = mg.create_text(extracted_text)
        qry = 'match (f) where id(f)=%s MERGE (f)-[:TEXT]->(:Text:stream {text:"%s"}) '% (args.node_id,extracted_text)
        print('store query:',qry)
        res = neo.run(qry)
    else:
        qry = 'match (f) where id(f)=%s SET f.extract_status="extract_error" '% (args.node_id)
        print('no text:',qry)
        res = neo.run(qry)

# End building blocks
    

def extract_file2(filename):
    parsed = parser.from_file(filename)
    text = parsed["content"].encode('ascii','ignore') 
    extract_file1(text, filename)

def stringify(text):
    if not type(text) == str:
        return text.decode()
    return text

def extract_node_graph(node_id):
    neo = connect_neo()
#    n = argparse.Namespace(addr='73.180.97.70',mongo_port=27017, database='aif_document_db', collection='text_collection', text_store='mongo')
    mg.set_namespace(args)
    qry = 'match (f:Text)-[]-(file:File) where id(f)=%s return f,file'% (node_id)
    print('find node ',qry)
    res = neo.run(qry)
    fnode = None
    for row in res:
        fnode = row['f']
        file_node = row['file']
        print('found node',fnode)
    if not fnode:
        raise Exception('unable to find node in the database')
    print(fnode)
    text = mg.get_text(fnode['text'])
    iname = file_node['iname']
    print('create graph ',len(text), iname)
    extract_file1(text, iname)

def extract_file1(text,file_id):
    global gr
    gr = nx.Graph()

    doc_id = uid()
    text = stringify(text)

# for each file we have anode representing it as a file and one as a document
#    gr.add_node(file_id, label='file_merge_', iname=file_id, merge_with=file_id)
    gr.add_node(doc_id, label='DocumentRoot', text=text, iname='DocumentRoot_'+file_id, linkTo=file_id) 
#    gr.add_edge(file_id, doc_id, label='document')

gr = None
if __name__ == '__main__':
    if args.output_file == None:
        graph_out = "graph_out_"+str(uid())+'.'+args.graph_format.lower()
        print('graph_out',graph_out)
        graph_out = aparser.get_tmp(graph_out)
        setattr(args, 'output_file', graph_out)
    if args.document == None:
        setattr(args, 'document', args.iname)


# this app is officially a mess. 
#    outf = open(args.output_file,'w')
    if args.mode == 'node_graph':    
        extract_node_graph(args.node_id)
    if args.mode == 'test':    
        print(get_text(args.document))
    if args.mode == 'node_direct':    
        node_localize_extract_store()
    if args.mode == 'file':    
        extract_file1(args.document, args.project, args.doc_type, args.document_id)
    if args.mode == 'text_file':    
        extract_file2(args.document)
    if args.mode == 'direct':
        setattr(args, 'graph_format', "None")
        print("direct mode")
        if args.node_id == None:
            extract_text_direct_all()
        else:
            extract_text_direct(args.node_id)
        sys.exit(0)
    if gr and args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif gr and args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif gr and args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(gr, args.output_file)
    if gr:
        aparser.write_dict({'graph_output':args.output_file})

#    outf.close()
    
