
#!/usr/bin/env python
print("extractor.py")

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

aparser = argparse.ArgumentParser(description='Graph document')

aparser.add_argument('--document',help='Document filename')

aparser.add_argument('--iname',help='Alternative document filename')
	
aparser.add_argument('--project',default='none',help='Project the document is associated with')

aparser.add_argument('--doc_type',help='Type of document')
	
aparser.add_argument('--document_id',default='this_doc',help='Document ID')

aparser.add_argument('-output_file',help='Grahp output')

aparser.add_argument('--graph_format',default='GraphML',help='')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')
aparser.add_argument('--node')
aparser.add_argument('--filename_attribute')
aparser.add_argument('--mode',choices=['file','direct','text_file','node_graph'],help='')
aparser.add_argument('--node_id',help='')
aparser.add_argument('--limit',default=1000,type=int,help='max number of files to retrieve')
aparser.add_argument('--stdout')



import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)

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
    return Graph('%s/db/data/'%args.gdb_url)
        

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
    text = get_text(fname)
    print(text)
        
def extract_text_direct(file_node):
    global doc_id, current_sent, seq, fo, gr
  
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    graph = Graph('%s/db/data/'%args.gdb_url)

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
        print('extracting ',total_docs,node_id,fname)
        text = get_text(fname)
        if not args.stdout == None:
            print(text)
        if not text == None:
            row['f']['text'] = mg.create_text(text)
            row['f'].push()


def get_text(filename):
    try:
        parsed = parser.from_file(filename)
        return parsed["content"].encode('ascii','ignore') 
    except:
        print('warning, no text found')
        return b'<NO_TEXT>'
    

def extract_file2(filename):
    parsed = parser.from_file(filename)
    text = parsed["content"].encode('ascii','ignore') 
    extract_file1(text, filename)

def extract_node_graph(node_id):
    neo = connect_neo()
    res = neo.run('match (f:file) where id(f)=%s return f'%node_id)
    for row in res:
        fnode = row['f']
    text = mg.get_text(fnode['text'])
    iname = fnode['iname']
    print('create graph ',len(text), iname)
    extract_file1(text, iname)

def extract_file1(text,file_id):
    global gr
    gr = nx.Graph()

    doc_id = uid()

# for each file we have anode representing it as a file and one as a document
    gr.add_node(file_id, label='file_merge_', iname=file_id)
    gr.add_node(doc_id, label='document_merge_', text=text.decode(), iname=file_id) 
    gr.add_edge(file_id, doc_id, label='document')

gr = None
if __name__ == '__main__':
    if args.output_file == None:
        setattr(args, 'output_file', "graph_out_"+str(uid())+'.'+args.graph_format.lower())
    if args.document == None:
        setattr(args, 'document', args.iname)


# this app is officially a mess. 
#    outf = open(args.output_file,'w')
    if args.mode == 'node_graph':    
        extract_node_graph(args.node_id)
    if args.mode == 'file':    
        extract_file1(args.document, args.project, args.doc_type, args.document_id)
    if args.mode == 'text_file':    
        extract_text_file(args.document)
    if args.mode == 'direct':
        setattr(args, 'graph_format', "None")
        if args.node_id == None:
            extract_text_direct_all()
        else:
            extract_text_direct(args.node_id)
        sys.exit(0)
    if args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(gr, args.output_file)
    sc.write_dict({'graph_output':args.output_file})

#    outf.close()
    
