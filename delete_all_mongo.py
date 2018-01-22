
import time
from pymongo import MongoClient
import gridfs
import shutil
from hashlib import md5
import uuid

def connect_service(ip, port):
    global fs, client, db
    client = MongoClient(ip, port)
    db = client.aif_document_db
    fs = gridfs.GridFS(db)
    
def delete_all_docs():
    global fs
    for i in fs.find(): # or fs.list()
        print('delete document',i)
        print('dic',i)
#s        fs.delete(i._id)

connect_service('localhost', 27017)

print('preparing to delete all documents')
delete_all_docs()
