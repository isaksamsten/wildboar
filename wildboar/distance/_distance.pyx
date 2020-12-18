# cython: cdivision=True
# cython: boundscheck=False
# cython: wraparound=False
# cython: language_level=3

# This file is part of wildboar
#
# wildboar is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# wildboar is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see
# <http://www.gnu.org/licenses/>.

# Authors: Isak Samsten

import numpy as np
cimport numpy as np

from libc.stdlib cimport malloc

from libc.math cimport sqrt
from libc.math cimport NAN
from libc.stdlib cimport free

from . import _dtw_distance
from . import _euclidean_distance

from ._distance cimport TSCopy
from ._distance cimport DistanceMeasure
from ._distance cimport ts_database_new
from ._distance cimport TSDatabase

from .._utils import check_array_fast

from sklearn.utils import check_array

_DISTANCE_MEASURE = {
    'euclidean': _euclidean_distance.EuclideanDistance,
    'dtw': _dtw_distance.DtwDistance,
    'scaled_euclidean': _euclidean_distance.ScaledEuclideanDistance,
    'scaled_dtw': _dtw_distance.ScaledDtwDistance,
}

cdef int ts_copy_init(TSCopy *shapelet, size_t dim, size_t length, double mean, double std) nogil:
    shapelet[0].dim = dim
    shapelet[0].length = length
    shapelet[0].mean = mean
    shapelet[0].std = std
    shapelet[0].data = <double*> malloc(sizeof(double) * length)
    if shapelet[0].data == NULL:
        return -1

cdef void ts_copy_free(TSCopy *shapelet) nogil:
    if shapelet != NULL and shapelet[0].data != NULL:
        free(shapelet[0].data)

cdef void ts_view_init(TSView *s) nogil:
    """Initialize  a shapelet info struct """
    s[0].start = 0
    s[0].length = 0
    s[0].dim = 0
    s[0].mean = NAN
    s[0].std = NAN
    s[0].index = 0

cdef void ts_view_free(TSView *shapelet_info) nogil:
    """Free the `extra` payload of a shapelet info if needed """
    if shapelet_info[0].extra != NULL:
        free(shapelet_info[0].extra)
        shapelet_info[0].extra = NULL

cdef int _ts_view_update_statistics(TSView *s_ptr, const TSDatabase *t_ptr) nogil:
    """Update the mean and standard deviation of a shapelet info struct """
    cdef TSDatabase t = t_ptr[0]
    cdef TSView s = s_ptr[0]
    cdef size_t shapelet_offset = (s.index * t.sample_stride +
                                   s.dim * t.dim_stride +
                                   s.start * t.timestep_stride)
    cdef double ex = 0
    cdef double ex2 = 0
    cdef size_t i
    for i in range(s.length):
        current_value = t.data[shapelet_offset + i * t.timestep_stride]
        ex += current_value
        ex2 += current_value ** 2

    s.mean = ex / s.length
    s.std = sqrt(ex2 / s.length - s.mean * s.mean)
    return 0

cdef TSDatabase ts_database_new(np.ndarray data):
    """Construct a new time series database from a ndarray """
    data = check_array_fast(data, allow_nd=True)
    if data.ndim < 2 or data.ndim > 3:
        raise ValueError("ndim {0} < 2 or {0} > 3".format(data.ndim))

    cdef TSDatabase sd
    sd.n_samples = <size_t> data.shape[0]
    sd.n_timestep = <size_t> data.shape[data.ndim - 1]
    sd.data = <double*> data.data
    sd.sample_stride = <size_t> data.strides[0] / <size_t> data.itemsize
    sd.timestep_stride = (<size_t> data.strides[data.ndim - 1] /
                          <size_t> data.itemsize)

    if data.ndim == 3:
        sd.n_dims = <size_t> data.shape[data.ndim - 2]
        sd.dim_stride = (<size_t> data.strides[data.ndim - 2] /
                         <size_t> data.itemsize)
    else:
        sd.n_dims = 1
        sd.dim_stride = 0

    return sd

cdef class DistanceMeasure:
    """A distance measure can compute the distance between time series and
    shapelets """

    def __cinit__(self, size_t n_timestep, *args, **kvargs):
        """ Initialize a new distance measure

        :param n_timesteps: the (maximum) number of timepoints in a timeseries

        :param *args: optimal arguments for subclasses

        :param **kvargs: optional arguments for subclasses
        """
        self.n_timestep = n_timestep

    def __reduce__(self):
        return self.__class__, (self.n_timestep,)

    cdef void ts_view_sub_distances(self, TSView *s, TSDatabase *td, size_t *samples, double *distances,
                                size_t n_samples) nogil:
        """ Compute the distance between the shapelet `s` in `td` and all
        samples in `samples`

        :param s: information about the shapelet
        :param td: the time series database
        :param samples: array of length `n_samples` samples to compute
        the distance to
        :param distances: array to store the distances. The the length
        of distances >= `n_samples`, the `i = 0,...,n_samples`
        position stores the distance between the i:th sample (in
        `samples`) and `s` [out param]
        :param n_samples: the number of samples 
        """
        cdef size_t p
        for p in range(n_samples):
            distances[p] = self.ts_view_sub_distance(s, td, samples[p])

    cdef int init_ts_view(
            self, TSDatabase *_td, TSView *shapelet_info, size_t index, size_t start,
            size_t length, size_t dim) nogil:
        """Return a information about a shapelet

        :param _td: shapelet database
        :param shapelet_info: [out param] 
        :param index: the index of the sample in `td`
        :param start: the start position of the subsequence
        :param length: the length of the subsequence
        :param dim: the dimension of the subsequence
        :return non-negative on success
        """
        shapelet_info[0].index = index
        shapelet_info[0].dim = dim
        shapelet_info[0].start = start
        shapelet_info[0].length = length
        shapelet_info[0].mean = NAN
        shapelet_info[0].std = NAN
        shapelet_info[0].extra = NULL
        return 0

    cdef int init_ts_copy_from_ndarray(self, TSCopy *tc, np.ndarray arr, size_t dim):
        tc[0].dim = dim
        tc[0].length = arr.shape[0]
        tc[0].mean = NAN
        tc[0].std = NAN
        tc[0].data = <double*> malloc(tc[0].length * sizeof(double))
        if tc[0].data == NULL:
            return -1

        cdef size_t i
        for i in range(tc[0].length):
            tc[0].data[i] = arr[i]
        return 0

    cdef int init_ts_copy(self, TSCopy *tc, TSView *tv_ptr, TSDatabase *td_ptr) nogil:
        cdef TSView s = tv_ptr[0]
        cdef TSDatabase td = td_ptr[0]
        ts_copy_init(tc, s.dim, s.length, s.mean, s.std)
        tc[0].ts_start = s.start
        tc[0].ts_index = s.index
        cdef double *data = tc[0].data
        cdef size_t tc_offset = (s.index * td.sample_stride +
                                 s.start * td.timestep_stride +
                                 s.dim * td.dim_stride)

        cdef size_t i
        cdef size_t p

        for i in range(s.length):
            p = tc_offset + td.timestep_stride * i
            data[i] = td.data[p]

        return 0

    cdef double ts_view_sub_distance(self, TSView *tv, TSDatabase *td_ptr, size_t t_index) nogil:
        """Return the distance between `s` and the sample specified by the
        index `t_index` in `td`. Implemented by subclasses.

        :param tv: shapelet information

        :param td_ptr: the time series database

        :param t_index: the index of the time series
        """
        with gil:
            raise NotImplementedError()

    cdef double ts_copy_sub_distance(self, TSCopy *s_ptr, TSDatabase *td_ptr, size_t t_index,
                                 size_t *return_index=NULL) nogil:
        """Return the distance between `s` and the sample specified by
        `t_index` in `td` setting the index of the best matching
        position to `return_index` unless `return_index == NULL`

        :param s_ptr: the shapelet

        :param td_ptr: the time series database

        :param t_index: the sample index

        :param return_index: (out) the index of the best matching position
        """
        with gil:
            raise NotImplementedError("sub_distance must be overridden")

    cdef int ts_copy_sub_matches(self, TSCopy *s_ptr, TSDatabase *td_ptr, size_t t_index, double threshold,
                             size_t** matches, double** distances, size_t *n_matches) nogil except -1:
        """Compute the matches for `s` in the sample `t_index` in `td` where
        the distance threshold is below `threshold`, storing the
        matching starting positions in `matches` and distance (<
        `threshold`) in `distances` with `n_matches` storing the
        number of successful matches.

        Note:

        - `matches` will be allocated and must be freed by the caller
        - `distances` will be allocated and must be freed by the caller

        :param s_ptr: the shapelet

        :param td_ptr: the time series database

        :param t_index: the sample

        :param threshold: the minimum distance to consider a match

        :param matches: (out) array of matching locations

        :param distances: (out) array of distance at the matching
        location (< `threshold`)

        :param n_matches: (out) the number of matches
        """
        with gil:
            raise NotImplementedError()

    cdef double ts_copy_distance(self, TSCopy *s, TSDatabase *td, size_t t_index) nogil:
        return self.ts_copy_sub_distance(s, td, t_index)

    cdef bint support_unaligned(self) nogil:
        return 0

cdef class ScaledDistanceMeasure(DistanceMeasure):
    """Distance measure that uses computes the distance on mean and
    variance standardized shapelets"""

    cdef int init_ts_copy_from_ndarray(self, TSCopy *tc, np.ndarray arr, size_t dim):
        cdef int err = DistanceMeasure.init_ts_copy_from_ndarray(self, tc, arr, dim)
        if err == -1:
            return -1
        tc[0].mean = np.mean(arr)
        tc[0].std = np.std(arr)
        return 0

    cdef int init_ts_view(self, TSDatabase *td, TSView *tv, size_t index, size_t start,
                          size_t length, size_t dim) nogil:
        DistanceMeasure.init_ts_view(self, td, tv, index, start, length, dim)
        _ts_view_update_statistics(tv, td)
        return -1


cdef class FuncDistanceMeasure(DistanceMeasure):
    cdef object func
    cdef np.ndarray x_buffer
    cdef np.ndarray y_buffer

    def __cinit__(self, size_t n_timestep, object func):
        self.n_timestep = n_timestep
        self.func = func
        self.x_buffer = np.empty(n_timestep, dtype=np.float64)
        self.y_buffer = np.empty(n_timestep, dtype=np.float64)


    cdef double ts_copy_sub_distance(self, TSCopy *s, TSDatabase *td, size_t t_index, size_t *return_index=NULL) nogil:
        cdef size_t i
        cdef size_t sample_offset = (t_index * td.sample_stride + s.dim * td.dim_stride)
        with gil:
            for i in range(td.n_timestep):
                if i < s.length:
                    self.x_buffer[i] = s.data[i]
                self.y_buffer[i] = td.data[sample_offset + td.timestep_stride * i]

            return self.func(self.x_buffer[:s.length], self.y_buffer)

    cdef double ts_view_sub_distance(self, TSView *s, TSDatabase *td, size_t t_index) nogil:
        cdef size_t i
        cdef size_t sample_offset = (t_index * td.sample_stride +
                                     s.dim * td.dim_stride)
        cdef size_t shapelet_offset = (s.index * td.sample_stride +
                                       s.dim * td.dim_stride +
                                       s.start * td.timestep_stride)
        with gil:
            for i in range(td.n_timestep):
                if i < s.length:
                    self.x_buffer[i] = td.data[shapelet_offset + td.timestep_stride * i]
                self.y_buffer[i] = td.data[sample_offset + td.timestep_stride * i]

            return self.func(self.x_buffer[:s.length], self.y_buffer)

    cdef double ts_copy_distance(self, TSCopy *s, TSDatabase *td, size_t t_index) nogil:
        return self.ts_copy_sub_distance(s, td, t_index)

    cdef bint support_unaligned(self) nogil:
        return False


def _validate_shapelet(shapelet):
    cdef np.ndarray s = check_array(
        shapelet, ensure_2d=False, dtype=np.float64, order="c")
    if s.ndim > 1:
        raise ValueError("only 1d shapelets allowed")

    if not s.flags.c_contiguous:
        s = np.ascontiguousarray(s, dtype=np.float64)
    return s

def _validate_data(data):
    cdef np.ndarray x = check_array(
        data, ensure_2d=False, allow_nd=True, dtype=np.float64, order="c")
    if x.ndim == 1:
        x = x.reshape(-1, x.shape[0])

    if not x.flags.c_contiguous:
        x = np.ascontiguousarray(x, dtype=np.float64)
    return x

def _check_sample(sample, n_samples):
    if sample < 0 or sample >= n_samples:
        raise ValueError("illegal sample {}".format(sample))

def _check_dim(dim, ndims):
    if dim < 0 or dim >= ndims:
        raise ValueError("illegal dimension {}".format(dim))

cdef np.ndarray _new_match_array(size_t *matches, size_t n_matches):
    if n_matches > 0:
        match_array = np.empty(n_matches, dtype=np.intp)
        for i in range(n_matches):
            match_array[i] = matches[i]
        return match_array
    else:
        return None

cdef np.ndarray _new_distance_array(
        double *distances, size_t n_matches):
    if n_matches > 0:
        dist_array = np.empty(n_matches, dtype=np.float64)
        for i in range(n_matches):
            dist_array[i] = distances[i]
        return dist_array
    else:
        return None

def new_distance_measure(metric, n_timestep, metric_params=None):
    """Create a new distance measure

    Parameters
    ----------
    metric : str or callable
        A metric name or callable

    n_timestep : int
        Number of maximum number of timesteps in the database

    metric_params : dict, optional
        Parameters to the metric

    Returns
    -------
    distance_measure : a distance measure instance
    """
    metric_params = metric_params or {}
    if isinstance(metric, str):
        if metric in _DISTANCE_MEASURE:
            distance_measure = _DISTANCE_MEASURE[metric](n_timestep, **metric_params)
        else:
            raise ValueError("metric (%s) is not supported" % metric)
    elif hasattr(metric, "__call__"):
        distance_measure = FuncDistanceMeasure(n_timestep, metric)
    else:
        raise ValueError("unknown metric, got %r" % metric)
    return distance_measure

def distance(shapelet, data, dim=0, sample=None, metric="euclidean", metric_params=None, subsequence_distance=True, return_index=False):
    cdef np.ndarray s = _validate_shapelet(shapelet)
    cdef np.ndarray x = _validate_data(data)
    if sample is None:
        if x.shape[0] == 1:
            sample = 0
        else:
            sample = np.arange(x.shape[0])
    cdef TSDatabase sd = ts_database_new(x)

    _check_dim(dim, sd.n_dims)
    cdef double min_dist
    cdef size_t min_index

    cdef double mean = 0
    cdef double std = 0

    cdef DistanceMeasure distance_measure = new_distance_measure(
        metric, sd.n_timestep, metric_params
    )

    if (
            not subsequence_distance and
            not distance_measure.support_unaligned() and
            s.shape[0] != sd.n_timestep
    ):
        raise ValueError(
            "x.shape[0] != y.shape[-1], got %r, %r" % (s.shape[0], sd.n_timestep)
        )

    if not distance_measure.support_unaligned() and s.shape[0] > sd.n_timestep:
        raise ValueError(
            "x.shape[0] > y.shape[-1], got %r, %r" % (s.shape[0], sd.n_timestep)
        )


    cdef TSCopy shape
    distance_measure.init_ts_copy_from_ndarray(&shape, s, dim)
    if isinstance(sample, int):
        if subsequence_distance:
            min_dist = distance_measure.ts_copy_sub_distance(
                &shape, &sd, sample, &min_index)
        else:
            min_dist = distance_measure.ts_copy_distance(
                &shape, &sd, sample
            )
            min_index = 0

        if return_index:
            return min_dist, min_index
        else:
            return min_dist
    else:  # assume an `array_like` object for `samples`
        samples = check_array(sample, ensure_2d=False, dtype=np.int)
        dist = []
        ind = []
        for i in samples:
            if subsequence_distance:
                min_dist = distance_measure.ts_copy_sub_distance(
                    &shape, &sd, i, &min_index
                )
            else:
                min_dist = distance_measure.ts_copy_distance(
                    &shape, &sd, sample
                )
                min_index = 0

            dist.append(min_dist)
            ind.append(min_index)

        if return_index:
            return np.array(dist), np.array(ind)
        else:
            return np.array(dist)

def matches(shapelet, X, threshold, dim=0, sample=None, metric="euclidean", metric_params=None, return_distance=False):
    cdef np.ndarray s = _validate_shapelet(shapelet)
    cdef np.ndarray x = _validate_data(X)
    _check_dim(dim, x.ndim)
    if sample is None:
        if x.shape[0] == 1:
            sample = 0
        else:
            sample = np.arange(x.shape[0])

    cdef TSDatabase sd = ts_database_new(x)

    cdef size_t *matches
    cdef double *distances
    cdef size_t n_matches

    cdef DistanceMeasure distance_measure = new_distance_measure(
        metric, sd.n_timestep, metric_params
    )
    cdef TSCopy shape
    distance_measure.init_ts_copy_from_ndarray(&shape, s, dim)
    cdef size_t i
    if isinstance(sample, int):
        _check_sample(sample, sd.n_samples)
        distance_measure.ts_copy_sub_matches(
            &shape, &sd, sample, threshold, &matches, &distances, &n_matches)

        match_array = _new_match_array(matches, n_matches)
        distance_array = _new_distance_array(distances, n_matches)
        free(distances)
        free(matches)

        if return_distance:
            return distance_array, match_array
        else:
            return match_array
    else:
        samples = check_array(sample, ensure_2d=False, dtype=np.int)
        match_list = []
        distance_list = []
        for i in samples:
            _check_sample(i, sd.n_samples)
            distance_measure.ts_copy_sub_matches(&shape, &sd, i, threshold, &matches, &distances, &n_matches)
            match_array = _new_match_array(matches, n_matches)
            distance_array = _new_distance_array(distances, n_matches)
            match_list.append(match_array)
            distance_list.append(distance_array)
            free(matches)
            free(distances)

        if return_distance:
            return distance_list, match_list
        else:
            return match_list