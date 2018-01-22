
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

aparser.add_argument('--node')
aparser.add_argument('--class_attribute')
aparser.add_argument('--text_attribute')
aparser.add_argument('--name')
aparser.add_argument('--training_label')
aparser.add_argument('--select_category',default='rfp')
aparser.add_argument('--act',choices=['create','run','train','mongo'])


clf = None

def neo_query(st):
    print('query:',st)
    return graph.run(st)

def train():
# train a give classifier
    graph.query('match (cp:classification_problem)')
    
    
def get_feature_data(cp,cl):
# collect cp feature data
    print('get feature data')
    class_attribute = cl['training_label']
    feature_attribute = cp['feature_attribute']
    total_rows = 0
    mapping_function = 'document_category'
#    res = neo_query('match (n:%s)-[:%s]->(t:%s) where t.iname="rfp" return n.%s, t.iname '%(cp['node'],mapping_function,class_attribute,feature_attribute))

    res = neo_query('match (n:%s) where not n.doc_type="unknown" and exists(n.%s) return n.%s, n.%s '%(cp['node'],feature_attribute,class_attribute,feature_attribute))
#    result_list = []
#    for row in res:
#        total_rows += 1
#        result_list.extend((row['n.%s'%class_attribute],mg.get_text(row['n.%s'%feature_attribute])))
    feature_data = []
    feature_target = []
    for row in res:
        total_rows += 1
        feature_data.extend([mg.get_text(row['n.%s'%feature_attribute])])
        feature_target.extend([row['n.%s'%class_attribute]])
    feature_target_set = list(set(feature_target))
    for target in range(len(feature_target)):
        feature_target[target] = feature_target_set.index(feature_target[target])
    print(feature_target_set)
    print('total rows',total_rows)
    return feature_target_set, feature_target, feature_data



#    trained_model = train_model(result_list, classifier)
    
def run():
    print("running")
# evaluate existing cp's to determine what process to run
    res = graph.run('match (cp:classification_problem)-[]->(cl:classifier {type:"empirical"}) return cp, cl')
    for row in res:
        cp = row['cp']
        cl = row['cl']
        print("cp",cp,cl)
        if cp['state'] == 'created' or True:
            cp['state'] = 'training'
            cp.push()
            print("before classify")
            train(cp,cl)
            cp['state'] = 'trained'
            cp.push()
        elif cp['state'] == 'trained':
            classify(cp)
            cp[] = ''
            cp.push()

def classifier_type(st):
    return 'naive_bayes'

from sklearn.feature_extraction.text import CountVectorizer
from sklearn.feature_extraction.text import TfidfTransformer
from sklearn.naive_bayes import MultinomialNB

def train(cp,cl):
    global clf
# Train a new classifier on cp
    print('classify')
    data = get_feature_data(cp,cl)
    count_vect = CountVectorizer()
    X_train_counts = count_vect.fit_transform(data[2])
    print('shape',X_train_counts.shape)

    tfidf_transformer = TfidfTransformer()
    X_train_tfidf = tfidf_transformer.fit_transform(X_train_counts)
    print('tfidf shape',X_train_tfidf.shape)

    clf = MultinomialNB().fit(X_train_tfidf, data[1])
    sc.save_model(clf, args.model_output_file)
    print(clf.__dict__)
            
def create_classifier(graph,cp):
    cp['state'] = 'creating_classifier'
    node = cp['node']
    attr = cp['feature_attribute']
    res = graph.run('match (n:%s) return n.%s limit 5'%(cp['node'],cp['class_attribute']))
    for attr in res:
        classifier_type = type(attr)
    if True:
        class_type = 'text'
        classif = Node("classifier", classifier_type=class_type)
        graph.create(classif)
        graph.create(Relationship(cp, "has_classifier", classif))
    classify(cp,classif)

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

if __name__ == '__main__':

    if args.act == 'create':
        make_cp()
    elif args.act == 'run':
        print("run")
        run()
    elif args.act == 'mongo':
        extract_text_direct()
    
