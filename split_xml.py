
#!/usr/bin/env python
import argparse
import uuid
import time
import threading
import re
import networkx as nx
import json
import sys

import lxml

import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='split an xml file into subfiles based on a node attribute')
aparser.add_argument('--xml_input',default='*dag_input_file',help='xml filename')
aparser.add_argument('--dag_input_file',default='tbd',help='xml filename')
aparser.add_argument('--aggregate',default='signeddate')
aparser.add_argument('--prefix',default='split_')
aparser.add_argument('--xslt',default='/home/gvasend/gv-ML-code/freeflow/split_xslt.xml')

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

def file_string(fname):
    with open(fname,'r') as inpf:
        instr = inpf.read()
    return instr.replace("\n","")

def load_graph(Filename):
    return nx.read_graphml(Filename)

import networkx as nx
from io import StringIO, BytesIO
from lxml import etree

def load_xml(filename):
    tree = etree.parse(filename)
    root = tree.getroot()
    print(str(root))
    return root


root = load_xml(args.dag_input_file)

# Nodes to convert to attribute nodes

cnt = 0

total_nodes = 0
for elem in root.iterchildren():
    total_nodes += 1
print('total nodes',total_nodes)

import subprocess
def trigger_dag(dag,abs_path='/',context={}):
    ctx = '"'+json.dumps(context).replace('"','\\"')+'"'
    shell('airflow trigger_dag %s --conf %s'%(dag,ctx))


def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)


from datetime import datetime
def transform(label,value):
    try:
        new_value = datetime.strptime(value, '%m/%d/%Y').strftime('%m%d%Y')
    except:
        new_value = value
    return new_value

aggregate_label = args.aggregate
agg_list = []

for elem0 in root.iterchildren():
  for elem in elem0.iterchildren():
    cnt += 1
#    print("new node ",elem.tag,cnt,cnt/total_nodes)
    for attr in elem.iterchildren():
           if attr.tag == aggregate_label:
               agg_list.extend([attr.text])

aggregate_set = set(agg_list)
print('aggregate labels',aggregate_set)

xslt = file_string(args.xslt)

output_files = []
for agg in aggregate_set:
    xslt1 = xslt.replace("{attribute}",args.aggregate).replace("{aggregate_value}",agg)
    print('xslt',xslt1)
    xslt_root = etree.XML(xslt1)
    transform = etree.XSLT(xslt_root)
    newdom = transform(root)
    total_doc = len(newdom.xpath('//doc'))
    print('total doc nodes',total_doc)
    xml_str = etree.tostring(newdom, pretty_print=True).decode('utf-8')
    xml_str = xml_str.replace("<doc/>","")
    clean_label = agg.replace("/","-")
    with open(args.prefix+clean_label+".xml",'w') as of:
        of.write(xml_str)
    output_files.extend([args.prefix+clean_label+".xml"])
#    trigger_dag('UsSpendingDaily', context={'dag_input_file':args.prefix+clean_label+".xml"})

sc.write_dict({'output_files':output_files})


