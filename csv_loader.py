
#!/usr/bin/env python
import platform
platform.python_version()

import os
import argparse
import uuid
import time
import threading
import uuid
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

from py2neo import authenticate, Graph, Node, Relationship


import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0
MERGE_CUTOFF = 10                # use create when importing nodes with more than 5 attributes


def uid():
    return str(uuid.uuid1())

def delete_file(path):
    print('delete file',path)
    os.remove(path)

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Load graph')
aparser.add_argument('-graph_output',help='Graph filename')
aparser.add_argument('--input_graph',default='*graph_output',help='Graph filename')
aparser.add_argument('--delete_all',default='False',help='Delete graph db (True/False)')
aparser.add_argument('--gdb_url',default='10.0.1.25:7474',help='Graph db URL')
aparser.add_argument('--plot_graph',default='False',help='Plot graph (True/False')
aparser.add_argument('--clean',default=True,type=bool)
aparser.add_argument('--uid',default='csv_id')
aparser.add_argument('--node_creation',default='create')
aparser.add_argument('--periodic_commit',type=int,default=0)





import scrape as sc

fpref = '/home/gvasend/gv-ML-code/freeflow/'

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

periodic_commit = ''
if args.periodic_commit > 0:
    periodic_commit = "USING PERIODIC COMMIT %d"%args.periodic_commit

def load_graph(Filename):
    return nx.read_graphml(Filename)

gr = load_graph(args.input_graph)

int_id = 0
def unique_int():
    global int_id
    int_id += 1
    return int_id

def clean_label(label):
    return label.replace("_merge_","").replace("_create_","")

def clean_dict(dct):
    if 'label' in dct:
        dct['label'] = clean_label(dct['label'])
    clean = {}
    for key, value in dct.items():
        clean[key] = clean_value(value)
    return clean

def clean_value(value):
    if args.clean == False:
        return value
    if type(value) == str:
        return value.replace("\\","").replace("\n","").replace('"','').replace("'","")
#    print(value)
    return value

node_file = {}
edge_file = {}

import csv
def csv_import(gr):
    global node_file, edge_file
# do a csv import of a networkx graph. each node and edge type is written as a csv file. the import cypher is written last and executed

    label_attr = nx.get_node_attributes(gr,'label')
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    graph = Graph('%s/db/data/'%args.gdb_url)

    if args.delete_all == 'True':
        graph.delete_all()
    
    label_list = []
    id_map = {}
    node_cypher = {}
    for n,d in gr.nodes_iter(data=True):
#        print("n ",n,"d ",d)
        if 'label' in d:
            label_list.extend([d['label']])
    label_set = set(label_list)
    print('label set',label_set)
    for label in label_set:
        dct_list = []
        key_set = set(['label','iname'])
        total_cnt = 0
        for n,d in gr.nodes_iter(data=True):
            if 'label' in d and d['label'] == label:
                total_cnt += 1
                if args.uid == 'csv_id':
                    d_prime = {'csv_id':unique_int()}
                else:
                    d_prime = {}
                d_prime.update(clean_dict(d))
                dct_list.extend([d_prime])
                key_set.update(set(d_prime.keys()))
                if not args.uid in d_prime:
#                    print('added index ',args.uid,label)
                    d_prime[args.uid] = uid()
                id_map[n] = d_prime[args.uid]
        print("total for ",label,total_cnt)
        total_cnt = 0
        temp_fname = get_temp_fname(label,'csv')
        node_file[label] = temp_fname
        with open(fpref+temp_fname, 'w') as of:
            w = csv.DictWriter(of,key_set)
            w.writeheader()
            w.writerows(dct_list)
        node_cypher[label] = dct_list[0].keys()

    edge_cypher = {}
    edge_node_label = {}
    edge_labels = []            
    for u,v,d in gr.edges_iter(data=True):
#        print("edge ",u,v,"data",d)
        if 'label' in d:
            edge_labels.extend([d['label']])
    edge_set = set(edge_labels)
    print('edge set',edge_set)
    total_cnt = 0
    for edge_label in edge_set:
        edge_list = []
        for u,v,d in gr.edges_iter(data=True):
#            print("edge ",u,v,"data",d)
            if 'label' in d and d['label'] == edge_label:
                total_cnt += 1
                edge_dct = {'from':id_map[u],'to':id_map[v]}
                edge_dct.update(d)
                edge_list.extend([edge_dct])
                edge_node_label[edge_label] = {'from':label_attr[u],'to':label_attr[v]}
#        print('edge list',edge_list)
        print("total for ",label,total_cnt)
        total_cnt = 0
        temp_fname = get_temp_fname(edge_label,'csv')
        edge_file[edge_label] = temp_fname
        with open(fpref+temp_fname, 'w') as of:
            w = csv.DictWriter(of,edge_list[0].keys())
            w.writeheader()
            w.writerows(edge_list)                
        edge_cypher[edge_label] = edge_list[0].keys()

    pref = "%s LOAD CSV WITH HEADERS FROM"%periodic_commit
    for key, value in node_cypher.items():
        node_label = key
        node_create = args.node_creation
        if len(value) > MERGE_CUTOFF:       # a bit of a kludge. we don't want to use merge on the "primary" nodes for performance reasons
            node_create = 'create'
        if '_merge_' in key:
            node_create = 'MERGE'
            node_label = key.replace("_merge_","")
        if '_create_' in key:
            node_create = 'CREATE'
            node_label = key.replace("_create_","")
        print('importing',key)
        temp_fname = node_file[key]
        fname = "file:///"+temp_fname
        query1 = ' %s "%s" AS csvLine %s (p:%s %s) ' %(pref,fname,node_create,node_label,import_spec(value))
        query2 = 'CREATE CONSTRAINT ON (n:%s) ASSERT n.%s is UNIQUE; ' %(node_label,args.uid)
        query3 = 'CREATE CONSTRAINT ON (n:%s) ASSERT n.iname is UNIQUE; ' %(node_label)
        query4 = 'CREATE INDEX ON :%s(iname) ' %(key)

 

        print('query:',query1,query2)
        graph.run(query2)
        graph.run(query1)
        try:
            graph.run(query4)
        except:
            print('index already exists')
        delete_file(fpref+temp_fname)
    for key, value in edge_cypher.items():
        temp_fname = edge_file[key]
        fname = "file:///"+temp_fname
        from_lab = clean_label(edge_node_label[key]['from'])
        to_lab = clean_label(edge_node_label[key]['to'])
        from_spec = get_id_spec(args.uid,"from")
        to_spec = get_id_spec(args.uid,"to")
        q1 = '%s "%s" AS csvLine MATCH (x:%s { %s }),(y:%s { %s}) MERGE (x)-[:%s ]->(y)'%(pref,fname,from_lab,from_spec,to_lab,to_spec,key)

        print('query:',q1)
        graph.run(q1)
        delete_file(fpref+temp_fname)
    
    for key, value in node_cypher.items():
        graph.run("match (n:%s) remove n.csv_id"%key)
        
def get_temp_fname(pref,ext):
    fname = pref+"_"+uid()+"."+ext
    return fname
        

def get_id_spec(key,which_end):
    if key == 'csv_id':
        return 'csv_id: toInt(csvLine.%s)'%(which_end)
    else:
        return "%s: csvLine.%s"%(key,which_end)

def import_spec(props):
    prop_list = []
    for prop in props:
        if not prop == 'csv_id':
            prop_list.extend(["%s : csvLine.%s "%(prop,prop)])
        else:
            prop_list.extend(["csv_id: toInt(csvLine.csv_id)"])
    print('prop_list',prop_list)
    return "{"+",".join(prop_list)+"}"

def networkx_2_neo4j():
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    graph = Graph('%s/db/data/'%args.gdb_url)

    if args.delete_all == 'True':
        graph.delete_all()
    node_dct = {}
    for n,d in gr.nodes_iter(data=True):
    #    print("n ",n,"d ",d)
        label = 'node'
        create_node = False
        if 'label' in d:
            label = d['label']
        if not '_' in n:
            d['iname'] = n
            node = Node(label,**d)
            create_node = True
        else:
            node = graph.find_one(label,property_key='iname',property_value=n)
            if node == None:
                d['iname'] = n
                node = Node(label, **d)
                create_node = True
#            node = find_node(iname=n)
        node_dct[n] = node
        if create_node:
            graph.create(node)
        else:
            print('found existing node',node)
    for u,v,d in gr.edges_iter(data=True):
#        print("edge ",u,v,"data",d)
        if 'label' in d:
            label = d['label']
        else:
            label = 'related'
        graph.create(Relationship(node_dct[u], label, node_dct[v]))

csv_import(gr)

