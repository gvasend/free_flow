
from sklearn.decomposition import NMF, LatentDirichletAllocation


from skparse import SKParse

# general parameters



parser = SKParse(description='Translate text file into tfidf')

parser.model_options()
parser.all_options()

#parser.add_argument('--output_file',default='*output_file',help='file containing output feature data')
parser.add_argument('--corpus',default='log.txt',help='file containing text data. one line for each document with first field as label.')
parser.add_argument('--no_topics',type=int,default=20,help='number of topics')
parser.add_argument('--vector_type',choices=['tfidf','count'],default='tfidf',help='selects vectorizer type, tfidf or count')
parser.add_argument('--algorithm',choices=['nmf','lda'],default='lda',help='selects algorithm, nmf or lda')

# SVC parameters

parser.output_options()

args = parser.parse_args()

from time import time

from sklearn.datasets import dump_svmlight_file

from sklearn.feature_extraction.text import TfidfVectorizer, CountVectorizer


def display_topics(model, feature_names, no_top_words):
    for topic_idx, topic in enumerate(model.components_):
        print("Topic %d:" % (topic_idx))
        print(" ".join([feature_names[i]
                        for i in topic.argsort()[:-no_top_words - 1:-1]]))

n_features = 10000
vector_type = args.vector_type
if args.algorithm == 'lda':
    vector_type = 'count'
if args.algorithm == 'nmf':
    vector_type = 'tfidf'

global lines
with open(args.corpus, 'r') as f:
    lines = f.readlines()

data_samples = [line.split("\t")[1]  for line in lines]
labels = [line.split("\t")[0]  for line in lines]

# Use tf-idf features for NMF.
if vector_type == 'tfidf':

    tf_vectorizer = TfidfVectorizer(max_df=0.95, min_df=2,
                                   max_features=n_features,
                                   stop_words='english')
else:
    tf_vectorizer = CountVectorizer(max_df=0.95, min_df=2, max_features=n_features, stop_words='english')

t0 = time()
tf = tf_vectorizer.fit_transform(data_samples)
tf_feature_names = tf_vectorizer.get_feature_names()

#lda = LatentDirichletAllocation(n_topics=no_topics, max_iter=5, learning_method='online', learning_offset=50.,random_state=0).fit(tfidf)
if args.algorithm == 'nmf':
    model = NMF(n_components=args.no_topics, random_state=1, alpha=.1, l1_ratio=.5, init='nndsvd').fit(tf)
else:
    model = LatentDirichletAllocation(n_topics=args.no_topics, max_iter=5, learning_method='online', learning_offset=50.,random_state=0).fit(tf)



no_top_words = 20
display_topics(model, tf_feature_names, no_top_words)

if args.output_file == None:
    setattr(args, 'output_file', "sk_ff_"+str(uuid.uuid1()))+'.libsvm'
    


y = [1.0 for idx in range(len(data_samples))]
#dump_svmlight_file(tfidf, y, 'test.svm')

dump_svmlight_file(tfidf,y,args.output_file,zero_based=args.zero_based,query_id=args.query_id,multilabel=args.multilabel,comment=args.comment)
    
