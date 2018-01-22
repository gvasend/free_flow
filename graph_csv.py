
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

from py2neo import authenticate, Graph, Node, Relationship

import lxml

import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Graph a csv formatted file')
aparser.add_argument('--input_csv',default='*graph_output',help='FBO filename')

aparser.add_argument('-graph_format',default='GraphML',help='')

aparser.add_argument('--output_file',help='Grahp output')
aparser.add_argument('--deferred_link',default=False,type=bool)
aparser.add_argument('--node_creation',default='create',help='create node using create or merge')
aparser.add_argument('--label',help='label to assign to created vertices')

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


import networkx as nx

import csv
dict1 = []
graph = nx.Graph()

total_rows = 0
with open(args.input_csv, "r") as infile:
    reader = csv.reader(infile)
    headers = next(reader)[1:]
    for row in reader:
        total_rows += 1
        row_dict = {key: value for key, value in zip(headers, row[1:])}
        dict1.extend([row_dict])
print(len(dict1))
print('total rows',total_rows)


# need to figure out a more generic way to handle this
attr_nodes1 = {'DEPARTMENT_ID':'DEPARTMENT_ID','DEPARTMENT_NAME':'DEPARTMENT_NAME','CONTRACTING_OFFICE_CODE':'CONTRACTING_OFFICE_CODE','CONTRACTING_OFFICE_NAME':'OFFICE','ADDRESS_CITY':'ADDRESS_CITY','ADDRESS_STATE':'ADDRESS_STATE','ZIP_CODE':'ZIP_CODE','AGENCY_NAME':'AGENCY'}
attr_nodes = []

total = 1000
cnt = 0
node_cache = {}

from datetime import datetime
def transform(label,value):
    try:
        new_value = datetime.strptime(value, '%m/%d/%Y').strftime('%m%d%Y')
        print(new_value)
    except:
        new_value = value
    return new_value

def uid():
    return str(uuid.uuid1())

for row in dict1:
#    print('row ',row)
    cnt += 1
#    print("new node ",elem.tag,cnt,cnt/total_nodes)
    props = {}
    link_list = []
    node_id = uid()
    for attr in row:
         if not row[attr] == None and not row == None:
           props[attr] = row[attr]
           if attr in attr_nodes1:

               link_node_id = uid()
               common_label = attr_nodes1[attr]
               if args.deferred_link:
                   def_query = 'merge (n {iname:"%s"}) merge (n1:%s {iname:"%s"}) merge (n)-[:%s]->(n1)'%(node_id, common_label,transform(attr,row[attr]), 'contracting_office_'+common_label)
#               print(def_query)
                   graph.add_node(link_node_id, iname=link_node_id, label='deferred_link', from_id=node_id, query=def_query)
               else:
                   link_list.extend([ (node_id,common_label,transform(attr,row[attr])) ])

#         else:
#           props[attr.tag] = "None"
#           link_list.extend([attr])
#             print('None detected',attr.tag,attr.text)
#        print('attribute',attr.tag)
#    print('+++++++++++++++++++++++++++++end attr')

    graph.add_node(node_id, label=args.label+"_"+args.node_creation+"_", iname=node_id, **props)
#    print(attr.tag,props)

node_cache = {}

if not True:
    for from_id, edge_label, to_iname in link_list:
        to_id = uid()
        graph.add_node(to_, iname=to_iname)
        graph.add_edge(from_id, to_id, label=edge_label)
        
if not args.deferred_link:
    for node_id, label, cust_id in link_list:      # link_list
        if True:
    #            print('create attribute node',label)
            node1 = None
            if label+cust_id in node_cache:
                print("cache hit")
                node1 = node_cache[label+cust_id]
            if node1 == None:
                graph.add_node(cust_id, label=label, iname=cust_id)
                node1 = cust_id
                node_cache[label+cust_id] = node1
            graph.add_edge(node_id, node1, label=label)

if __name__ == '__main__':
    if args.output_file == None:
        setattr(args, 'output_file', "graph_out_"+str(uid())+'.'+args.graph_format.lower())

#    outf = open(args.output_file,'w')
    
    if args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(graph, args.output_file)
    sc.write_dict({'graph_output':args.output_file})

