
#!/usr/bin/env python
import uuid
import time
import threading
import re
import subprocess
import networkx as nx
import json

import tika
import xmltodict
import sys
tika.initVM()
from tika import parser
current_sent = None

import logging

print("directory grapher")

fo = None

doc_id = None
seq = 0
from ffparse import FFParse

aparser = FFParse(description='Graph directory')

aparser.add_argument('--directory',required=True,help='Directory root')
aparser.add_argument('-output_file',help='Directory root')
aparser.add_argument('--trigger_dag',default='graph_doc1',help='Dag to trigger for each file')
aparser.add_argument('--l1',default='folder')
aparser.add_argument('--l2',default='folder')
aparser.add_argument('--file_label',default='file')
aparser.add_argument('--edge_label',default='sub_item')


aparser.add_argument('--graph_format',default='GraphML',help='')

aparser.all_options()

args = aparser.parse_args()

def uid():
    return str(uuid.uuid1())

# airflow trigger_dag graph_document --conf "{\"document\":\"/home/gvasend/gv-ML-code/freeflow/rfp1.pdf\"}"

import os

def walk_dir(root_dir,gr):
# traverse root directory, and list directories as dirs and files as files
    gr.add_node(root_dir+"_folder", label='folder')
    for root, dirs, files in os.walk(root_dir):
        rel_root = root[len(root_dir):]
        path = rel_root.split(os.sep)
        dir_name = os.path.basename(root)
        level = len(path)-1
        level_label = getattr(args,'l'+str(level),'folder')
        root_node = root+"_folder"
        higher_dir = "/".join(root.split('/')[:-1])+"_folder"
        print((len(path) - 1) * '---', level, level_label, os.path.basename(root), rel_root, root, "/".join(root.split('/')[:-1]))
        gr.add_node(root_node, label='folder')
        if not level_label == 'folder':
            gr.add_node(dir_name, label=level_label)
            gr.add_edge(root_node, dir_name, label=level_label)      
        gr.add_edge(higher_dir, root_node, label=args.edge_label)
        for file in files:
            file_path = root+'/'+file
            file_node = file_path+"_file"
            abs_path = os.path.abspath(file_path)
            basename = os.path.basename(file_path)
            print(file_path,abs_path)
            print(len(path) * '---', file_path)
            gr.add_node(file_node, label=args.file_label, abs_name=abs_path, name=basename)
            gr.add_edge(root_node, file_node, label=args.edge_label)
#            subprocess.check_call('airflow trigger_dag %s --conf "{\\"document\\":\\"%s\\"}"'%(args.trigger_dag,abs_path),shell=True)


gr = nx.Graph()
if __name__ == '__main__':
    if args.output_file == None:
        setattr(args, 'output_file', "graph_out_"+str(uid())+'.'+args.graph_format.lower())

#    outf = open(args.output_file,'w')
    
    walk_dir(args.directory,gr)
    if args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(gr, args.output_file)
    aparser.write_dict({'graph_output':args.output_file})

s#    outf.close()
    
