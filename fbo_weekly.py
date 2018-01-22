
#!/usr/bin/env python
import argparse
import uuid
import time
import json
import sys
import networkx as nx

from py2neo import authenticate, Graph, Node, Relationship


aparser = argparse.ArgumentParser(description='Process weekly FBO files')
aparser.add_argument('-graph_output',help='Graph filename')

aparser.add_argument('--graph_format',default='GraphML',help='')

aparser.add_argument('--output_file',help='Grahp output')
aparser.add_argument('--ts',default='*run_id',required=True,help='Date being processed')

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

import dateutil.parser
scheduled_date = args.ts.split("T")[0].replace("-","")
date_node = scheduled_date[4:]+scheduled_date[:4] 
#new_value = datetime.strptime(args.ts.split("T")[0], '%Y-%m-%d').strftime('%m%d%Y')

print('sched ',scheduled_date, date_node)


from ftplib import FTP

attr_nodes = ['SOLNBR','NAICS','OFFICE','CONTACT','AGENCY','DATE','CLASSCOD','SETASIDE']
total_records = 0

def uid():
    return str(uuid.uuid1())

def ftp_download(url,fname):
    print('downloading %s'%(fname))
    ftp = FTP(url)
    print('FTP')
    ftp.login("anonymous", "")
    print('login')
#ftp.cwd("/Dir")
    ftp.retrbinary('RETR %s'%fname, open(fname, 'wb').write)
    print('ftp successful')
    
fname = 'FBOFeed%s'%scheduled_date
ftp_download('ftp.fbo.gov',fname)


from html.parser import HTMLParser

class MLStripper(HTMLParser):
    def __init__(self):
        super().__init__()
        self.reset()
        self.strict = False
        self.convert_charrefs= True
        self.fed = []
    def handle_data(self, d):
        self.fed.append(d)
    def get_data(self):
        return ''.join(self.fed)

def cleanhtml(html):
    s = MLStripper()
    s.feed(html)
    return s.get_data().replace("&","")

import re
def format_fbo(fname,gr):
    global total_records
# read a daily formatted FBO file and try to parse its funky format 
    with open(fname, 'rb') as inf:
        text = str(inf.read())
    text = text.replace("<BR>","")
#    print('text',text)
#    f.write("<root>\n")
    p = re.compile('<[A-Z]+>(.*?)<\/[A-Z]+>')
    p1 = re.compile('<[A-Z]+>')
    p2 = re.compile('<[A-Z]+>(.*?)(?!<[A-Z]+>)')
    node_links = []
    for node in re.findall('<[A-Z]+>.*?<\/[A-Z]+>',str(text)):
# loop through the outer tags. fortunately those follow proper format and and terminated with the proper tag. inside that tag it is not properly formatted
        node_text = p.match(node).group(1).replace("\\n","")
        props = {}
        tag = p1.match(node).group(0)
        node_label = tag.replace("<","").replace(">","")
#        print('^^^^^',tag,node_text)
        remain_text = node_text
#        f.write(tag+"\n")
        node_id = uid()
        while not remain_text == '':
#  this funky loop takes care of proper tags not having a proper closing tag.
            l = re.findall('(<[A-Z]+>)(.*?)(<[A-Z]+>.*)',remain_text)
            if len(l) == 0:
                l = re.findall('(<[A-Z]+>)(.*?)',remain_text)
#                print(l)               TBD does this contain useful data?
                remain_text = ''
            else:
                subnode = l[0][0].replace("<","").replace(">","")
                endsub = subnode.replace("<","</")
                subtext = cleanhtml(l[0][1])
                if subtext == '' or subtext == None:
                    subtext = 'null'
                if subnode in attr_nodes:
                    node_links.extend([(node_id,subnode,subtext)])
                props.update({subnode:subtext})
                remain_text = l[0][2]
#                f.write("%s%s%s\n"%(subnode,subtext,endsub))
#        f.write(tag.replace("<","</")+"\n")
        gr.add_node(node_id, label='FBO_Announcement', iname=node_id, **props)
        total_records += 1
#    f.write("</root>\n")
    for node, label, iname in node_links:
        if 'DATE' in label and len(iname) == 4:                 # another artifact of this crazy daily format. Dates do not include year.
#            iname = iname + '2017'
            iname = date_node
        gr.add_node(iname, label=label+"_merge_")
        gr.add_edge(node, iname, label=label)

print('total records',total_records)


if __name__ == '__main__':
    if args.output_file == None:
        autofile = uid()+'.'+args.graph_format.lower()
        print("output_file not set, auto generate filename",autofile)
        setattr(args, 'output_file', "graph_out_"+autofile)

    graph = nx.Graph()
    format_fbo(fname,graph)
    
    if args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(graph, args.output_file)
    sc.write_dict({'graph_output':args.output_file})




