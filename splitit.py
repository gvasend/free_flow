#!/usr/bin/python

import sys
import uuid
import subprocess
import logging
import re
import argparse

parser = argparse.ArgumentParser(description='Split file into multiple datasets')

parser.add_argument('--input_file',default='*feature_file',help='')

parser.add_argument('--prefix',default='',help='')

parser.add_argument('--additional_suffix',default='.libsvm',help='')

import scrape as sc

sc.all_options(parser)

from scrape import write_dict

args = sc.parse_args(parser)

def check_output(st):
    logging.warn("shell command %s"%st)
    result = subprocess.check_output(st,shell=True)
    logging.warn("shell output %s"%result)
    return str(result)

#results = np.loadtxt(open("test_1_centroids.csv","rb"),delimiter=",",skiprows=1)

#print (results)

# bcml mode feature_class version
#  0    1        2           3
# mode { baseline, update }

prefix = args.prefix+str(uuid.uuid1())

output = check_output('split --verbose -n l/2 %s %s --additional-suffix %s'%(args.input_file,prefix,args.additional_suffix))
print(output)

files = re.findall('\'(.*?)\'',output)
print(files)

write_dict({'file0':files[0]})
write_dict({'file1':files[1]})
