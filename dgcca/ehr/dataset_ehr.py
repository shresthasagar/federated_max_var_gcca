import torch
from torchvision import datasets, transforms, utils
from torch.utils.data import DataLoader, Dataset
import torchvision
import torch.nn.functional as F
import numpy as np
import os

def shuffle_dataset(x, y):
    """
    Shuffle the dataset only for the examples with the same labels
    @params:
        x -> data tensor of size [num_views, num_entities, ...]
        y -> label tensor of size [num_entities]
    @return:
        x_shuffled, y_shuffled of the same shape as the input
    """

    def get_flip_indices(y_sorted):
        """
        Compute the indices at which the sorted dataset flip from one label to another
        """
        flip_indices = [0]
        current_int = y_sorted[0]
        for i in range(len(y_sorted)):
            if current_int !=y_sorted[i]:
                current_int = y_sorted[i]
                flip_indices.append(i)         
        return flip_indices

    ## first shuffle only the samples corresponding to the same target
    ## The resulting dataset will be sorted by target
    
    # sort the dataset according to the labels
    a = np.argsort(y)
    x_shuffled = x[:, a, ...]
    y_shuffled = y[a]

    # Find the indices from which the labels flip from one index to another
    # E.g. 0 0 0 0 0 1 1 1 2 2. The flip index is [5, 8]
    flip_idx = get_flip_indices(y_shuffled)
    flip_idx = flip_idx + [len(y_shuffled)]

    # apply random permutation of the to the segments separated by flip indices 
    for view in range(len(x_shuffled)):
        randperms = torch.cat([flip_idx[i]+torch.randperm(flip_idx[i+1]-flip_idx[i]) for i in range(len(flip_idx)-1)])
        x_shuffled[view] = x_shuffled[view,randperms, ...]
    
    ## Now shuffle the whole dataset 
    perm = torch.randperm(len(y_shuffled))
    x_shuffled = x_shuffled[:,perm, ...]
    y_shuffled = y_shuffled[perm]

    return x_shuffled, y_shuffled


class EhrDataset(Dataset):
    def __init__(self, trian=True, normalize=False, shuffle=True, data_file=None):
        """
        """
        assert os.path.isfile(data_file), "Invalid file path"
        x, y = torch.load(data_file)
        self.x = torch.stack(x)
        self.y = torch.tensor(y)
        if shuffle:
            self.shuffle()
    
    def shuffle(self):
        self.x, self.y = shuffle_dataset(self.x, self.y)

    def __len__(self):
        return len(self.x[0])

    def __getitem__(self, idx):
        return self.x[:,idx, ...]
        

def get_ehr_data(trian=True, normalize=False, shuffle=True, data_file=None):
    """
    Get shuffled ehr data
    """
    if data_file is None:
        mat, labeled_data = torch.load('/scratch/sagar/Projects/federated_max_var_gcca/ehr/data/combined_views')
    else:
        assert os.path.isfile(data_file), "The given path is not a file"
        mat, labeled_data = torch.load(data_file)
    x  = torch.stack(mat)

def get_frequent_indices(y, min_count=40, except_classes = [15]):
    """
    @params: 
        y: a 1-D tensor of class labels
        min_count: 
        except_ind: except the class labels in this list
    @return:
        freq_id: list of indices of class labels with frequency greater than or equal to min_count
    """

    # sort x and y according to class index
    a = np.argsort(y)
    y_sorted = y[a]
    
    num_ind = []
    idx = {y_sorted[0].item():1}
    j = y_sorted[0]
    sumid = 0

    # count all the indices
    for i in y_sorted:
        if not j==i:
            j = i
            idx[j.item()] = 1
            num_ind.append(sumid)
            sumid = 0
        else:
            idx[i.item()] += 1

    # get the most frequent classes
    frequent_keys = []
    for key in idx:
        if idx[key] >= min_count and not key in except_classes:
            frequent_keys.append(key)

    # remove the entities related to SYMPTOMS, SIGNS, AND ILL-DEFINED CONDITIONS (780-799)
    freq_id = []
    for i in range(len(y)):
        if y[i] in frequent_keys:
            freq_id.append(i)

    return freq_id, frequent_keys