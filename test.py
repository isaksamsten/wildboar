import numpy as np

from pypf.tree import PfTree

# from pypf._distribution import get_class_distribution
# from pypf._impurity import safe_info

x = np.array([0, 1], dtype=np.float64)
y = np.array([0.5, 0.5], dtype=np.float64)

x = [
    [0, 0, 1, 10, 1],
    [0, 0, 1, 10, 1],
    [0, 1, 9, 1, 0],
    [1, 9, 1, 0, 0],
    [0, 1, 9, 1, 0],
    [0, 1, 2, 3, 4],
    [1, 2, 3, 0, 0],
    [0, 0, 0, 1, 2],
    [0, 0, -1, 0, 1],
    [1, 2, 3, 0, 1],
]
x = np.array(x, dtype=np.float64)
y = np.array([0, 0, 0, 0, 0, 1, 1, 1, 1, 1])

random_state = np.random.RandomState(123)
order = np.arange(10)
random_state.shuffle(order)

x = x[order, :]
y = y[order]

print(x)
print(y)

tree = PfTree(random_state=random_state)
tree.fit(x, y)

print(np.vstack([y, tree.predict(x)]))

tree.tree.prnt(1)
# print(tree.score(x, y))
# s = np.array([1, 9, 1])
# print((s - np.mean(s)) / np.std(s))

# c = pypf.tree.get_class_distribution(
#     np.array([4, 5, 6, 7, 8, 9]), np.array([1, 1, 1, 0, 1, 1, 0, 0, 0, 0]), 2)
# print(c)

train = np.loadtxt("synthetic_control_TRAIN")
test = np.loadtxt("synthetic_control_TEST")

y = train[:, 0].astype(np.intp)
y -= 1
x = train[:, 1:].astype(np.float64)

x_test = test[:, 1:].astype(np.float64)
y_test = test[:, 0].astype(np.intp)
y_test -= 1

tree = PfTree(n_shapelets=100)
#tree.fit(x, y)

from sklearn.ensemble import BaggingClassifier

bag = BaggingClassifier(
    base_estimator=tree, bootstrap=True, n_jobs=16, n_estimators=100)

from sklearn.model_selection import cross_val_score

import time
c = time.time()
bag.fit(x, y)
print(bag.score(x_test, y_test))
#score = cross_val_score(bag, x, y, cv=3)
#print(score)
print(round(time.time() - c) * 1000)
