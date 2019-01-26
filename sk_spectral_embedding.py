#!/usr/bin/python
#http://scikit-learn.org/stable/auto_examples/manifold/plot_compare_methods.html
import numpy as np
from sklearn.cluster import KMeans
from sklearn.cluster import MeanShift
import csv
import sys
import logging

from sklearn import manifold, datasets


from skparse import SKParse

parser = SKParse(description='Spectral Embedding.')

parser.add_argument('--affinity',default='nearest_neighbors',choices=['nearest_neighbors','rbf','precomputed'],help='nearest_neighbors : construct affinity matrix by knn graph, rbf : construct affinity matrix by rbf kernel, precomputed : interpret X as precomputed affinity matrix, callable : use passed in function as affinity the function takes in data matrix (n_samples, n_features) and return affinity matrix (n_samples, n_samples).')

parser.add_argument('--n_neighbors',type=int,help='default Number of nearest neighbors for nearest_neighbors graph building.')

parser.add_arguments(parser,["n_jobs","random_state","gamma","eigen_solver"])

parser.add_argument('--n_components',type=int,default=2,help='The dimension of the projected subspace.')


parser.model_options()
parser.all_options(p)
parser.output_options()

args = parser.parse_args()

# model = manifold.SpectralEmbedding(n_components=args.n_components, affinity=args.affinity, gamma=args.gamma, random_state=args.random_state, eigen_solver=args.eigen_solver, n_neighbors=args.n_neighbors, n_jobs=args.n_jobs)

model = manifold.SpectralEmbedding(n_components=2,n_neighbors=10)
   
parser.save_model(model, args.model_output_file)




