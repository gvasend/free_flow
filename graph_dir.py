
#!/usr/bin/env python
import argparse
import uuid
import time
import threading
import re
import subprocess
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
current_sent = None

import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

print("directory grapher")

fo = None

doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Graph directory')

aparser.add_argument('--directory',required=True,help='Directory root')
aparser.add_argument('-output_file',help='Directory root')
aparser.add_argument('--trigger_dag',default='graph_doc1',help='Dag to trigger for each file')


aparser.add_argument('--graph_format',default='GraphML',help='')

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)

def uid():
    return str(uuid.uuid1())

# airflow trigger_dag graph_document --conf "{\"document\":\"/home/gvasend/gv-ML-code/freeflow/rfp1.pdf\"}"

import os

def walk_dir(root_dir,gr):
# traverse root directory, and list directories as dirs and files as files
    gr.add_node('._folder', label='folder')
    for root, dirs, files in os.walk(root_dir):
        path = root.split(os.sep)
        root_node = root + "_folder"
        higher_dir = "/".join(root.split('/')[:-1])+"_folder"
        print((len(path) - 1) * '---', os.path.basename(root), root, "/".join(root.split('/')[:-1]))
        gr.add_node(root_node, label='folder')
        gr.add_edge(higher_dir, root_node, label='sub_folder')
        for file in files:
            file_path = root+'/'+file
            file_node = file_path+"_file"
            abs_path = os.path.abspath(file_path)
            print(file_path,abs_path)
            print(len(path) * '---', file_path)
            gr.add_node(file_node, label='file')
            gr.add_edge(root_node, file_node, label='sub_file')
            subprocess.check_call('airflow trigger_dag %s --conf "{\\"document\\":\\"%s\\"}"'%(args.trigger_dag,abs_path),shell=True)


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
    sc.write_dict({'graph_output':args.output_file})

#    outf.close()
    
