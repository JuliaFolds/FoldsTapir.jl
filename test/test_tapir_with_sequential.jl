module TestWithSequential

using FoldsTapir
using Folds.Testing: test_with_sequential

executors = [TapirEx(), TapirEx(basesize = 1), TapirEx(basesize = 3)]

test_with_sequential(executors)

end
