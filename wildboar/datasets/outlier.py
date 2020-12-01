import math
import numbers
import warnings
from abc import ABCMeta, abstractmethod

import numpy as np
from sklearn.cluster import KMeans, DBSCAN, OPTICS
from sklearn.metrics import pairwise_distances, confusion_matrix
from sklearn.neighbors import KNeighborsClassifier, NearestNeighbors
from sklearn.utils import check_random_state, check_array

from linear_model import KernelLogisticRegression

__all__ = ['OutlierLabeler', 'KMeansLabeler', 'DensityLabeler', 'MinorityLabeler', 'EmmottLabeler']


class OutlierLabeler(metaclass=ABCMeta):
    @abstractmethod
    def fit(self, x, y=None):
        pass

    @abstractmethod
    def transform(self, x, y):
        pass

    def fit_transform(self, x, y=None):
        return self.fit(x, y).transform(x, y)


class KMeansLabeler:
    def __init__(self, *, n_clusters=None, n_outliers=None, random_state=None):
        self.n_clusters = n_clusters
        self.n_outliers = n_outliers
        self.random_state = random_state

    def fit(self, x, y=None):
        if self.n_outliers is None:
            min_outliers = self.n_outliers or math.ceil(x.shape[0] * 0.05)
        elif isinstance(self.n_outliers, float):
            if not 0.0 < self.n_outliers <= 1.0:
                raise ValueError("n_outliers must be in (0, 1], got %r" % self.n_outliers)
            min_outliers = math.ceil(x.shape[0] * self.n_outliers)
        elif isinstance(self.n_outliers, int):
            if not 0 < self.n_outliers < x.shape[0]:
                raise ValueError("n_outliers must be in (0, %d), got %r" % (x.shape[0], self.n_outliers))
            min_outliers = self.n_outliers
        else:
            raise ValueError("n_outliers (%s) not supported" % self.n_outliers)

        n_clusters = self.n_clusters or math.floor(x.shape[0] / min_outliers)
        if min_outliers * n_clusters > x.shape[0]:
            self.k_means_ = KMeans(n_clusters=n_clusters, random_state=self.random_state)
        else:
            try:
                from k_means_constrained import KMeansConstrained
                self.k_means_ = KMeansConstrained(n_clusters=n_clusters, size_min=min_outliers,
                                                  random_state=self.random_state)
            except ImportError:
                self.k_means_ = KMeans(n_clusters=n_clusters, random_state=self.random_state)

        self.k_means_.fit(x)
        _, count = np.unique(self.k_means_.labels_, return_counts=True)

        # skip clusters with too few samples
        invalid_clusters = np.where(count < min_outliers)

        centroid_distance = pairwise_distances(self.k_means_.cluster_centers_, metric='euclidean')

        # skip self matches
        centroid_distance[centroid_distance == 0] = np.nan

        # skip invalid clusters
        centroid_distance[invalid_clusters] = np.nan
        if np.all(np.isnan(x)):
            raise ValueError("no valid clusters")

        # hide the warning for ignored clusters
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", category=RuntimeWarning)
            self.outlier_cluster_ = np.nanargmax(np.nanmean(centroid_distance, axis=1))
        return self

    def fit_transform(self, x, y=None):
        return self.fit(x, y).transform(x, y)

    def transform(self, x, y):
        y = np.ones(x.shape[0])
        labels = self.k_means_.predict(x)
        y[labels == self.outlier_cluster_] = -1
        return x, y


DENSITY_ESTIMATORS = {'dbscan': DBSCAN(), 'optics': OPTICS()}
DENSITY_ESTIMATORS_PARAMS = {}


class DensityLabeler(OutlierLabeler):

    def __init__(self, *, estimator=None, estimator_params=None):
        self.estimator = estimator
        self.estimator_params = estimator_params

    def fit(self, x, y=None):
        if self.estimator is None:
            self.estimator_ = DENSITY_ESTIMATORS['dbscan']
        elif self.estimator in DENSITY_ESTIMATORS:
            self.estimator_ = DENSITY_ESTIMATORS[self.estimator]
        else:
            self.estimator_ = self.estimator

        estimator_params = self.estimator_params or DENSITY_ESTIMATORS_PARAMS[
            self.estimator] if self.estimator in DENSITY_ESTIMATORS_PARAMS else {}
        self.estimator_.set_params(**estimator_params)
        self.estimator_.fit(x, y)
        label, count = np.unique(self.estimator_.labels_, return_counts=True)
        if len(count) == 1:
            raise ValueError("only a single cluster was formed")
        elif not np.any(label == -1):
            raise ValueError("no outlier points")
        else:
            self.outlier_label_ = -1

        return self

    def fit_transform(self, x, y=None):
        self.fit(x, y)
        y = np.ones(x.shape[0])
        y[self.estimator_.labels_ == self.outlier_label_] = -1
        return x, y

    def transform(self, x, y):
        y = np.ones(x.shape[0])
        if hasattr(self.estimator_, 'predict'):
            y[self.estimator.predict(x) == -1] = -1
        else:
            raise ValueError('estimator does not support predict')


class MinorityLabeler(OutlierLabeler):

    def __init__(self, n_outliers=None, random_state=None):
        self.n_outliers = n_outliers
        self.random_state = random_state

    def fit(self, x, y=None):
        labels, label_count = np.unique(y, return_counts=True)
        min_label = np.argmin(label_count)
        self.outlier_label_ = labels[min_label]
        return self

    def transform(self, x, y):
        random_state = check_random_state(self.random_state)
        outliers = np.where(y == self.outlier_label_)[0]
        random_state.shuffle(outliers)
        inliers = np.where(y != self.outlier_label_)[0]

        if self.n_outliers is None:
            n_outliers = outliers.shape[0]
        elif isinstance(self.n_outliers, numbers.Real):
            if not 0.0 < self.n_outliers <= 1.0:
                raise ValueError("n_outliers must be in (0, 1], got %r" % self.n_outliers)
            n_outliers = math.ceil(self.n_outliers * inliers.shape[0])
        else:
            raise ValueError("n_outlier (%r) is not supported" % self.n_outliers)

        x = np.concatenate([x[inliers, :], x[outliers[0:np.min(n_outliers, x.shape[0])], :]], axis=0)
        y = np.concatenate([y[inliers], y[outliers[0:np.min(n_outliers, x.shape[0])]]])
        y[0:inliers.shape[0]] = 1
        y[inliers.shape[0]:] = -1
        return x, y


DEFAULT_EMMOTT_SCALE = np.array([0, 0.16, 0.3, 0.5])


def _variation_dispersed(x, n_outliers, random_state):
    try:
        from sklearn_extra.cluster import KMedoids
        n_outliers = min(x.shape[0], n_outliers)
        f = KMedoids(n_clusters=n_outliers, random_state=random_state).fit(x)
        return f.medoid_indices_
    except ImportError:
        raise ValueError("variation (tight) require scikit-learn-extra.")


def _variation_tight(x, n_outliers, random_state):
    random_state = check_random_state(random_state)
    n_outliers = min(x.shape[0], n_outliers)
    if n_outliers == x.shape[0]:
        return np.arange(0, x.shape[0])
    sample = random_state.randint(0, x.shape[0])
    f = NearestNeighbors(n_neighbors=n_outliers).fit(x)
    return f.kneighbors(x[sample].reshape(1, -1), return_distance=False).reshape(-1)


def _set_random_states(estimator, random_state=None):
    random_state = check_random_state(random_state)
    to_set = {}
    for key in sorted(estimator.get_params(deep=True)):
        if key == 'random_state' or key.endswith('__random_state'):
            to_set[key] = random_state.randint(np.iinfo(np.int32).max)

    if to_set:
        estimator.set_params(**to_set)


_EMMOTT_VARIATION = {'tight': _variation_tight, 'dispersed': _variation_dispersed}


class EmmottLabeler(OutlierLabeler):
    def __init__(self, n_outliers=None, *, confusion_estimator=None, confusion_estimator_params=None,
                 difficulty_estimator=None, difficulty_estimator_params=None, difficulty=1, scale=None,
                 variation='tight', random_state=None):
        self.n_outliers = n_outliers
        self.confusion_estimator = confusion_estimator
        self.confusion_estimator_params = confusion_estimator_params
        self.difficulty_estimator = difficulty_estimator
        self.difficulty_estimator_params = difficulty_estimator_params
        self.difficulty = difficulty
        self.scale = scale or DEFAULT_EMMOTT_SCALE
        self.variation = variation
        self.random_state = random_state

    def fit(self, x, y=None):
        y = check_array(y, ensure_2d=False)
        x = check_array(x)
        random_state = check_random_state(self.random_state)
        if self.difficulty_estimator is None:
            self.difficulty_estimator_ = KernelLogisticRegression(kernel='poly', max_iter=1000)
            _set_random_states(self.difficulty_estimator_, random_state)
        else:
            self.difficulty_estimator_ = self.difficulty_estimator

        if self.difficulty_estimator_params is not None:
            self.difficulty_estimator_.set_params(**self.difficulty_estimator_params)

        self.difficulty_estimator_.fit(x, y)
        self.n_classes_ = np.unique(y).shape[0]
        if self.n_classes_ > 2:
            if self.confusion_estimator is None:
                self.confusion_estimator_ = KNeighborsClassifier()
                _set_random_states(self.confusion_estimator_, random_state)
            else:
                self.confusion_estimator_ = self.confusion_estimator

            if self.confusion_estimator_params is not None:
                self.confusion_estimator_.set_params(**self.confusion_estimator_params)

            self.confusion_estimator_.fit(x, y)
        elif self.n_classes_ < 2:
            raise ValueError("require more than 1 labels, got %r" % self.n_classes_)

        if self.n_classes_ > 2:
            try:
                import networkx as nx
                y_pred = self.confusion_estimator_.predict(x)
                cm = confusion_matrix(y, y_pred)
                graph = nx.Graph()
                classes = self.confusion_estimator_.classes_
                graph.add_nodes_from(classes)
                for i in range(self.n_classes_):
                    for j in range(self.n_classes_):
                        if i != j:
                            graph.add_edge(classes[i], classes[j], weight=cm[i][j] + cm[j][i])

                max_spanning_tree = nx.maximum_spanning_tree(graph, algorithm='kruskal')
                coloring = nx.algorithms.bipartite.color(max_spanning_tree)
                color = random_state.randint(2)

                outlier_labels = []
                for cls in classes:
                    if coloring[cls] != color:
                        outlier_labels.append(cls)

                self.outlier_label_ = np.array(outlier_labels)
            except ImportError:
                raise ValueError("for n_classes>2, `networkx` is required.")
        else:
            labels = np.unique(y)
            self.outlier_label_ = labels[random_state.randint(2)]

        y_new = np.ones(x.shape[0], dtype=np.int)
        y_new[np.isin(y, self.outlier_label_)] = -1

        self.difficulty_estimator_.fit(x, y_new)

        return self

    def transform(self, x, y):
        random_state = check_random_state(self.random_state)
        y_new = np.ones(x.shape[0], dtype=np.int)
        y_new[np.isin(y, self.outlier_label_)] = -1
        difficulty_estimate = self.difficulty_estimator_.predict_proba(x)
        difficulty_estimate = difficulty_estimate[:, np.where(self.difficulty_estimator_.classes_ == 1)[0]]
        outliers_indices = np.where(y_new == -1)
        inlier_indices = np.where(y_new == 1)

        if self.variation in _EMMOTT_VARIATION:
            variation = _EMMOTT_VARIATION[self.variation]
        else:
            raise ValueError("variation (%s) is not supported" % self.variation)

        x_outliers = x[outliers_indices]
        y_outliers = y_new[outliers_indices]
        difficulty_estimate = difficulty_estimate[outliers_indices]

        if self.n_outliers is None:
            self.n_outliers_ = y_outliers.shape[0]
        elif isinstance(self.n_outliers, numbers.Real):
            if not 0.0 < self.n_outliers <= 1.0:
                raise ValueError("n_outliers must be in (0, 1], got %r" % self.n_outliers)
            self.n_outliers_ = math.ceil(self.n_outliers * inlier_indices[0].shape[0])
        else:
            raise ValueError("n_outlier (%r) is not supported" % self.n_outliers)

        difficulty = np.digitize(difficulty_estimate, self.scale)
        x_outliers = x_outliers[np.where(np.isin(difficulty, self.difficulty))[0]]
        outlier_sampled = variation(x_outliers, self.n_outliers_, random_state.randint(np.iinfo(np.int32).max))

        return (np.concatenate([x[inlier_indices], x_outliers[outlier_sampled]], axis=0),
                np.concatenate([y_new[inlier_indices], y_outliers[outlier_sampled]], axis=0))