# wildboar
![Python version](https://img.shields.io/badge/python-3.7%20%7C%203.8-blue)
[![Build Status](https://travis-ci.com/isaksamsten/wildboar.svg?branch=master)](https://travis-ci.com/isaksamsten/wildboar)
[![Docs Status](https://img.shields.io/badge/docs-passing-success)](http://isaksamsten.github.io/wildboar/index.html)
[![PyPI version](https://badge.fury.io/py/wildboar.svg)](https://badge.fury.io/py/wildboar)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.4264063.svg)](https://doi.org/10.5281/zenodo.4264063)

[wildboar](https://isaksamsten.github.io/wildboar/) is a Python module for temporal machine learning and fast
distance computations built on top of
[SciKit-Learn](https://scikit-learn.org) and [Numpy](https://numpy.org)
distributed under the GNU General Public License Version 3.

It is currently maintained by Isak Samsten

## Installation

### Dependencies

wildboar requires:

 * python>=3.7
 * numpy>=1.17.4
 * scikit-learn>=0.21.3
 * scipy>=1.3.2
 
Some parts of wildboar is implemented using Cython. Hence, compilation
requires:

 * cython (>= 0.29.14)

### Current version

- Current release: 1.0.3
- Current development release: 1.0.3dev

### Binaries

`wildboar` is available through `pip` and can be installed with:

    pip install wildboar

Universal binaries are compiled for GNU/Linux and Python 3.6 and 3.7.

### Compilation

If you already have a working installation of numpy, scikit-learn, scipy and cython,
compiling and installing wildboar is as simple as:

    python setup.py install
	
To install the requirements, use:

    pip install -r requirements.txt
	

## Development

Contributions are welcome. Pull requests should be
formatted according to [PEP8](https://www.python.org/dev/peps/pep-0008/).

## Usage

```python
from wildboar.ensemble import ShapeletForestClassifier
from wildboar.datasets import load_two_lead_ecg
x_train, x_test, y_train, y_test = load_two_lead_ecg(merge_train_test=False)
c = ShapeletForestClassifier()
c.fit(x_train, y_train)
c.score(x_test, y_test)
``` 
    
See the [tutorial](https://isaksamsten.github.io/wildboar/master/tutorial.html) for more examples.

## Source code

You can check the latest sources with the command:

    git clone https://github.com/isakkarlsson/wildboar
    
## Documentation

* HTML documentation: [https://isaksamsten.github.io/wildboar](https://isaksamsten.github.io/wildboar)
	
## Citation
If you use `wildboar` in a scientific publication, I would appreciate
citations to the paper:
- Karlsson, I., Papapetrou, P. Boström, H., 2016.
 *Generalized Random Shapelet Forests*. In the Data Mining and
 Knowledge Discovery Journal
  - `ShapeletForestClassifier`

- Isak Samsten, 2020. isaksamsten/wildboar: wildboar (Version 1.0.3). Zenodo. doi:10.5281/zenodo.4264063
  - `ShapeletForestRegressor`
  - `ExtraShapeletForestClassifier`
  - `ExtraShapeletForestRegressor`
  - `IsolationShapeletForest`
