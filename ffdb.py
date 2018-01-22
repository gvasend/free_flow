#!/usr/bin/env python3
# FreeFlow run analysis support


import pprint
from pymongo import MongoClient
import gridfs


db = None
fs = None
client = None

def connect_service(ip, port):
    global fs, client, db
    client = MongoClient(ip, port)
    db = client.aif_document_db
    fs = gridfs.GridFS(db)
    
def delete_all_docs():
    global fs
    for i in fs.find(): # or fs.list()
        fs.delete(i._id)



def search(query):
    global db
#    print("searching one ",query)
    return db.posts.find_one(query)

def search_all(query):
    global db
    return list(db.posts.find(query))
        
def print_all(query):
    global db
    res = db.posts.find(query)
    for r in res:
        pprint.pprint(r)

connect_service('localhost', 27017)


import re
rid_history = []

def tab_data(run,collect_list):
    rid_hist = []
    output_records = []
    data = search_all(run)
#    print("found ",len(data))
    for rec in data:
        if 'run_id' in rec and rec['run_id'] not in rid_history:
#            print("processing run ",rec['run_id'])
            rid = rec['run_id']
            rid_history.extend([rid])
            record = {'run_id':rid}
            for c in collect_list:
                subset = search({'run_id':rid, **c[0]})
#                print("subset ",subset)
                for item in c[1]:
                    if item in subset:
                        record[item] = subset[item]
                    else:
                        record[item] = None
            output_records.extend([record])
    keys = [key for key in output_records[0]]
    print("|".join(keys))
    for rec in output_records:
        out_rec = []
        for key in keys:
            out_rec.extend([str(rec[key])])
        st = '|'.join(out_rec)
        print(st)


if __name__ == '__main__':

    tab_data({'run_id':re.compile('.*expAA')},[({'task_id':'w3txq'},['--n_samples','run_time','--noise','--n_types']),({'task_id':'compare'},['score'])])

# plot score vs. noise per classifier
#
#
    
    
